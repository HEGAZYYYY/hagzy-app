// Server-Side Pricing & Promo Code Engine
// Calculates true prices, deposits, and due-now amounts. Never trusts client values.

const VALID_PROMO_CODES = {
  HAGZYVIP: {
    type: 'percentage',
    value: 20,
    maxDiscount: 100,
    minBookingAmount: 100,
    validUntil: '2027-12-31T23:59:59Z',
  },
  WELCOME26: {
    type: 'fixed',
    value: 30,
    maxDiscount: 30,
    minBookingAmount: 50,
    validUntil: '2027-12-31T23:59:59Z',
  },
  HAGZYPADEL: {
    type: 'percentage',
    value: 15,
    maxDiscount: 75,
    category: 'sports',
    minBookingAmount: 150,
    validUntil: '2027-12-31T23:59:59Z',
  },
};

class PricingError extends Error {
  constructor(message, { statusCode = 400, code = 'PRICING_ERROR' } = {}) {
    super(message);
    this.name = 'PricingError';
    this.statusCode = statusCode;
    this.code = code;
  }
}

function calculateServerPricing({
  venue,
  itemId,
  durationMinutes = 60,
  serviceIds = [],
  splitCount = 1,
  promoCode = '',
}) {
  if (!venue) {
    throw new PricingError('Venue is required for pricing calculation', { statusCode: 404 });
  }

  // 1. Find bookable unit / space
  const items = venue.units || venue.items || venue.spaces || [];
  const unit = items.find(i => String(i.id) === String(itemId));
  if (!unit) {
    throw new PricingError(`Bookable unit '${itemId}' not found in venue`, { statusCode: 404 });
  }

  const duration = Math.max(15, Math.min(720, Number(durationMinutes) || 60));
  const hourlyRate = Number(unit.hourlyRate !== undefined ? unit.hourlyRate : (unit.price || 0));
  const basePrice = Math.round((hourlyRate * (duration / 60)) * 100) / 100;

  // 2. Additive services
  const venueServices = venue.services || [];
  let servicesTotal = 0;
  const verifiedServices = [];

  if (Array.isArray(serviceIds)) {
    for (const sid of serviceIds) {
      const s = venueServices.find(vs => String(vs.id) === String(sid) || String(vs.name) === String(sid));
      if (s) {
        const sPrice = Number(s.price || 0);
        servicesTotal += sPrice;
        verifiedServices.push({ id: s.id, name: s.name, price: sPrice });
      }
    }
  }

  const subtotal = Math.round((basePrice + servicesTotal) * 100) / 100;

  // 3. Promo code verification
  let discountAmount = 0;
  let appliedPromo = null;

  if (promoCode && typeof promoCode === 'string') {
    const cleanPromo = promoCode.trim().toUpperCase();
    const rule = VALID_PROMO_CODES[cleanPromo];
    if (rule) {
      const now = new Date();
      const expires = new Date(rule.validUntil);
      if (now <= expires && subtotal >= (rule.minBookingAmount || 0)) {
        if (!rule.category || rule.category === venue.type) {
          if (rule.type === 'percentage') {
            const rawDiscount = (subtotal * rule.value) / 100;
            discountAmount = Math.min(rawDiscount, rule.maxDiscount || rawDiscount);
          } else if (rule.type === 'fixed') {
            discountAmount = Math.min(rule.value, subtotal);
          }
          discountAmount = Math.round(discountAmount * 100) / 100;
          appliedPromo = cleanPromo;
        }
      }
    }
  }

  const finalPrice = Math.max(0, Math.round((subtotal - discountAmount) * 100) / 100);

  // 4. Deposit & Due Now calculations
  const depositPercent = Math.max(0, Math.min(100, Number(venue.depositPercent !== undefined ? venue.depositPercent : 30)));
  const requiredDeposit = Math.round((finalPrice * (depositPercent / 100)) * 100) / 100;

  const validSplit = Math.max(1, Math.min(50, Math.floor(Number(splitCount) || 1)));
  let dueNow = requiredDeposit;
  if (validSplit > 1) {
    const splitShare = Math.round((finalPrice / validSplit) * 100) / 100;
    dueNow = splitShare > requiredDeposit ? splitShare : requiredDeposit;
  }

  return {
    unitId: unit.id,
    unitName: unit.name,
    durationMinutes: duration,
    hourlyRate,
    basePrice,
    servicesTotal,
    services: verifiedServices,
    subtotal,
    promoCode: appliedPromo,
    discountAmount,
    finalPrice,
    depositPercent,
    requiredDeposit,
    splitCount: validSplit,
    dueNow,
  };
}

module.exports = {
  calculateServerPricing,
  PricingError,
  VALID_PROMO_CODES,
};
