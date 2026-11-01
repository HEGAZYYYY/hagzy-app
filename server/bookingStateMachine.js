// Booking State Machine
// Centralizes transitions and invariants for booking lifecycles.

const BOOKING_STATUS = {
  PENDING_PAYMENT: 'pending_payment',
  CONFIRMED: 'confirmed',
  COMPLETED: 'completed',
  CANCELLED: 'cancelled',
  EXPIRED: 'expired',
  NO_SHOW: 'no_show',
};

const ALLOWED_TRANSITIONS = {
  [BOOKING_STATUS.PENDING_PAYMENT]: [
    BOOKING_STATUS.CONFIRMED,
    BOOKING_STATUS.EXPIRED,
    BOOKING_STATUS.CANCELLED,
  ],
  [BOOKING_STATUS.CONFIRMED]: [
    BOOKING_STATUS.COMPLETED,
    BOOKING_STATUS.CANCELLED,
    BOOKING_STATUS.NO_SHOW,
  ],
  [BOOKING_STATUS.EXPIRED]: [],
  [BOOKING_STATUS.CANCELLED]: [],
  [BOOKING_STATUS.COMPLETED]: [],
  [BOOKING_STATUS.NO_SHOW]: [],
};

class StateMachineError extends Error {
  constructor(message, { statusCode = 409, code = 'ILLEGAL_TRANSITION', details = {} } = {}) {
    super(message);
    this.name = 'StateMachineError';
    this.statusCode = statusCode;
    this.code = code;
    this.details = details;
  }
}

function canTransition(currentStatus, nextStatus) {
  const normalizedCurrent = (currentStatus || BOOKING_STATUS.PENDING_PAYMENT).toLowerCase();
  const normalizedNext = (nextStatus || '').toLowerCase();

  if (normalizedCurrent === normalizedNext) return true; // Idempotent no-op

  const allowed = ALLOWED_TRANSITIONS[normalizedCurrent] || [];
  return allowed.includes(normalizedNext);
}

function transitionBookingStatus(booking, nextStatus, { actor = 'system', reason = '', auditLog = [] } = {}) {
  if (!booking) {
    throw new StateMachineError('Booking not found', { statusCode: 404, code: 'BOOKING_NOT_FOUND' });
  }

  const current = (booking.status || BOOKING_STATUS.PENDING_PAYMENT).toLowerCase();
  const target = (nextStatus || '').toLowerCase();

  if (current === target) {
    return booking; // Idempotent
  }

  if (!canTransition(current, target)) {
    throw new StateMachineError(
      `Illegal booking transition from '${current}' to '${target}'. Confirmed/cancelled bookings cannot be revived.`,
      {
        statusCode: 409,
        code: 'ILLEGAL_TRANSITION',
        details: { current, target, bookingId: booking.id }
      }
    );
  }

  const previousStatus = booking.status;
  booking.status = target;
  booking.updatedAt = new Date().toISOString();

  if (target === BOOKING_STATUS.CONFIRMED) {
    booking.confirmed = true;
    booking.isPendingPayment = false;
    booking.depositPaid = true;
    booking.paymentStatus = 'paid';
    booking.holdExpiresAt = null;
    booking.dueNow = 0;
  } else if (target === BOOKING_STATUS.CANCELLED) {
    booking.cancelled = true;
    booking.isPendingPayment = false;
    booking.holdExpiresAt = null;
  } else if (target === BOOKING_STATUS.EXPIRED) {
    booking.isPendingPayment = false;
    booking.cancelled = false;
  }

  const auditEntry = {
    id: `aud_${Date.now()}_${Math.random().toString(36).substring(2, 7)}`,
    bookingId: booking.id,
    fromStatus: previousStatus,
    toStatus: target,
    actor,
    reason,
    timestamp: new Date().toISOString(),
  };

  auditLog.push(auditEntry);
  booking.lastAuditEntry = auditEntry;

  return booking;
}

module.exports = {
  BOOKING_STATUS,
  ALLOWED_TRANSITIONS,
  StateMachineError,
  canTransition,
  transitionBookingStatus,
};
