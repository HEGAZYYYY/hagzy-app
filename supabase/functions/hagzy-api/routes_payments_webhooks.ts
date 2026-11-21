import { Hono } from '@hono/hono';
import {
  buildBookingQrCheckInUrl,
  computeBookingQrSig,
  isUserAdmin,
  resolveUserFromToken,
  safeEqual,
} from './_shared/auth.ts';
import { processChatbotMessage } from './_shared/chatbot.ts';
import { getEnv, getSupabaseAdmin, loadFullVenueWithUnits, normalizeLocalPhone } from './_shared/db.ts';
import { notifyVenueOwner, sendSmsOrWhatsApp, sendWhatsAppMessage } from './_shared/notifications.ts';
import {
  finalizePaymentVerification,
  generateUniquePayableAmount,
  normalizeSenderId,
  parseIncomingTransferText,
  redactRawPaymentText,
  verifyWebhookHmac,
} from './_shared/payments.ts';

export function registerPaymentAndWebhookRoutes(app: Hono) {
  const supabase = getSupabaseAdmin();

  // Create payment intent (InstaPay / Vodafone Cash)
  app.post('/api/payments/intent', async c => {
    const authHeader = c.req.header('authorization') || '';
    const resolved = authHeader.startsWith('Bearer ')
      ? await resolveUserFromToken(supabase, authHeader.slice(7))
      : null;
    const body = await c.req.json().catch(() => ({}));
    const { bookingId, paymentMethod, senderIdentifier } = body || {};

    if (!bookingId || !paymentMethod || !senderIdentifier) {
      return c.json({ error: 'bookingId, paymentMethod, and senderIdentifier are required' }, 400);
    }

    const method = paymentMethod === 'MOBILE_WALLET' ? 'MOBILE_WALLET' : 'INSTAPAY';
    const normalizedSender = normalizeSenderId(method, senderIdentifier);
    if (!normalizedSender) return c.json({ error: 'Invalid sender identifier' }, 400);

    let bookingRow: Record<string, any> | null = null;
    if (!String(bookingId).startsWith('wallet_topup_')) {
      const { data } = await supabase.from('bookings').select('*').eq('id', bookingId).maybeSingle();
      bookingRow = data;
    }

    const rawAmount = bookingRow
      ? Number(bookingRow.due_now ?? bookingRow.deposit_amount ?? bookingRow.total_price ?? 0)
      : Number(body.expectedAmount ?? body.amount ?? 0);
    if (!Number.isFinite(rawAmount) || rawAmount <= 0) {
      return c.json({ error: 'Valid payable amount is required' }, 400);
    }

    let receiverWallet = method === 'INSTAPAY'
      ? getEnv('INSTAPAY_HANDLE', 'hagzy@instapay')
      : getEnv('ADMIN_PHONE', '01015325250');

    if (bookingRow?.venue_id) {
      const { data: venueRow } = await supabase
        .from('venues')
        .select('instapay_address, wallet_number, vodafone_cash_number')
        .eq('id', bookingRow.venue_id)
        .maybeSingle();
      if (venueRow) {
        if (method === 'INSTAPAY' && venueRow.instapay_address) {
          receiverWallet = String(venueRow.instapay_address).trim();
        } else if (method === 'MOBILE_WALLET' && (venueRow.vodafone_cash_number || venueRow.wallet_number)) {
          receiverWallet = String(venueRow.vodafone_cash_number || venueRow.wallet_number).trim();
        }
      }
    }

    const { data: openIntents } = await supabase
      .from('payment_intents')
      .select('*')
      .eq('status', 'AWAITING_TRANSFER');

    const payableAmount = generateUniquePayableAmount(
      rawAmount,
      receiverWallet,
      openIntents || [],
      normalizedSender,
    );
    const intentId = `pi_${Date.now()}_${crypto.randomUUID().slice(0, 6)}`;
    const now = new Date();
    const expiresAt = new Date(now.getTime() + 15 * 60 * 1000).toISOString();

    const { data: saved, error } = await supabase
      .from('payment_intents')
      .insert({
        id: intentId,
        booking_id: bookingRow ? bookingRow.id : null,
        raw_booking_id: String(bookingId),
        user_id: resolved?.userRow?.id || bookingRow?.customer_id || null,
        payment_method: method,
        receiver_wallet: receiverWallet,
        expected_sender_identifier: normalizedSender,
        expected_amount: payableAmount,
        status: 'AWAITING_TRANSFER',
        expires_at: expiresAt,
      })
      .select('*')
      .single();

    if (error || !saved) return c.json({ error: error?.message || 'Could not create payment intent' }, 500);

    // Retroactive 15-minute unclaimed payment_event matching (if customer paid just before creating intent)
    const fifteenMinAgoIso = new Date(now.getTime() - 15 * 60 * 1000).toISOString();
    const { data: unclaimedEvents } = await supabase
      .from('payment_events')
      .select('*')
      .eq('is_claimed', false)
      .eq('payment_method', method)
      .eq('sender_identifier', normalizedSender)
      .gte('received_at', fifteenMinAgoIso)
      .order('received_at', { ascending: false })
      .limit(10);

    const eligibleRetro = (unclaimedEvents || []).filter(
      evt => Number(evt.amount || 0) >= payableAmount - 0.005,
    );
    const retroactiveEvent =
      eligibleRetro.find(evt => Math.abs(Number(evt.amount || 0) - payableAmount) <= 0.005) ||
      eligibleRetro.find(evt => Number(evt.amount || 0) > payableAmount + 0.005);

    if (retroactiveEvent) {
      const evtAmount = Number(retroactiveEvent.amount || 0);
      const excessAmount = Math.max(0, Number((evtAmount - payableAmount).toFixed(2)));
      const verifiedAtIso = new Date().toISOString();

      await supabase
        .from('payment_intents')
        .update({
          status: 'VERIFIED',
          verified_at: verifiedAtIso,
          actual_amount: evtAmount,
          excess_amount: excessAmount,
        })
        .eq('id', saved.id);

      await supabase
        .from('payment_events')
        .update({
          is_claimed: true,
          matched_intent_id: saved.id,
          ...(saved.booking_id ? { booking_id: saved.booking_id } : {}),
        })
        .eq('id', retroactiveEvent.id);

      // Resolve any stale UNMATCHED review-queue entry created when the transfer arrived first
      await supabase
        .from('payment_review_queue')
        .update({
          status: 'RESOLVED',
          resolved_by: 'payment_oracle_retroactive',
          resolved_at: verifiedAtIso,
          attached_to: { bookingId: saved.booking_id || saved.raw_booking_id, intentId: saved.id },
        })
        .eq('status', 'UNMATCHED')
        .eq('payment_method', method)
        .eq('sender_identifier', normalizedSender)
        .eq('amount', evtAmount);

      if (saved.raw_booking_id?.startsWith('wallet_topup_') && saved.user_id) {
        await supabase.rpc('rpc_apply_wallet_entry_atomic', {
          p_entry_id: `led_${Date.now()}_${crypto.randomUUID().slice(0, 6)}`,
          p_user_id: saved.user_id,
          p_booking_id: null,
          p_amount: evtAmount,
          p_entry_type: 'TOPUP',
          p_reference_id: saved.id,
          p_description: `Retroactive wallet top-up via ${method}`,
          p_actor: 'payment_oracle',
        });
      } else if (saved.booking_id && bookingRow && !bookingRow.cancelled) {
        await supabase
          .from('bookings')
          .update({
            status: 'confirmed',
            confirmed: true,
            due_now: 0,
            actual_paid_amount: evtAmount,
            excess_amount: excessAmount,
            payment_method: method,
            payment_reference: retroactiveEvent.provider_ref || '',
            confirmed_at: verifiedAtIso,
            expires_at: null,
          })
          .eq('id', bookingRow.id);

        if (excessAmount > 0 && bookingRow.customer_id) {
          await supabase.rpc('rpc_apply_wallet_entry_atomic', {
            p_entry_id: `led_${Date.now()}_${crypto.randomUUID().slice(0, 6)}`,
            p_user_id: bookingRow.customer_id,
            p_booking_id: bookingRow.id,
            p_amount: excessAmount,
            p_entry_type: 'EXCESS_PAYMENT',
            p_reference_id: saved.id,
            p_description: `Excess transfer credited for booking ${bookingRow.id}`,
            p_actor: 'payment_oracle',
          });
        }

        if (bookingRow.customer_phone) {
          await sendSmsOrWhatsApp({
            phone: bookingRow.customer_phone,
            message: `✅ تم التحقق من تحويلك وتأكيد حجزك في حجزي بنجاح! رقم الحجز: ${bookingRow.id}.`,
          });
        }
        const venueObj = bookingRow.venue_id ? await loadFullVenueWithUnits(supabase, bookingRow.venue_id) : null;
        await notifyVenueOwner(supabase, {
          venue: venueObj,
          booking: { ...bookingRow, status: 'confirmed', confirmed: true, actual_paid_amount: evtAmount },
          eventType: 'booking_confirmed',
        });
      }

      saved.status = 'VERIFIED';
      saved.verified_at = verifiedAtIso;
      saved.actual_amount = evtAmount;
      saved.excess_amount = excessAmount;
    }

    return c.json({
      intentId: saved.id,
      booking_id: saved.booking_id || saved.raw_booking_id,
      user_id: saved.user_id || 'guest',
      payment_method: saved.payment_method,
      receiver_wallet: saved.receiver_wallet,
      expected_sender_identifier: saved.expected_sender_identifier,
      expected_amount: Number(saved.expected_amount),
      ...(saved.actual_amount != null ? { actual_amount: Number(saved.actual_amount) } : {}),
      ...(Number(saved.excess_amount || 0) > 0 ? { excess_amount: Number(saved.excess_amount) } : {}),
      status: saved.status,
      ...(saved.verified_at ? { verified_at: saved.verified_at } : {}),
      expires_at: saved.expires_at,
    });
  });

  app.get('/api/payments/intent/:intentId', async c => {
    const intentId = c.req.param('intentId');
    const { data: intent } = await supabase.from('payment_intents').select('*').eq('id', intentId).maybeSingle();
    if (!intent) return c.json({ error: 'Payment intent not found' }, 404);

    if (intent.status !== 'VERIFIED' && intent.booking_id) {
      const { data: b } = await supabase.from('bookings').select('status, confirmed').eq('id', intent.booking_id).maybeSingle();
      if (b && (b.status === 'confirmed' || b.confirmed)) {
        const verifiedAt = intent.verified_at || new Date().toISOString();
        await supabase.from('payment_intents').update({ status: 'VERIFIED', verified_at: verifiedAt }).eq('id', intent.id);
        intent.status = 'VERIFIED';
        intent.verified_at = verifiedAt;
      }
    }

    return c.json({
      intentId: intent.id,
      booking_id: intent.booking_id || intent.raw_booking_id,
      user_id: intent.user_id || 'guest',
      payment_method: intent.payment_method,
      receiver_wallet: intent.receiver_wallet,
      expected_sender_identifier: intent.expected_sender_identifier,
      expected_amount: Number(intent.expected_amount),
      ...(intent.actual_amount != null ? { actual_amount: Number(intent.actual_amount) } : {}),
      ...(Number(intent.excess_amount || 0) > 0 ? { excess_amount: Number(intent.excess_amount) } : {}),
      status: intent.status,
      ...(intent.verified_at ? { verified_at: intent.verified_at } : {}),
      expires_at: intent.expires_at,
    });
  });

  // Payment Webhook
  app.post('/api/payments/webhook', async c => {
    const secret = getEnv('PAYMENT_WEBHOOK_SECRET') || getEnv('PAYMENT_LISTENER_KEY');
    if (!secret) return c.json({ error: 'Webhook secret is not configured on server.' }, 503);

    const sig = c.req.header('x-signature') || c.req.header('x-hagzy-signature') || c.req.header('x-webhook-signature') || '';
    if (!sig) return c.json({ error: 'Missing signature header' }, 401);

    const rawBody = await c.req.text();
    const ts = c.req.header('x-timestamp');
    const check = await verifyWebhookHmac(secret, sig, ts, rawBody);
    if (!check.ok) return c.json({ error: check.error }, check.error?.includes('Timestamp') ? 401 : 403);

    let parsedBody: Record<string, any> = {};
    try { parsedBody = JSON.parse(rawBody); } catch (_) {}

    const result = await finalizePaymentVerification(supabase, {
      paymentMethod: parsedBody.paymentMethod || 'INSTAPAY',
      senderIdentifier: parsedBody.senderIdentifier || '',
      amount: Number(parsedBody.amount || 0),
      providerRef: parsedBody.providerRef,
      rawText: rawBody,
    });
    return c.json(result);
  });

  // Android Listener Status & Heartbeat
  const handleStatus = async (c: any) => {
    const { data: row } = await supabase.from('gateway_heartbeats').select('*').eq('id', 'default').maybeSingle();
    const lastMs = row?.last_heartbeat_at ? new Date(row.last_heartbeat_at).getTime() : null;
    const isActive = lastMs ? Date.now() - lastMs < 15 * 60 * 1000 : false;
    return c.json({
      status: 'online',
      endpoint: 'POST /api/payments/listener',
      supportedMethods: ['VODAFONE_CASH (MOBILE_WALLET)', 'INSTAPAY'],
      authMethods: ['Header: x-signature with x-timestamp', 'Header: x-listener-key'],
      serverTime: new Date().toISOString(),
      isListenerActive: isActive,
      lastHeartbeatAt: row?.last_heartbeat_at || null,
      recentLogs: Array.isArray(row?.recent_logs) ? row.recent_logs : [],
    });
  };
  app.get('/api/payments/listener/status', handleStatus);
  app.get('/api/payments/android-listener/status', handleStatus);

  const handleHeartbeat = async (c: any) => {
    const secret = getEnv('PAYMENT_LISTENER_KEY') || getEnv('PAYMENT_WEBHOOK_SECRET');
    const auth = c.req.header('authorization') || '';
    const key = c.req.header('x-listener-key') || (auth ? auth.replace(/^Bearer\s+/i, '') : '');
    if (!secret || !key || !safeEqual(key, secret)) {
      return c.json({ error: 'Unauthorized heartbeat' }, 401);
    }
    const nowIso = new Date().toISOString();
    await supabase.from('gateway_heartbeats').upsert({ id: 'default', last_heartbeat_at: nowIso });
    return c.json({ success: true, status: 'ok', serverTime: nowIso });
  };
  app.post('/api/payments/listener/heartbeat', handleHeartbeat);
  app.post('/api/payments/android-listener/heartbeat', handleHeartbeat);

  const handleListener = async (c: any) => {
    const secret = getEnv('PAYMENT_LISTENER_KEY') || getEnv('PAYMENT_WEBHOOK_SECRET');
    if (!secret) return c.json({ error: 'Payment listener secret is not configured on server.' }, 503);

    const rawBody = await c.req.text().catch(() => '');
    let payload: Record<string, any> = {};
    try { payload = rawBody ? JSON.parse(rawBody) : {}; } catch { payload = { text: rawBody }; }

    const sig = c.req.header('x-signature') || c.req.header('x-hagzy-signature');
    const ts = c.req.header('x-timestamp');
    const authHeader = c.req.header('authorization') || '';
    const key = c.req.header('x-listener-key') ||
      (authHeader ? authHeader.replace(/^Bearer\s+/i, '') : '') ||
      payload.secret || payload.key;

    let ok = false;
    if (sig) {
      if (!ts) return c.json({ error: 'Missing X-Timestamp header' }, 401);
      const hmacCheck = await verifyWebhookHmac(secret, sig, ts, rawBody || JSON.stringify(payload));
      ok = hmacCheck.ok;
    } else if (key) {
      ok = safeEqual(String(key).trim(), secret);
    }
    if (!ok) return c.json({ error: 'Unauthorized: Invalid or missing listener authentication' }, 401);

    const rawText = String(
      payload.text || payload.smsBody || payload.body || payload.message || payload.not_text || payload.notification_text || rawBody || '',
    ).split(secret).join(' ');

    const parsed = parseIncomingTransferText(rawText, payload);
    const nowIso = new Date().toISOString();
    const { data: hb } = await supabase.from('gateway_heartbeats').select('recent_logs').eq('id', 'default').maybeSingle();

    if (!parsed.amount || !parsed.senderIdentifier) {
      const looksFinancial = Boolean(
        parsed.amount ||
        /egp|جنيه|جنيها|ج\.م|جم|instapay|انستاباي|vodafone|vf-cash|vf cash|فودافون|استلام|استلمت|تحويل|إيداع|ايداع|received|recieved/i.test(rawText),
      );
      if (!looksFinancial) {
        return c.json({ error: 'Could not parse transfer amount or sender identifier from notification payload', parsed, rawText }, 422);
      }
      const revId = `rev_parse_${Date.now()}_${crypto.randomUUID().slice(0, 6)}`;
      await supabase.from('payment_review_queue').insert({
        id: revId,
        payment_method: parsed.paymentMethod || 'INSTAPAY',
        sender_identifier: parsed.senderIdentifier || 'unknown',
        amount: Number(parsed.amount || 0),
        provider_ref: parsed.providerRef || '',
        raw_text: redactRawPaymentText(rawText),
        status: 'PARSE_REVIEW',
        reason: !parsed.amount
          ? 'Financial notification received without a parseable amount — routed for manual review'
          : 'Financial notification received without a sender phone or handle — routed for manual review',
        received_at: nowIso,
      });
      const nextLogs = [
        { at: nowIso, status: 200, matched: false, requiresReview: true, parseStatus: 'PARSE_REVIEW', amount: parsed.amount || 0 },
        ...(Array.isArray(hb?.recent_logs) ? hb.recent_logs : []),
      ].slice(0, 15);
      await supabase.from('gateway_heartbeats').upsert({
        id: 'default',
        last_heartbeat_at: nowIso,
        recent_logs: nextLogs,
      });
      return c.json({
        success: true,
        matched: false,
        requiresReview: true,
        status: 'PARSE_REVIEW',
        eventId: revId,
        parsed,
        message: 'Unparsed financial notification saved to review queue.',
      });
    }

    const result = await finalizePaymentVerification(supabase, {
      paymentMethod: parsed.paymentMethod,
      senderIdentifier: parsed.senderIdentifier,
      amount: parsed.amount,
      providerRef: parsed.providerRef,
      rawText,
    });

    const nextLogs = [
      { at: nowIso, status: 200, matched: result.matched, bookingId: result.bookingId, amount: parsed.amount },
      ...(Array.isArray(hb?.recent_logs) ? hb.recent_logs : []),
    ].slice(0, 15);
    await supabase.from('gateway_heartbeats').upsert({
      id: 'default',
      last_heartbeat_at: nowIso,
      recent_logs: nextLogs,
    });

    return c.json(result);
  };
  app.post('/api/payments/listener', handleListener);
  app.post('/api/payments/android-listener', handleListener);

  app.get('/api/payments/listener', async c => {
    const q = c.req.query();
    if (!q.text && !q.smsBody && !q.message && !q.amount && !q.body && !q.not_text) {
      return c.json({ status: 'online', endpoint: 'POST /api/payments/listener', serverTime: new Date().toISOString() });
    }
    return c.json({ error: 'Use POST with authorization headers for payment events.' }, 405);
  });
  app.get('/api/payments/android-listener', async c => {
    return c.json({ status: 'online', endpoint: 'POST /api/payments/android-listener', serverTime: new Date().toISOString() });
  });

  // WhatsApp Webhook & In-App Chatbot
  const handleWhatsapp = async (c: any) => {
    try {
      const payload = await c.req.json().catch(() => ({}));
      const data = payload.data || payload;
      if (data.fromMe === true || data.fromMe === 'true') {
        return c.json({ status: 'ignored_own_message' });
      }
      const rawFrom = String(data.from || '');
      const messageBody = String(data.body || '').trim();
      if (!rawFrom || !messageBody) return c.json({ status: 'no_content' });

      const localPhone = normalizeLocalPhone(rawFrom.replace(/@.*$/, ''));
      const reply = await processChatbotMessage(supabase, { message: messageBody, senderPhone: localPhone, language: 'AR' });
      if (reply) {
        await sendSmsOrWhatsApp({ phone: rawFrom.replace(/@.*$/, ''), message: reply });
      }
      return c.json({ status: 'success', replied: true });
    } catch (err) {
      return c.json({ status: 'error', error: (err as Error).message });
    }
  };
  app.post('/api/whatsapp/webhook', handleWhatsapp);
  app.post('/api/webhook/whatsapp', handleWhatsapp);

  app.post('/api/chatbot/message', async c => {
    const { message, phone, bookingId, language } = await c.req.json().catch(() => ({}));
    if (!message || typeof message !== 'string') return c.json({ error: 'Message is required' }, 400);
    const reply = await processChatbotMessage(supabase, {
      message,
      senderPhone: phone || '',
      bookingId: bookingId || '',
      language: language || 'AR',
    });
    return c.json({ success: true, reply });
  });

  // Internal/Cron WhatsApp booking reminder dispatcher (idempotent via reminder_sent_at)
  app.post('/api/internal/run-reminders', async c => {
    const secret = getEnv('PAYMENT_LISTENER_KEY') || getEnv('PAYMENT_WEBHOOK_SECRET');
    const authHeader = c.req.header('authorization') || '';
    const keyHeader = c.req.header('x-listener-key') || (authHeader.startsWith('Bearer ') ? authHeader.slice(7) : '');
    let authorized = Boolean(secret && keyHeader && safeEqual(keyHeader.trim(), secret));
    if (!authorized && authHeader.startsWith('Bearer ')) {
      const resolved = await resolveUserFromToken(supabase, authHeader.slice(7));
      authorized = Boolean(resolved && isUserAdmin(resolved.claims));
    }
    if (!authorized) return c.json({ error: 'Unauthorized reminder runner' }, 401);

    const nowMs = Date.now();
    const nowIso = new Date(nowMs).toISOString();
    const { data: candidates } = await supabase
      .from('bookings')
      .select('*')
      .eq('confirmed', true)
      .eq('cancelled', false)
      .eq('checked_in', false)
      .is('reminder_sent_at', null)
      .gt('reminder_offset_minutes', 0)
      .gte('starts_at', nowIso)
      .order('starts_at', { ascending: true })
      .limit(100);

    const results: Record<string, any>[] = [];
    let sentCount = 0;
    for (const b of candidates || []) {
      const startsAtMs = new Date(b.starts_at).getTime();
      const offsetMins = Number(b.reminder_offset_minutes || 120);
      if (Number.isNaN(startsAtMs) || offsetMins <= 0) continue;
      if (nowMs < startsAtMs - offsetMins * 60 * 1000) continue;
      if (!b.customer_phone) {
        results.push({ bookingId: b.id, skipped: true, reason: 'no_phone' });
        continue;
      }

      const venueName = b.venue_name || b.venue_id;
      const unitLine = b.unit_name ? ` (${b.unit_name})` : '';
      const total = Number(b.total_price || 0);
      const paid = Number(b.actual_paid_amount || b.deposit_amount || 0);
      const remaining = Math.max(0, Number((total - paid).toFixed(2)));
      const sig = await computeBookingQrSig(b.id, b.venue_id);
      const qrUrl = buildBookingQrCheckInUrl(b.id, sig);
      const msg = [
        `⏰ *تذكير بموعد حجزك في حجزي*`,
        `🏟️ المكان: ${venueName}${unitLine}`,
        `📅 الموعد: ${b.starts_at}`,
        `💰 المتبقي للدفع بالمكان: ${remaining} ج.م`,
        `🎫 رابط كود الدخول QR: ${qrUrl}`,
        `🆔 رقم الحجز: ${b.id}`,
      ].join('\n');

      const sendRes = await sendWhatsAppMessage({ phone: b.customer_phone, message: msg });
      if (sendRes.sent) {
        await supabase.from('bookings').update({ reminder_sent_at: nowIso }).eq('id', b.id);
        sentCount++;
      }
      results.push({ bookingId: b.id, sent: Boolean(sendRes.sent), provider: sendRes.provider });
    }

    return c.json({
      success: true,
      checkedAt: nowIso,
      dueEvaluated: (candidates || []).length,
      sentCount,
      results,
    });
  });
}
