import { createClient, SupabaseClient } from '@supabase/supabase-js';

let cachedAdminClient: SupabaseClient | null = null;
let cachedAuthClient: SupabaseClient | null = null;

export function getEnv(name: string, fallback = ''): string {
  return (Deno.env.get(name) ?? fallback).trim();
}

export function getSupabaseAdmin(): SupabaseClient {
  if (cachedAdminClient) return cachedAdminClient;
  const url = getEnv('SUPABASE_URL');
  const serviceKey = getEnv('SUPABASE_SERVICE_ROLE_KEY');
  if (!url || !serviceKey) {
    throw new Error('SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY are required');
  }
  cachedAdminClient = createClient(url, serviceKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  });
  return cachedAdminClient;
}

export function getSupabaseAnon(): SupabaseClient {
  if (cachedAuthClient) return cachedAuthClient;
  const url = getEnv('SUPABASE_URL');
  const anonKey = getEnv('SUPABASE_ANON_KEY') || getEnv('SUPABASE_PUBLISHABLE_KEY');
  if (!url || !anonKey) {
    return getSupabaseAdmin();
  }
  cachedAuthClient = createClient(url, anonKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  });
  return cachedAuthClient;
}

export function normalizeLocalPhone(rawPhone: unknown): string {
  if (!rawPhone) return '';
  let digits = String(rawPhone).replace(/\D/g, '');
  if (!digits) return '';
  if (digits.startsWith('0020')) digits = digits.slice(4);
  else if (digits.startsWith('20') && digits.length >= 12) digits = digits.slice(2);
  if (digits.length === 10 && /^[125]\d{8}/.test(digits)) digits = `0${digits}`;
  return digits;
}

export function formatE164Phone(rawPhone: unknown): string {
  if (!rawPhone) return '';
  const digits = String(rawPhone).replace(/\D/g, '');
  if (!digits) return '';
  if (digits.startsWith('20') && digits.length >= 12) return `+${digits}`;
  if (digits.startsWith('0') && digits.length >= 11) return `+2${digits}`;
  if (digits.length === 10 && /^(10|11|12|15)/.test(digits)) return `+20${digits}`;
  return `+${digits}`;
}

export function normalizeTarget(value: unknown): string {
  const t = String(value || '').trim();
  if (t.includes('@')) return t.toLowerCase();
  return t.replace(/[\s\-\(\)]/g, '');
}

export function buildCleanUserId({ name = '', email = '', phone = '' }): string {
  const cleanName = String(name || '').trim().toLowerCase();
  const cleanEmail = String(email || '').trim().toLowerCase();
  const cleanPhone = String(phone || '').replace(/\D/g, '');

  let slug = cleanName.replace(/[^a-z0-9]+/g, '_').replace(/^_+|_+$/g, '');
  if (!slug || slug === 'hagzy_member' || slug === 'member' || slug === 'customer') {
    if (cleanEmail.includes('@')) {
      slug = cleanEmail.split('@')[0].replace(/[^a-z0-9]+/g, '_').replace(/^_+|_+$/g, '');
    } else if (cleanPhone) {
      slug = `user_${cleanPhone.slice(-6)}`;
    } else {
      slug = 'member';
    }
  }
  const suffix = crypto.randomUUID().replace(/-/g, '').slice(0, 6);
  return `usr_${slug.slice(0, 24)}_${suffix}`;
}

export function mapUserRowToJson(row: Record<string, any>): Record<string, any> {
  const extra = (row.extra && typeof row.extra === 'object') ? row.extra : {};
  return {
    ...extra,
    id: row.id,
    authUserId: row.auth_user_id ?? undefined,
    googleId: row.google_id ?? undefined,
    appleUserId: row.apple_user_id ?? undefined,
    email: row.email || '',
    phone: row.phone || '',
    name: row.name || '',
    avatar: row.avatar || '',
    role: row.role || 'customer',
    partnerStatus: row.partner_status || 'none',
    authProvider: row.auth_provider || 'otp',
    emailVerified: Boolean(row.email_verified),
    phoneVerified: Boolean(row.phone_verified),
    walletBalance: Number(row.wallet_balance || 0),
    createdAt: row.created_at,
    updatedAt: row.updated_at,
  };
}

export function mapVenueRowToJson(
  row: Record<string, any>,
  unitRows: Record<string, any>[] = [],
  reviewRows: Record<string, any>[] = [],
): Record<string, any> {
  const extra = (row.extra && typeof row.extra === 'object') ? { ...row.extra } : {};
  const rawOwnerId = extra._rawOwnerId;
  delete extra._rawOwnerId;

  const grouped: Record<string, any[]> = {};
  for (const u of unitRows) {
    const uExtra = (u.extra && typeof u.extra === 'object') ? u.extra : {};
    const key = ['units', 'items', 'spaces'].includes(u.source_key) ? u.source_key : 'units';
    if (!grouped[key]) grouped[key] = [];
    grouped[key].push({
      ...uExtra,
      id: u.id,
      name: u.name,
      ...(u.name_en ? { nameEn: u.name_en } : {}),
      type: u.unit_type || 'unit',
      kind: u.unit_type || 'unit',
      ...(u.capacity != null ? { capacity: Number(u.capacity) } : {}),
      pricePerHour: Number(u.price_per_hour || 0),
      hourlyRate: Number(u.price_per_hour || 0),
      price: Number(u.price_per_hour || 0),
      isActive: u.is_active !== false,
    });
  }

  const mappedReviews = reviewRows.map(r => ({
    id: r.id,
    authorName: r.author_name,
    rating: Number(r.rating),
    comment: r.comment || '',
    date: r.review_date || String(r.created_at || '').split('T')[0],
    verifiedBooking: r.verified_booking !== false,
  }));

  const out: Record<string, any> = {
    ...extra,
    id: row.id,
    name: row.name,
    ...(row.name_en ? { nameEn: row.name_en } : {}),
    category: row.category || '',
    type: extra.type || row.category || 'sports',
    city: row.city || '',
    area: row.area || '',
    address: row.address || '',
    description: row.description || '',
    phone: row.phone || '',
    ...(row.owner_id || rawOwnerId ? { ownerId: row.owner_id || rawOwnerId } : {}),
    ...(row.owner_email ? { ownerEmail: row.owner_email } : {}),
    ...(row.owner_phone ? { ownerPhone: row.owner_phone } : {}),
    pricePerHour: Number(row.price_per_hour || 0),
    depositPercent: Number(row.deposit_percent || 0),
    pricingMode: row.pricing_mode || 'per_hour',
    rating: Number(row.rating || 0),
    reviewsCount: Number(row.reviews_count || 0),
    reviews: mappedReviews,
    reviewsList: mappedReviews,
    isActive: row.is_active !== false,
    isDeleted: Boolean(row.is_deleted),
    images: Array.isArray(row.images) ? row.images : [],
    amenities: Array.isArray(row.amenities) ? row.amenities : [],
    rules: Array.isArray(row.rules) ? row.rules : [],
    services: Array.isArray(row.services) ? row.services : [],
    ...grouped,
    ...(mappedReviews.length > 0 ? { reviewsList: mappedReviews } : {}),
    createdAt: row.created_at,
    updatedAt: row.updated_at,
  };
  return out;
}

export function mapBookingRowToJson(row: Record<string, any>): Record<string, any> {
  const extra = (row.extra && typeof row.extra === 'object') ? { ...row.extra } : {};
  const rawCustomerId = extra._rawCustomerId;
  const ownerId = extra._ownerId;
  const rawUnitId = extra._rawUnitId;
  delete extra._rawCustomerId;
  delete extra._ownerId;
  delete extra._rawUnitId;
  delete extra._hasItemId;
  delete extra._hasPhone;
  delete extra._hasEmail;
  delete extra._hasPrice;
  delete extra._hasHoldExpiresAt;

  const resolvedCustomer = row.customer_id || rawCustomerId;
  const resolvedUnit = row.unit_id || rawUnitId;

  return {
    ...extra,
    id: row.id,
    ...(resolvedCustomer ? { customerId: resolvedCustomer, ownerId: ownerId || resolvedCustomer, userId: resolvedCustomer } : {}),
    venueId: row.venue_id,
    ...(resolvedUnit ? { unitId: resolvedUnit, itemId: resolvedUnit } : {}),
    ...(row.unit_name ? { unitName: row.unit_name } : {}),
    venueName: row.venue_name || '',
    customer: row.customer_name || extra.customer || '',
    customerName: row.customer_name || '',
    customerPhone: row.customer_phone || '',
    phone: row.customer_phone || '',
    customerEmail: row.customer_email || '',
    email: row.customer_email || '',
    ...(row.booking_date ? { date: row.booking_date } : {}),
    startsAt: row.starts_at,
    ...(row.ends_at ? { endsAt: row.ends_at } : {}),
    durationMinutes: Number(row.duration_minutes || 60),
    status: row.status,
    totalPrice: Number(row.total_price || 0),
    price: Number(row.total_price || 0),
    depositAmount: Number(row.deposit_amount || 0),
    dueNow: Number(row.due_now || 0),
    actualPaidAmount: Number(row.actual_paid_amount || 0),
    excessAmount: Number(row.excess_amount || 0),
    paymentMethod: row.payment_method || '',
    ...(row.payment_reference ? { paymentReference: row.payment_reference } : {}),
    confirmed: Boolean(row.confirmed),
    cancelled: Boolean(row.cancelled),
    checkedIn: Boolean(row.checked_in),
    ...(row.checked_in_at ? { checkedInAt: row.checked_in_at } : {}),
    ...(row.confirmed_at ? { confirmedAt: row.confirmed_at } : {}),
    ...(row.cancelled_at ? { cancelledAt: row.cancelled_at } : {}),
    ...(row.expires_at ? { expiresAt: row.expires_at, holdExpiresAt: row.expires_at } : {}),
    reminderOffsetMinutes:
      row.reminder_offset_minutes !== undefined && row.reminder_offset_minutes !== null
        ? Number(row.reminder_offset_minutes)
        : 120,
    ...(row.reminder_sent_at ? { reminderSentAt: row.reminder_sent_at } : {}),
    createdAt: row.created_at,
    updatedAt: row.updated_at,
  };
}

export async function loadFullVenueWithUnits(
  supabase: SupabaseClient,
  venueId: string,
): Promise<Record<string, any> | null> {
  const [{ data: vRow, error: vErr }, { data: units }, { data: reviews }] = await Promise.all([
    supabase.from('venues').select('*').eq('id', venueId).maybeSingle(),
    supabase.from('bookable_units').select('*').eq('venue_id', venueId).order('sort_order', { ascending: true }),
    supabase.from('venue_reviews').select('*').eq('venue_id', venueId).order('created_at', { ascending: false }).limit(50),
  ]);
  if (vErr || !vRow) return null;
  return mapVenueRowToJson(vRow, units || [], reviews || []);
}

export async function loadAllVenuesWithUnits(
  supabase: SupabaseClient,
  { includeDeleted = false } = {},
): Promise<Record<string, any>[]> {
  let vQuery = supabase.from('venues').select('*').order('created_at', { ascending: true });
  if (!includeDeleted) vQuery = vQuery.eq('is_deleted', false);

  const [{ data: venues }, { data: units }, { data: reviews }] = await Promise.all([
    vQuery,
    supabase.from('bookable_units').select('*').order('sort_order', { ascending: true }),
    supabase.from('venue_reviews').select('*').order('created_at', { ascending: false }),
  ]);

  const unitsByVenue = new Map<string, any[]>();
  for (const u of units || []) {
    const arr = unitsByVenue.get(u.venue_id) || [];
    arr.push(u);
    unitsByVenue.set(u.venue_id, arr);
  }

  const reviewsByVenue = new Map<string, any[]>();
  for (const r of reviews || []) {
    const arr = reviewsByVenue.get(r.venue_id) || [];
    arr.push(r);
    reviewsByVenue.set(r.venue_id, arr);
  }

  return (venues || []).map(v => mapVenueRowToJson(v, unitsByVenue.get(v.id) || [], reviewsByVenue.get(v.id) || []));
}
