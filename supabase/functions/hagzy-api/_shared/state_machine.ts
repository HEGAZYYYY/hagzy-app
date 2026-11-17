export const BOOKING_STATUS = {
  PENDING_PAYMENT: 'pending_payment',
  CONFIRMED: 'confirmed',
  COMPLETED: 'completed',
  CANCELLED: 'cancelled',
  EXPIRED: 'expired',
  NO_SHOW: 'no_show',
} as const;

export const ALLOWED_TRANSITIONS: Record<string, string[]> = {
  [BOOKING_STATUS.PENDING_PAYMENT]: [
    BOOKING_STATUS.CONFIRMED,
    BOOKING_STATUS.EXPIRED,
    BOOKING_STATUS.CANCELLED,
  ],
  pending: [BOOKING_STATUS.CONFIRMED, BOOKING_STATUS.EXPIRED, BOOKING_STATUS.CANCELLED],
  awaiting_payment: [BOOKING_STATUS.CONFIRMED, BOOKING_STATUS.EXPIRED, BOOKING_STATUS.CANCELLED],
  pending_confirmation: [BOOKING_STATUS.CONFIRMED, BOOKING_STATUS.CANCELLED],
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

export class StateMachineError extends Error {
  statusCode: number;
  code: string;
  constructor(message: string, { statusCode = 409, code = 'ILLEGAL_TRANSITION' } = {}) {
    super(message);
    this.name = 'StateMachineError';
    this.statusCode = statusCode;
    this.code = code;
  }
}

export function canTransition(currentStatus: string, nextStatus: string): boolean {
  const normalizedCurrent = (currentStatus || BOOKING_STATUS.PENDING_PAYMENT).toLowerCase();
  const normalizedNext = (nextStatus || '').toLowerCase();
  if (normalizedCurrent === normalizedNext) return true;
  const allowed = ALLOWED_TRANSITIONS[normalizedCurrent] || [];
  return allowed.includes(normalizedNext);
}
