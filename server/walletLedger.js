// Append-Only Wallet Ledger
// Computes balance strictly from immutable transaction records. Never allows overdrafts.

const crypto = require('crypto');

const LEDGER_ENTRY_TYPE = {
  TOPUP: 'TOPUP',
  BOOKING_DEPOSIT: 'BOOKING_DEPOSIT',
  REFUND: 'REFUND',
  WELCOME_BONUS: 'WELCOME_BONUS',
  ADMIN_ADJUSTMENT: 'ADMIN_ADJUSTMENT',
};

class WalletError extends Error {
  constructor(message, { statusCode = 400, code = 'WALLET_ERROR' } = {}) {
    super(message);
    this.name = 'WalletError';
    this.statusCode = statusCode;
    this.code = code;
  }
}

function calculateWalletBalance(userId, ledger = []) {
  if (!userId) return 0;
  return ledger
    .filter(entry => entry.userId === userId)
    .reduce((sum, entry) => sum + Number(entry.amount || 0), 0);
}

function recordLedgerEntry(ledger, {
  userId,
  amount,
  type,
  referenceId = null,
  description = '',
  actor = 'system',
}) {
  if (!userId) {
    throw new WalletError('userId is required for wallet ledger entry', { statusCode: 400 });
  }

  const numAmount = Number(amount);
  if (!Number.isFinite(numAmount) || numAmount === 0) {
    throw new WalletError('Valid non-zero amount is required', { statusCode: 400 });
  }

  const currentBalance = calculateWalletBalance(userId, ledger);

  // Overdraft protection
  if (numAmount < 0 && (currentBalance + numAmount) < -0.001) {
    throw new WalletError(
      `Insufficient wallet balance. Current: ${currentBalance.toFixed(2)} EGP, Required: ${Math.abs(numAmount).toFixed(2)} EGP`,
      { statusCode: 402, code: 'INSUFFICIENT_FUNDS' }
    );
  }

  // Welcome bonus abuse limit (max 1 per user)
  if (type === LEDGER_ENTRY_TYPE.WELCOME_BONUS) {
    const existingBonus = ledger.find(e => e.userId === userId && e.type === LEDGER_ENTRY_TYPE.WELCOME_BONUS);
    if (existingBonus) {
      throw new WalletError('Welcome gift balance has already been claimed for this account', { statusCode: 409 });
    }
  }

  const entry = {
    id: `led_${Date.now()}_${crypto.randomBytes(4).toString('hex')}`,
    userId,
    amount: Math.round(numAmount * 100) / 100,
    type,
    referenceId: referenceId ? String(referenceId) : null,
    description: String(description || '').slice(0, 200),
    actor,
    balanceAfter: Math.round((currentBalance + numAmount) * 100) / 100,
    createdAt: new Date().toISOString(),
  };

  ledger.push(entry);
  return entry;
}

module.exports = {
  LEDGER_ENTRY_TYPE,
  WalletError,
  calculateWalletBalance,
  recordLedgerEntry,
};
