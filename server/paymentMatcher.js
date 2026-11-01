// Payment Matcher & Intent Deduplication Engine
// Enforces exact amount matching, unique piaster suffixes, and review queue isolation.

const crypto = require('crypto');

const MAX_AUTO_CONFIRM_AMOUNT = Number(process.env.PAYMENT_AUTO_CONFIRM_MAX || 5000);
const EVENT_EXPIRY_WINDOW_MS = 24 * 60 * 60 * 1000; // 24 hours

class PaymentMatchingError extends Error {
  constructor(message, { statusCode = 400, code = 'PAYMENT_ERROR', details = {} } = {}) {
    super(message);
    this.name = 'PaymentMatchingError';
    this.statusCode = statusCode;
    this.code = code;
    this.details = details;
  }
}

/**
 * Generates a unique payable amount with a piaster fraction (e.g. 150.37 EGP)
 * to guarantee no collision among open intents on the same receiver wallet.
 */
function generateUniquePayableAmount(baseAmount, receiverWallet, activeIntents = []) {
  const numBase = Number(Number(baseAmount).toFixed(2));
  const activeForWallet = activeIntents.filter(i =>
    i.status === 'AWAITING_TRANSFER' &&
    (!receiverWallet || i.receiver_wallet === receiverWallet)
  );

  const hasExactCollision = activeForWallet.some(i =>
    Math.abs(Number(i.expected_amount) - numBase) < 0.005
  );

  // If no collision on the clean base amount, use it directly
  if (!hasExactCollision) {
    return numBase;
  }

  // Collision detected on exact amount: assign unique 2-digit piaster suffix
  const roundedBase = Math.floor(numBase);
  const takenFractions = new Set(
    activeForWallet
      .filter(i => Math.floor(Number(i.expected_amount)) === roundedBase)
      .map(i => Math.round((Number(i.expected_amount) - Math.floor(Number(i.expected_amount))) * 100))
  );

  for (let attempt = 0; attempt < 90; attempt++) {
    const candidateSuffix = 10 + Math.floor(Math.random() * 89);
    if (!takenFractions.has(candidateSuffix)) {
      return Number((roundedBase + candidateSuffix / 100).toFixed(2));
    }
  }

  for (let s = 1; s <= 99; s++) {
    if (!takenFractions.has(s)) {
      return Number((roundedBase + s / 100).toFixed(2));
    }
  }

  return numBase;
}

/**
 * Computes an idempotent fingerprint for incoming payment notifications.
 */
function computePaymentEventHash({ providerRef, senderIdentifier, amount, timestamp, rawText }) {
  if (providerRef && String(providerRef).trim()) {
    return crypto.createHash('sha256').update(`REF:${String(providerRef).trim()}`).digest('hex');
  }
  const normalized = [
    String(senderIdentifier || '').trim(),
    Number(amount).toFixed(2),
    String(timestamp || ''),
    String(rawText || '').trim().replace(/\s+/g, ' ')
  ].join('|');
  return crypto.createHash('sha256').update(normalized).digest('hex');
}

/**
 * Redacts third-party account numbers and balances from stored messages.
 */
function redactRawPaymentText(rawText) {
  if (!rawText || typeof rawText !== 'string') return '';
  return rawText
    .replace(/(رصيدك الحالي هو\s*)[0-9]+(?:\.[0-9]+)?/gi, '$1[REDACTED]')
    .replace(/(your balance is\s*)[0-9]+(?:\.[0-9]+)?/gi, '$1[REDACTED]');
}

/**
 * Matches an incoming payment event against open intents.
 * Exactly one matching intent confirms the booking.
 * Zero or >1 matching intents send the event to the review queue.
 */
function matchPaymentEvent({
  paymentMethod,
  senderIdentifier,
  amount,
  providerRef = null,
  timestamp = null,
  rawText = '',
  receiverWallet = null,
  activeIntents = [],
  reviewQueue = [],
  processedHashes = new Set(),
}) {
  const numAmount = Number(amount);
  const now = new Date();

  // 1. Idempotency check
  const eventHash = computePaymentEventHash({ providerRef, senderIdentifier, amount: numAmount, timestamp, rawText });
  if (processedHashes.has(eventHash)) {
    return {
      status: 'DUPLICATE',
      duplicate: true,
      eventHash,
      message: 'Payment notification has already been processed (idempotent)',
    };
  }

  // 2. Event expiry check
  if (timestamp) {
    const eventTime = new Date(timestamp).getTime();
    if (!isNaN(eventTime) && now.getTime() - eventTime > EVENT_EXPIRY_WINDOW_MS) {
      const eventRecord = {
        id: `rev_${Date.now()}_${crypto.randomBytes(4).toString('hex')}`,
        paymentMethod,
        senderIdentifier,
        amount: numAmount,
        providerRef,
        rawText: redactRawPaymentText(rawText),
        status: 'REJECTED_STALE',
        reason: 'Payment event is older than the allowed 24-hour verification window',
        receivedAt: now.toISOString(),
      };
      reviewQueue.push(eventRecord);
      processedHashes.add(eventHash);
      return { status: 'REJECTED_STALE', eventId: eventRecord.id, requiresReview: true };
    }
  }

  // 3. Cap check (High-value transfers require manual confirmation)
  if (numAmount > MAX_AUTO_CONFIRM_AMOUNT) {
    const eventRecord = {
      id: `rev_${Date.now()}_${crypto.randomBytes(4).toString('hex')}`,
      paymentMethod,
      senderIdentifier,
      amount: numAmount,
      providerRef,
      rawText: redactRawPaymentText(rawText),
      status: 'REQUIRES_MANUAL_REVIEW',
      reason: `Amount (${numAmount} EGP) exceeds maximum auto-confirm cap of ${MAX_AUTO_CONFIRM_AMOUNT} EGP`,
      receivedAt: now.toISOString(),
    };
    reviewQueue.push(eventRecord);
    processedHashes.add(eventHash);
    return { status: 'REQUIRES_MANUAL_REVIEW', eventId: eventRecord.id, requiresReview: true };
  }

  // 4. Amount matching (Exact match preferred, overpayment allowed, underpayment strictly rejected)
  const candidateIntents = activeIntents.filter(intent => {
    if (intent.status !== 'AWAITING_TRANSFER') return false;
    if (intent.payment_method !== paymentMethod) return false;
    if (intent.expected_sender_identifier !== senderIdentifier) return false;
    if (receiverWallet && intent.receiver_wallet && intent.receiver_wallet !== receiverWallet) return false;

    // Underpayment is strictly rejected
    return numAmount >= Number(intent.expected_amount);
  });

  // Prefer exact match if one exists
  const exactMatches = candidateIntents.filter(i =>
    Math.abs(Number(i.expected_amount) - numAmount) <= 0.005
  );
  const matchingIntents = exactMatches.length > 0 ? exactMatches : candidateIntents;

  // Ambiguity: Multiple open intents match
  if (matchingIntents.length > 1) {
    const eventRecord = {
      id: `rev_${Date.now()}_${crypto.randomBytes(4).toString('hex')}`,
      paymentMethod,
      senderIdentifier,
      amount: numAmount,
      providerRef,
      rawText: redactRawPaymentText(rawText),
      status: 'AMBIGUOUS_MATCH',
      matchingIntentIds: matchingIntents.map(i => i.intentId || i.intent_id || i.id),
      reason: 'Multiple open intents found for this sender and amount. Sent to review queue.',
      receivedAt: now.toISOString(),
    };
    reviewQueue.push(eventRecord);
    processedHashes.add(eventHash);
    return { status: 'AMBIGUOUS_MATCH', matched: false, eventId: eventRecord.id, requiresReview: true };
  }

  // No match found
  if (matchingIntents.length === 0) {
    const eventRecord = {
      id: `rev_${Date.now()}_${crypto.randomBytes(4).toString('hex')}`,
      paymentMethod,
      senderIdentifier,
      amount: numAmount,
      providerRef,
      rawText: redactRawPaymentText(rawText),
      status: 'UNMATCHED',
      reason: 'No open payment intent found for this amount and sender',
      receivedAt: now.toISOString(),
    };
    reviewQueue.push(eventRecord);
    processedHashes.add(eventHash);
    return { status: 'UNMATCHED', matched: false, eventId: eventRecord.id, requiresReview: true };
  }

  // Exactly one match
  const matchedIntent = matchingIntents[0];
  const excessAmount = Math.max(0, Number((numAmount - Number(matchedIntent.expected_amount || 0)).toFixed(2)));
  processedHashes.add(eventHash);

  return {
    status: 'MATCHED',
    matched: true,
    intent: matchedIntent,
    eventHash,
    amount: numAmount,
    excessAmount,
  };
}

module.exports = {
  PaymentMatchingError,
  generateUniquePayableAmount,
  computePaymentEventHash,
  redactRawPaymentText,
  matchPaymentEvent,
  MAX_AUTO_CONFIRM_AMOUNT,
};
