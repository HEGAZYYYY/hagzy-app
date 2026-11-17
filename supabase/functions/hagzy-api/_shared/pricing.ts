export const VALID_PROMO_CODES: Record<string, {
  type: 'fixed' | 'percentage';
  value: number;
  maxDiscount: number;
  minBookingAmount: number;
  category?: string;
  validUntil: string;
}> = {
  HAGZY50: {
    type: 'fixed',
    value: 50,
    maxDiscount: 50,
    minBookingAmount: 150,
    validUntil: '2027-12-31T23:59:59Z',
  },
  HAGZY20: {
    type: 'percentage',
    value: 20,
    maxDiscount: 100,
    minBookingAmount: 0,
    validUntil: '2027-12-31T23:59:59Z',
  },
  WELCOME: {
    type: 'percentage',
    value: 25,
    maxDiscount: 120,
    minBookingAmount: 0,
    validUntil: '2027-12-31T23:59:59Z',
  },
  PADEL100: {
    type: 'fixed',
    value: 100,
    maxDiscount: 100,
    category: 'sports',
    minBookingAmount: 350,
    validUntil: '2027-12-31T23:59:59Z',
  },
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

export class PricingError extends Error {
  statusCode: number;
  code: string;
  constructor(message: string, { statusCode = 400, code = 'PRICING_ERROR' } = {}) {
    super(message);
    this.name = 'PricingError';
    this.statusCode = statusCode;
    this.code = code;
  }
}

export function calculateServerPricing({
  venue,
  itemId,
  durationMinutes = 60,
  serviceIds = [] as string[],
  splitCount = 1,
  promoCode = '',
}: {
  venue: Record<string, any> | null;
  itemId: string;
  durationMinutes?: number;
  serviceIds?: unknown[];
  splitCount?: number;
  promoCode?: string;
}) {
  if (!venue) {
    throw new PricingError('Venue is required for pricing calculation', { statusCode: 404 });
  }

  const items: any[] = venue.units || venue.items || venue.spaces || [];
  const unit = items.find((i: any) => String(i.id) === String(itemId));
  if (!unit) {
    throw new PricingError(`Bookable unit '${itemId}' not found in venue`, { statusCode: 404 });
  }

  const duration = Math.max(15, Math.min(720, Number(durationMinutes) || 60));
  const hourlyRate = Number(
    unit.hourlyRate !== undefined ? unit.hourlyRate : (unit.pricePerHour ?? unit.price ?? venue.pricePerHour ?? 0),
  );
  const basePrice = Math.round((hourlyRate * (duration / 60)) * 100) / 100;

  const venueServices: any[] = venue.services || [];
  let servicesTotal = 0;
  const verifiedServices: any[] = [];

  if (Array.isArray(serviceIds)) {
    for (const sid of serviceIds) {
      const s = venueServices.find((vs: any) => String(vs.id) === String(sid) || String(vs.name) === String(sid));
      if (s) {
        const sPrice = Number(s.price || 0);
        servicesTotal += sPrice;
        verifiedServices.push({ id: s.id, name: s.name, price: sPrice });
      }
    }
  }

  const isSalon = String(venue.type || venue.category || '').toLowerCase() === 'salon';
  const effectiveBase = isSalon
    ? (verifiedServices.length > 0 ? 0 : Math.round((hourlyRate * (duration / 30)) * 100) / 100)
    : basePrice;
  const subtotal = Math.round((effectiveBase + servicesTotal) * 100) / 100;

  let discountAmount = 0;
  let appliedPromo: string | null = null;

  if (promoCode && typeof promoCode === 'string') {
    const cleanPromo = promoCode.trim().toUpperCase();
    const rule = VALID_PROMO_CODES[cleanPromo];
    if (rule) {
      const now = new Date();
      const expires = new Date(rule.validUntil);
      const venueType = String(venue.type || venue.category || '').toLowerCase();
      if (now <= expires && subtotal >= (rule.minBookingAmount || 0)) {
        if (!rule.category || rule.category === venueType) {
          if (rule.type === 'percentage') {
            const rawDiscount = (subtotal * rule.value) / 100;
            discountAmount = Math.min(rawDiscount, rule.maxDiscount || rawDiscount);
          } else {
            discountAmount = Math.min(rule.value, subtotal);
          }
          discountAmount = Math.round(discountAmount * 100) / 100;
          appliedPromo = cleanPromo;
        }
      }
    }
  }

  const finalPrice = Math.max(0, Math.round((subtotal - discountAmount) * 100) / 100);
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
    discountAmount,
    appliedPromo,
    finalPrice,
    depositPercent,
    depositAmount: requiredDeposit,
    dueNow,
  };
}
