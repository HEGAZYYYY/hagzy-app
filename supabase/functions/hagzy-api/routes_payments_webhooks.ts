import { Hono } from '@hono/hono';
import { resolveUserFromToken, safeEqual } from './_shared/auth.ts';
import { processChatbotMessage } from './_shared/chatbot.ts';
import { getEnv, getSupabaseAdmin, normalizeLocalPhone } from './_shared/db.ts';
import { sendSmsOrWhatsApp } from './_shared/notifications.ts';
import {
  finalizePaymentVerification,
  generateUniquePayableAmount,
  normalizeSenderId,
  parseIncomingTransferText,
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

    const receiverWallet = method === 'INSTAPAY'
      ? getEnv('INSTAPAY_HANDLE', 'hagzy@instapay')
      : getEnv('ADMIN_PHONE', '01015325250');

    const { data: openIntents } = await supabase
      .from('payment_intents')
      .select('*')
      .eq('status', 'AWAITING_TRANSFER');

    const payableAmount = generateUniquePayableAmount(rawAmount, receiverWallet, openIntents || []);
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

    return c.json({
      intentId: saved.id,
      booking_id: saved.booking_id || saved.raw_booking_id,
      user_id: saved.user_id || 'guest',
      payment_method: saved.payment_method,
      receiver_wallet: saved.receiver_wallet,
      expected_sender_identifier: saved.expected_sender_identifier,
      expected_amount: Number(saved.expected_amount),
      status: saved.status,
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
    if (!parsed.amount || !parsed.senderIdentifier) {
      return c.json({ error: 'Could not parse transfer amount or sender identifier from notification payload', parsed, rawText }, 422);
    }

    const nowIso = new Date().toISOString();
    const { data: hb } = await supabase.from('gateway_heartbeats').select('recent_logs').eq('id', 'default').maybeSingle();
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
}
