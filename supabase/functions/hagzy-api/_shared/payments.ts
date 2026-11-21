import { SupabaseClient } from '@supabase/supabase-js';
import { hmacSha256Hex, safeEqual, sha256Hex } from './auth.ts';
import { getEnv, loadFullVenueWithUnits, normalizeLocalPhone } from './db.ts';
import { notifyVenueOwner, sendSmsOrWhatsApp } from './notifications.ts';

const EVENT_EXPIRY_WINDOW_MS = 24 * 60 * 60 * 1000;

export function convertEasternArabicNumerals(str: unknown): string {
  if (!str || typeof str !== 'string') return '';
  const eastern = ['٠', '١', '٢', '٣', '٤', '٥', '٦', '٧', '٨', '٩'];
  const extended = ['۰', '۱', '۲', '۳', '۴', '۵', '۶', '۷', '۸', '۹'];
  let out = str
    .replace(/[\u200E\u200F\u202A-\u202E\u2066-\u2069]/g, '')
    .replace(/[٠-٩]/g, d => String(eastern.indexOf(d)))
    .replace(/[۰-۹]/g, d => String(extended.indexOf(d)))
    .replace(/٫/g, '.')
    .replace(/٬/g, '');
  let prev = '';
  while (out !== prev) {
    prev = out;
    out = out.replace(/(\d),(\d{3})(?!\d)/g, '$1$2');
  }
  return out;
}

export function normalizeSenderId(method: string, raw: unknown): string {
  if (!raw || typeof raw !== 'string') return '';
  const trimmed = convertEasternArabicNumerals(raw).trim();
  if (method === 'INSTAPAY') {
    let handle = trimmed.toLowerCase().replace(/(@instapay)+$/gi, '').trim();
    handle = handle.replace(/[^a-z0-9_.-]/g, '');
    return handle ? `${handle}@instapay` : '';
  }
  if (method === 'MOBILE_WALLET') {
    let phone = trimmed.replace(/[\s\-+()]/g, '');
    if (phone.startsWith('0020')) phone = phone.slice(4);
    else if (phone.startsWith('20')) phone = phone.slice(2);
    if (phone.length === 10 && /^[125]\d{8}$/.test(phone)) phone = `0${phone}`;
    return phone;
  }
  return trimmed;
}

export function redactRawPaymentText(rawText: unknown): string {
  if (!rawText || typeof rawText !== 'string') return '';
  return rawText
    .replace(/(رصيدك الحالي هو\s*)[0-9]+(?:\.[0-9]+)?/gi, '$1[REDACTED]')
    .replace(/(your balance is\s*)[0-9]+(?:\.[0-9]+)?/gi, '$1[REDACTED]');
}

export function generateUniquePayableAmount(
  baseAmount: number,
  receiverWallet: string,
  activeIntents: Record<string, any>[],
  senderIdentifier = '',
): number {
  const numBase = Number(Number(baseAmount).toFixed(2));
  const cleanSender = senderIdentifier ? String(senderIdentifier).trim().toLowerCase() : '';
  const activeForScope = activeIntents.filter(i => {
    if (i.status !== 'AWAITING_TRANSFER') return false;
    if (receiverWallet && i.receiver_wallet && i.receiver_wallet !== receiverWallet) return false;
    if (cleanSender) {
      const intentSender = String(i.expected_sender_identifier || '').trim().toLowerCase();
      if (intentSender && intentSender !== cleanSender) return false;
    }
    return true;
  });
  const collision = activeForScope.some(i => Math.abs(Number(i.expected_amount) - numBase) < 0.005);
  if (!collision) return numBase;

  const roundedBase = Math.floor(numBase);
  const taken = new Set(
    activeForScope
      .filter(i => Math.floor(Number(i.expected_amount)) === roundedBase)
      .map(i => Math.round((Number(i.expected_amount) - Math.floor(Number(i.expected_amount))) * 100)),
  );
  for (let s = 10; s <= 99; s++) {
    if (!taken.has(s)) return Number((roundedBase + s / 100).toFixed(2));
  }
  for (let s = 1; s <= 9; s++) {
    if (!taken.has(s)) return Number((roundedBase + s / 100).toFixed(2));
  }
  return numBase;
}

export function parseIncomingTransferText(rawText: string, metadata: Record<string, any> = {}) {
  const fullText = convertEasternArabicNumerals(
    `${rawText || ''} ${metadata.title || ''} ${metadata.text || ''} ${metadata.body || ''} ${metadata.smsBody || ''} ${metadata.appName || ''} ${metadata.package || ''}`,
  )
    .replace(/[\[\{](?:not_text|not_title|sms_body|sms_number|notification_text)[\]\}]/gi, ' ')
    .trim();

  let amount: number | null = metadata.amount && Number(metadata.amount) > 0 ? Number(metadata.amount) : null;
  let paymentMethod: 'INSTAPAY' | 'MOBILE_WALLET' | null = metadata.paymentMethod
    ? (metadata.paymentMethod === 'MOBILE_WALLET' ? 'MOBILE_WALLET' : 'INSTAPAY')
    : null;
  let senderIdentifier: string | null = metadata.senderIdentifier ? String(metadata.senderIdentifier).trim() : null;
  let providerRef: string | null = null;

  const isVodafone =
    /vodafone|vf-cash|فودافون|vfcash|vf cash/i.test(fullText) ||
    /^(VF-Cash|Vodafone|VF)$/i.test(String(metadata.sender || metadata.smsSender || ''));
  const isInstapay =
    /instapay|انستاباي|انستا باي|@instapay|لحظي|حوالة عبر انستاباي/i.test(fullText) ||
    /mysrv|instapay/i.test(String(metadata.package || metadata.appName || ''));

  if (!paymentMethod) {
    if (isInstapay) paymentMethod = 'INSTAPAY';
    else if (isVodafone || /01[0125]\d{8}/.test(fullText)) paymentMethod = 'MOBILE_WALLET';
    else paymentMethod = 'INSTAPAY';
  }

  if (amount === null) {
    const regexes = [
      /(?:فودافون كاش|vf[\s-]*cash|أرسلت|ارسلت|وصلتك|حول لك|تم تحويل|تم إيداع|تم ايداع|مبلغ|بمبلغ|بقيمة|قيمة|استلام|استلمت|تحويل|إيداع|ايداع)[:\s-]+(?:مبلغ\s+)?([0-9]+(?:\.[0-9]+)?)\s*(?:جنيه|جنيها|ج\.م|جم|ج م|egp|le)/i,
      /(?:received|recieved|you have received|you have recieved|you received|you recieved|transfer of)[:\s]+(?:egp|le)?\s*([0-9]+(?:\.[0-9]+)?)/i,
      /(?:received|recieved|you have received|you have recieved|you received|you recieved|transfer of)[:\s]+([0-9]+(?:\.[0-9]+)?)\s*(?:egp|le)?/i,
      /([0-9]+(?:\.[0-9]+)?)\s*(?:egp|le|جنيه|جنيها|ج\.م|جم)\s+(?:received|recieved|from|من|successfully)/i,
      /(?:مبلغ|بمبلغ|بقيمة|قيمة|استلام|استلمت|تحويل|إيداع|ايداع)\s+([0-9]+(?:\.[0-9]+)?)\s*(?:جنيه|جنيها|ج\.م|جم|ج م|egp|le)/i,
      /(?:received|recieved|you have received|you have recieved|you received|you recieved|transfer of)\s+(?:egp|le)?\s*([0-9]+(?:\.[0-9]+)?)/i,
      /(?:received|recieved|you have received|you have recieved|you received|you recieved|transfer of)\s+([0-9]+(?:\.[0-9]+)?)\s*(?:egp|le)?/i,
      /([0-9]+(?:\.[0-9]+)?)\s*(?:egp|le|جنيه|ج\.م|جم)\s+(?:received|recieved|from|من)/i,
      /(?:مبلغ|بمبلغ|بقيمة)\s+([0-9]+(?:\.[0-9]+)?)/i,
      /([0-9]+(?:\.[0-9]+)?)\s*(?:جنيه|جنيها|ج\.م|جم|egp|le)/i,
    ];
    for (const rx of regexes) {
      const m = fullText.match(rx);
      if (m?.[1]) {
        const val = parseFloat(m[1]);
        if (!Number.isNaN(val) && val > 0) {
          amount = val;
          break;
        }
      }
    }
  }

  const receiverWallets = new Set(
    [
      normalizeLocalPhone(getEnv('ADMIN_PHONE', '01015325250')),
      '01041570557',
      ...getEnv('RECEIVER_WALLETS').split(',').map(normalizeLocalPhone),
    ].filter(Boolean),
  );

  if (!senderIdentifier) {
    if (paymentMethod === 'MOBILE_WALLET') {
      const explicit = fullText.match(/(?:من\s+رقم|من|from\s+number|from)\s+(01[0125][0-9]{8})/i);
      if (explicit?.[1] && !receiverWallets.has(explicit[1])) {
        senderIdentifier = explicit[1];
      } else {
        const all = fullText.match(/01[0125][0-9]{8}/g) || [];
        senderIdentifier = all.find(p => !receiverWallets.has(p)) || (all.length === 1 ? all[0] : null);
      }
    } else {
      const handleMatch = fullText.match(/([a-zA-Z0-9._-]+@instapay)/i);
      if (handleMatch?.[1] && !receiverWallets.has(normalizeLocalPhone(handleMatch[1]))) {
        senderIdentifier = handleMatch[1];
      } else {
        const all = fullText.match(/01[0125][0-9]{8}/g) || [];
        senderIdentifier = all.find(p => !receiverWallets.has(p)) || null;
      }
    }
  }

  const refMatch = fullText.match(/(?:رقم العملية|مرجع|المرجع|ref(?:erence)?[:\s_-]+)([0-9a-zA-Z_-]+)/i);
  if (refMatch?.[1]) providerRef = refMatch[1];

  return {
    amount,
    paymentMethod,
    senderIdentifier: senderIdentifier ? normalizeSenderId(paymentMethod, senderIdentifier) : null,
    providerRef: providerRef || `auto_${Date.now()}`,
    rawText,
  };
}

export async function verifyWebhookHmac(
  secret: string,
  signature: string,
  timestamp: string | undefined,
  rawBody: string,
): Promise<{ ok: boolean; error?: string }> {
  if (timestamp) {
    const diff = Math.abs(Date.now() - Number(timestamp));
    if (Number.isNaN(diff) || diff > 5 * 60 * 1000) {
      return { ok: false, error: 'Timestamp expired or invalid (max 5m drift)' };
    }
    const expected = await hmacSha256Hex(secret, `${rawBody}.${timestamp}`);
    return safeEqual(signature, expected) ? { ok: true } : { ok: false, error: 'Invalid HMAC signature' };
  }
  const expected = await hmacSha256Hex(secret, rawBody);
  return safeEqual(signature, expected) ? { ok: true } : { ok: false, error: 'Invalid HMAC signature' };
}

export async function finalizePaymentVerification(
  supabase: SupabaseClient,
  {
    paymentMethod,
    senderIdentifier,
    amount,
    providerRef,
    rawText = '',
    timestamp = null,
    receiverWallet = null,
  }: {
    paymentMethod: string;
    senderIdentifier: string;
    amount: number;
    providerRef?: string | null;
    rawText?: string;
    timestamp?: string | number | null;
    receiverWallet?: string | null;
  },
) {
  const maxAutoCap = Number(getEnv('PAYMENT_AUTO_CONFIRM_MAX', '5000'));
  const method = paymentMethod === 'MOBILE_WALLET' ? 'MOBILE_WALLET' : 'INSTAPAY';
  const normalizedSender = normalizeSenderId(method, senderIdentifier);
  const numAmount = Number(amount);
  const now = new Date();
  const redactedRaw = redactRawPaymentText(rawText);
  const eventId = `evt_${Date.now()}_${crypto.randomUUID().slice(0, 5)}`;

  // 1. Idempotency check in DB
  const eventHash = providerRef && String(providerRef).trim()
    ? await sha256Hex(`REF:${String(providerRef).trim()}`)
    : await sha256Hex([
      normalizedSender,
      numAmount.toFixed(2),
      String(timestamp || ''),
      rawText.trim().replace(/\s+/g, ' '),
    ].join('|'));

  const { data: dup } = await supabase
    .from('payment_event_hashes')
    .select('event_hash')
    .eq('event_hash', eventHash)
    .maybeSingle();

  if (dup) {
    return {
      success: true,
      duplicate: true,
      matched: false,
      eventHash,
      message: 'Payment notification has already been processed (idempotent)',
    };
  }

  // Record raw incoming payment event
  await supabase.from('payment_events').insert({
    id: eventId,
    payment_method: method,
    sender_identifier: normalizedSender,
    amount: numAmount,
    provider_ref: providerRef || '',
    is_claimed: false,
    raw_text: redactedRaw,
    received_at: now.toISOString(),
  });
  await supabase.from('payment_event_hashes').upsert({ event_hash: eventHash, payment_event_id: eventId });

  // 2. Stale event check (>24h)
  if (timestamp) {
    const evtTime = new Date(timestamp).getTime();
    if (!Number.isNaN(evtTime) && now.getTime() - evtTime > EVENT_EXPIRY_WINDOW_MS) {
      const revId = `rev_${Date.now()}_${crypto.randomUUID().slice(0, 6)}`;
      await supabase.from('payment_review_queue').insert({
        id: revId,
        payment_method: method,
        sender_identifier: normalizedSender,
        amount: numAmount,
        provider_ref: providerRef || '',
        raw_text: redactedRaw,
        status: 'REJECTED_STALE',
        reason: 'Payment event is older than the allowed 24-hour verification window',
        received_at: now.toISOString(),
      });
      return { success: true, matched: false, status: 'REJECTED_STALE', eventId: revId, requiresReview: true };
    }
  }

  // 3. Auto-confirm cap check
  if (numAmount > maxAutoCap) {
    const revId = `rev_${Date.now()}_${crypto.randomUUID().slice(0, 6)}`;
    await supabase.from('payment_review_queue').insert({
      id: revId,
      payment_method: method,
      sender_identifier: normalizedSender,
      amount: numAmount,
      provider_ref: providerRef || '',
      raw_text: redactedRaw,
      status: 'REQUIRES_MANUAL_REVIEW',
      reason: `Amount (${numAmount} EGP) exceeds maximum auto-confirm cap of ${maxAutoCap} EGP`,
      received_at: now.toISOString(),
    });
    return { success: true, matched: false, status: 'REQUIRES_MANUAL_REVIEW', eventId: revId, requiresReview: true };
  }

  // 4. Fetch open AWAITING_TRANSFER intents
  let { data: openIntents } = await supabase
    .from('payment_intents')
    .select('*')
    .eq('status', 'AWAITING_TRANSFER')
    .eq('payment_method', method)
    .eq('expected_sender_identifier', normalizedSender);

  // Cross-method fallback: customer picked InstaPay on screen but transferred to Vodafone Cash wallet (or vice-versa)
  if (!openIntents || openIntents.length === 0) {
    const { data: crossIntents } = await supabase
      .from('payment_intents')
      .select('*')
      .eq('status', 'AWAITING_TRANSFER')
      .eq('expected_sender_identifier', normalizedSender);
    openIntents = crossIntents;
  }

  const candidates = (openIntents || []).filter(i =>
    !receiverWallet || !i.receiver_wallet || i.receiver_wallet === receiverWallet,
  );
  const exactMatches = candidates.filter(i => {
    const expected = Number(i.expected_amount || 0);
    return Math.abs(numAmount - expected) <= 0.005;
  });
  const overMatches = candidates.filter(i => {
    const expected = Number(i.expected_amount || 0);
    return numAmount > expected + 0.005;
  });
  const matching = exactMatches.length > 0 ? exactMatches : overMatches;

  if (matching.length > 1) {
    const revId = `rev_${Date.now()}_${crypto.randomUUID().slice(0, 6)}`;
    await supabase.from('payment_review_queue').insert({
      id: revId,
      payment_method: method,
      sender_identifier: normalizedSender,
      amount: numAmount,
      provider_ref: providerRef || '',
      raw_text: redactedRaw,
      status: 'AMBIGUOUS_MATCH',
      reason: 'Multiple open intents found for this sender and amount. Sent to review queue.',
      extra: { matchingIntentIds: matching.map(i => i.id) },
      received_at: now.toISOString(),
    });
    return { success: true, matched: false, status: 'AMBIGUOUS_MATCH', eventId: revId, requiresReview: true };
  }

  if (matching.length === 1) {
    const intent = matching[0];
    const excessAmount = Math.max(0, Number((numAmount - Number(intent.expected_amount || 0)).toFixed(2)));

    await supabase
      .from('payment_intents')
      .update({
        status: 'VERIFIED',
        verified_at: now.toISOString(),
        actual_amount: numAmount,
        excess_amount: excessAmount,
      })
      .eq('id', intent.id);

    await supabase
      .from('payment_events')
      .update({
        is_claimed: true,
        matched_intent_id: intent.id,
        ...(intent.booking_id ? { booking_id: intent.booking_id } : {}),
      })
      .eq('id', eventId);

    if (intent.raw_booking_id?.startsWith('wallet_topup_') && intent.user_id) {
      await supabase.rpc('rpc_apply_wallet_entry_atomic', {
        p_entry_id: `led_${Date.now()}_${crypto.randomUUID().slice(0, 6)}`,
        p_user_id: intent.user_id,
        p_booking_id: null,
        p_amount: numAmount,
        p_entry_type: 'TOPUP',
        p_reference_id: intent.id,
        p_description: `Automated wallet top-up via ${method}`,
        p_actor: 'payment_oracle',
      });
      return { success: true, matched: true, walletTopUp: true, amount: numAmount, excessAmount };
    }

    if (intent.booking_id) {
      const { data: b } = await supabase
        .from('bookings')
        .select('*')
        .eq('id', intent.booking_id)
        .maybeSingle();

      if (b) {
        const bEnds = new Date(new Date(b.starts_at).getTime() + Number(b.duration_minutes || 60) * 60000).toISOString();
        const { data: conflicts } = await supabase
          .from('bookings')
          .select('id, status, confirmed, expires_at')
          .eq('venue_id', b.venue_id)
          .eq('cancelled', false)
          .neq('id', b.id)
          .not('status', 'in', '("cancelled","expired","no_show")')
          .lt('starts_at', bEnds)
          .gt('ends_at', b.starts_at);

        const activeConflict = (conflicts || []).some(c =>
          c.status === 'confirmed' || c.confirmed || !c.expires_at || new Date(c.expires_at).getTime() > Date.now(),
        );

        if (activeConflict) {
          const revId = `rev_conflict_${Date.now()}`;
          await supabase.from('payment_review_queue').insert({
            id: revId,
            intent_id: intent.id,
            booking_id: b.id,
            payment_method: method,
            sender_identifier: normalizedSender,
            amount: numAmount,
            provider_ref: providerRef || '',
            raw_text: redactedRaw,
            status: 'SLOT_CONFLICT',
            reason: 'Booking slot is already booked by another confirmed reservation.',
            received_at: now.toISOString(),
          });
          return {
            success: true,
            matched: false,
            requiresReview: true,
            status: 'SLOT_CONFLICT',
            message: 'Slot conflict: booking slot was taken by another reservation. Sent to review queue.',
          };
        }

        await supabase
          .from('bookings')
          .update({
            status: 'confirmed',
            confirmed: true,
            due_now: 0,
            actual_paid_amount: numAmount,
            excess_amount: excessAmount,
            payment_method: method,
            payment_reference: providerRef || '',
            confirmed_at: now.toISOString(),
            expires_at: null,
          })
          .eq('id', b.id);

        await supabase.from('audit_log').insert({
          id: `aud_${Date.now()}_${crypto.randomUUID().slice(0, 5)}`,
          booking_id: b.id,
          venue_id: b.venue_id,
          user_id: b.customer_id,
          action: 'booking_confirmed',
          from_status: b.status,
          to_status: 'confirmed',
          actor: 'payment_oracle',
          reason: 'Automated exact payment match',
        });

        if (excessAmount > 0 && b.customer_id) {
          await supabase.rpc('rpc_apply_wallet_entry_atomic', {
            p_entry_id: `led_${Date.now()}_${crypto.randomUUID().slice(0, 6)}`,
            p_user_id: b.customer_id,
            p_booking_id: b.id,
            p_amount: excessAmount,
            p_entry_type: 'EXCESS_PAYMENT',
            p_reference_id: intent.id,
            p_description: `Excess transfer credited to wallet for booking ${b.id}`,
            p_actor: 'payment_oracle',
          });
        }

        if (b.customer_phone) {
          await sendSmsOrWhatsApp({
            phone: b.customer_phone,
            message: `✅ تم استلام التحويل وتأكيد حجزك في حجزي بنجاح! رقم الحجز: ${b.id}.`,
          });
        }

        const venueObj = b.venue_id ? await loadFullVenueWithUnits(supabase, b.venue_id) : null;
        await notifyVenueOwner(supabase, {
          venue: venueObj,
          booking: { ...b, status: 'confirmed', confirmed: true, actual_paid_amount: numAmount },
          eventType: 'booking_confirmed',
        });

        return { success: true, matched: true, bookingId: b.id, amount: numAmount, excessAmount };
      }
    }
  }

  // No open intent matched -> route to payment_review_queue cleanly
  const revId = `rev_${Date.now()}_${crypto.randomUUID().slice(0, 6)}`;
  await supabase.from('payment_review_queue').insert({
    id: revId,
    payment_method: method,
    sender_identifier: normalizedSender,
    amount: numAmount,
    provider_ref: providerRef || '',
    raw_text: redactedRaw,
    status: 'UNMATCHED',
    reason: 'No open payment intent found for this amount and sender',
    received_at: now.toISOString(),
  });

  return {
    success: true,
    matched: false,
    status: 'UNMATCHED',
    eventId: revId,
    amount: numAmount,
    paymentMethod: method,
    senderIdentifier: normalizedSender,
    requiresReview: true,
    message: 'Payment notification recorded.',
  };
}
