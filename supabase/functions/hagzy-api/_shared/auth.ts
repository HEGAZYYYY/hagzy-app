import { SupabaseClient } from '@supabase/supabase-js';
import {
  buildCleanUserId,
  formatE164Phone,
  getEnv,
  getSupabaseAdmin,
  mapUserRowToJson,
  normalizeLocalPhone,
} from './db.ts';

const encoder = new TextEncoder();
const decoder = new TextDecoder();

function toBase64Url(bytes: Uint8Array): string {
  let bin = '';
  for (const b of bytes) bin += String.fromCharCode(b);
  return btoa(bin).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/g, '');
}

function fromBase64Url(str: string): Uint8Array {
  const padded = str.replace(/-/g, '+').replace(/_/g, '/') + '='.repeat((4 - (str.length % 4)) % 4);
  const bin = atob(padded);
  const out = new Uint8Array(bin.length);
  for (let i = 0; i < bin.length; i++) out[i] = bin.charCodeAt(i);
  return out;
}

export async function sha256Hex(input: string): Promise<string> {
  const digest = await crypto.subtle.digest('SHA-256', encoder.encode(input));
  return Array.from(new Uint8Array(digest)).map(b => b.toString(16).padStart(2, '0')).join('');
}

export async function hmacSha256Hex(secret: string, payload: string): Promise<string> {
  const key = await crypto.subtle.importKey(
    'raw',
    encoder.encode(secret),
    { name: 'HMAC', hash: 'SHA-256' },
    false,
    ['sign'],
  );
  const sig = await crypto.subtle.sign('HMAC', key, encoder.encode(payload));
  return Array.from(new Uint8Array(sig)).map(b => b.toString(16).padStart(2, '0')).join('');
}

export function safeEqual(a: unknown, b: unknown): boolean {
  if (typeof a !== 'string' || typeof b !== 'string') return false;
  const maxLen = Math.max(a.length, b.length, 1);
  let diff = a.length === b.length ? 0 : 1;
  for (let i = 0; i < maxLen; i++) {
    const ca = i < a.length ? a.charCodeAt(i) : 0;
    const cb = i < b.length ? b.charCodeAt(i) : 0;
    diff |= ca ^ cb;
  }
  return diff === 0;
}

export function getJwtSecret(): string {
  const explicit = getEnv('JWT_SECRET');
  if (explicit) return explicit;
  const serviceKey = getEnv('SUPABASE_SERVICE_ROLE_KEY');
  if (!serviceKey) throw new Error('JWT_SECRET is not configured');
  return `hagzy_derived_${serviceKey}`;
}

export async function computeBookingQrSig(bookingId: string, venueId: string): Promise<string> {
  const hex = await hmacSha256Hex(getJwtSecret(), `qr_checkin:${bookingId}:${venueId}`);
  return hex.slice(0, 24);
}

export function buildBookingQrCheckInUrl(bookingId: string, sig: string): string {
  return `https://hagzy.shop/partner?scanBooking=${encodeURIComponent(bookingId)}&sig=${encodeURIComponent(sig)}`;
}

export async function verifyBookingQrSig(
  bookingId: string,
  venueId: string,
  sig: string,
): Promise<boolean> {
  if (!sig || !bookingId || !venueId) return false;
  const expected = await computeBookingQrSig(bookingId, venueId);
  return safeEqual(sig.trim(), expected);
}

export async function attachBookingQrMeta<T extends Record<string, any>>(
  booking: T,
): Promise<T & { qrSignature: string; qrCheckInUrl: string }> {
  const bookingId = String(booking.id || '');
  const venueId = String(booking.venueId || booking.venue_id || '');
  const sig = await computeBookingQrSig(bookingId, venueId);
  return {
    ...booking,
    qrSignature: sig,
    qrCheckInUrl: buildBookingQrCheckInUrl(bookingId, sig),
  };
}

export async function signJwt(
  payload: Record<string, unknown>,
  expiresInSeconds = 30 * 24 * 3600,
): Promise<string> {
  const secret = getJwtSecret();
  const nowSec = Math.floor(Date.now() / 1000);
  const fullPayload = { ...payload, iat: nowSec, exp: nowSec + expiresInSeconds };
  const h = toBase64Url(encoder.encode(JSON.stringify({ alg: 'HS256', typ: 'JWT' })));
  const p = toBase64Url(encoder.encode(JSON.stringify(fullPayload)));
  const key = await crypto.subtle.importKey(
    'raw',
    encoder.encode(secret),
    { name: 'HMAC', hash: 'SHA-256' },
    false,
    ['sign'],
  );
  const sig = new Uint8Array(await crypto.subtle.sign('HMAC', key, encoder.encode(`${h}.${p}`)));
  return `${h}.${p}.${toBase64Url(sig)}`;
}

export async function verifyJwt(token: string): Promise<Record<string, any>> {
  const clean = token.replace(/^Bearer\s+/i, '').trim();
  const parts = clean.split('.');
  if (parts.length !== 3) throw new Error('Invalid token structure');
  const [h, p, s] = parts;
  const key = await crypto.subtle.importKey(
    'raw',
    encoder.encode(getJwtSecret()),
    { name: 'HMAC', hash: 'SHA-256' },
    false,
    ['verify'],
  );
  const ok = await crypto.subtle.verify(
    'HMAC',
    key,
    fromBase64Url(s),
    encoder.encode(`${h}.${p}`),
  );
  if (!ok) throw new Error('Invalid JWT signature');
  const claims = JSON.parse(decoder.decode(fromBase64Url(p)));
  if (claims.exp && claims.exp * 1000 < Date.now()) {
    throw new Error('Token expired');
  }
  return claims;
}

export function getAdminWhitelist() {
  const emails = getEnv('ADMIN_EMAIL')
    .split(',')
    .map(s => s.trim().toLowerCase())
    .filter(Boolean);
  const phones = getEnv('ADMIN_PHONE')
    .split(',')
    .map(normalizeLocalPhone)
    .filter(Boolean);
  return { emails, phones };
}

export function isUserAdmin(identity: Record<string, any> | null | undefined): boolean {
  if (!identity) return false;
  const { emails, phones } = getAdminWhitelist();
  const email = String(identity.email || '').trim().toLowerCase();
  if (email && emails.length > 0 && emails.includes(email)) return true;
  const cleanPhone = normalizeLocalPhone(
    identity.phone || identity.customerPhone || identity.target || identity.phoneNumber || '',
  );
  if (cleanPhone && phones.length > 0 && phones.includes(cleanPhone)) return true;
  if (emails.length === 0 && phones.length === 0) {
    if (identity.role === 'owner' || identity.role === 'super_admin') return true;
  }
  return false;
}

export function doesPartnerOwnVenue(identity: Record<string, any> | null, venue: Record<string, any> | null): boolean {
  if (!identity || !venue || venue.is_deleted || venue.isDeleted) return false;
  if (identity.id && (venue.owner_id === identity.id || venue.ownerId === identity.id)) return true;
  const idEmail = String(identity.email || '').trim().toLowerCase();
  const vEmail = String(venue.owner_email || venue.ownerEmail || '').trim().toLowerCase();
  if (idEmail && vEmail && idEmail === vEmail) return true;
  const idPhone = normalizeLocalPhone(identity.phone || identity.customerPhone || identity.phoneNumber || '');
  const vPhone = normalizeLocalPhone(venue.owner_phone || venue.ownerPhone || venue.phone || '');
  if (idPhone && vPhone && idPhone === vPhone) return true;
  return false;
}

export async function buildPartnerAuthMeta(
  supabase: SupabaseClient,
  user: Record<string, any>,
) {
  const isOwner = isUserAdmin(user);
  const { data: venues } = await supabase
    .from('venues')
    .select('id, owner_id, owner_email, owner_phone, phone, is_deleted')
    .eq('is_deleted', false);

  const ownedVenues = !isOwner
    ? (venues || []).filter(v => doesPartnerOwnVenue(user, v))
    : [];

  const isPartner = !isOwner && Boolean(
    user.partner_status === 'approved' ||
    user.partnerStatus === 'approved' ||
    user.role === 'partner' ||
    ownedVenues.length > 0,
  );

  const role = isOwner ? 'owner' : (isPartner ? 'partner' : 'customer');
  const partnerStatus = isOwner
    ? 'approved'
    : (isPartner ? 'approved' : (user.partner_status || user.partnerStatus || 'none'));

  if (!isOwner && (user.role === 'owner' || (isPartner && user.role !== 'partner'))) {
    await supabase
      .from('users')
      .update({ role, partner_status: partnerStatus })
      .eq('id', user.id);
    user.role = role;
    user.partner_status = partnerStatus;
  }

  return {
    isOwner,
    isAdmin: isOwner,
    isPartner,
    role,
    partnerStatus,
    venueIds: ownedVenues.map(v => v.id),
  };
}

export async function claimPartnerVenues(supabase: SupabaseClient, user: Record<string, any>) {
  if (!user || !user.id) return false;
  const verifiedEmail = (user.email_verified || user.emailVerified) && user.email
    ? String(user.email).trim().toLowerCase()
    : '';
  const verifiedPhone = (user.phone_verified || user.phoneVerified) && user.phone
    ? normalizeLocalPhone(user.phone)
    : '';
  if (!verifiedEmail && !verifiedPhone) return false;

  const { data: venues } = await supabase
    .from('venues')
    .select('id, owner_id, owner_email, owner_phone, is_deleted')
    .eq('is_deleted', false);

  let claimed = false;
  for (const v of venues || []) {
    const byId = v.owner_id === user.id;
    const byEmail = verifiedEmail && String(v.owner_email || '').trim().toLowerCase() === verifiedEmail;
    const byPhone = verifiedPhone && normalizeLocalPhone(v.owner_phone) === verifiedPhone;
    if (byId || byEmail || byPhone) {
      if (v.owner_id !== user.id) {
        await supabase
          .from('venues')
          .update({
            owner_id: user.id,
            ...(verifiedEmail && !v.owner_email ? { owner_email: verifiedEmail } : {}),
            ...(verifiedPhone && !v.owner_phone ? { owner_phone: verifiedPhone } : {}),
          })
          .eq('id', v.id);
        claimed = true;
      }
    }
  }
  return claimed;
}

export async function claimCustomerBookings(supabase: SupabaseClient, user: Record<string, any>) {
  if (!user || !user.id) return;
  const userPhone = (user.phone_verified || user.phoneVerified) ? normalizeLocalPhone(user.phone) : '';
  const userEmail = (user.email_verified || user.emailVerified) && user.email
    ? String(user.email).trim().toLowerCase()
    : '';
  if (!userPhone && !userEmail) return;

  if (userEmail) {
    await supabase
      .from('bookings')
      .update({ customer_id: user.id })
      .is('customer_id', null)
      .ilike('customer_email', userEmail);
  }
  if (userPhone) {
    const { data: candidates } = await supabase
      .from('bookings')
      .select('id, customer_phone')
      .is('customer_id', null)
      .neq('customer_phone', '');
    for (const b of candidates || []) {
      if (normalizeLocalPhone(b.customer_phone) === userPhone) {
        await supabase.from('bookings').update({ customer_id: user.id }).eq('id', b.id);
      }
    }
  }
}

export async function ensureSupabaseAuthUser(
  supabase: SupabaseClient,
  { email = '', phone = '', name = '', existingAuthId = null as string | null },
): Promise<string | null> {
  if (existingAuthId) return existingAuthId;
  const cleanEmail = email.trim().toLowerCase();
  const formattedPhone = phone ? formatE164Phone(phone) : '';
  if (!cleanEmail && !formattedPhone) return null;

  try {
    const { data, error } = await supabase.auth.admin.createUser({
      ...(cleanEmail ? { email: cleanEmail, email_confirm: true } : {}),
      ...(formattedPhone ? { phone: formattedPhone, phone_confirm: true } : {}),
      user_metadata: { name: name || 'Hagzy Member' },
    });
    if (!error && data?.user?.id) {
      return data.user.id;
    }

    // Lookup existing auth user if already registered in auth.users
    const { data: listData } = await supabase.auth.admin.listUsers({ perPage: 1000 });
    const match = (listData?.users || []).find(au =>
      (cleanEmail && (au.email || '').toLowerCase() === cleanEmail) ||
      (formattedPhone && (au.phone || '').replace(/\D/g, '') === formattedPhone.replace(/\D/g, '')),
    );
    return match?.id || null;
  } catch (e) {
    console.warn('Supabase Auth sync notice:', (e as Error).message);
    return null;
  }
}

export async function revokeToken(supabase: SupabaseClient, rawToken: string) {
  const clean = rawToken.replace(/^Bearer\s+/i, '').trim();
  if (!clean) return;
  const hash = await sha256Hex(clean);
  const expiresAt = new Date(Date.now() + 30 * 24 * 3600 * 1000).toISOString();
  await supabase.from('revoked_tokens').upsert({ token_hash: hash, expires_at: expiresAt });
}

export async function isTokenRevoked(supabase: SupabaseClient, rawToken: string): Promise<boolean> {
  const clean = rawToken.replace(/^Bearer\s+/i, '').trim();
  if (!clean) return false;
  const hash = await sha256Hex(clean);
  const { data } = await supabase
    .from('revoked_tokens')
    .select('token_hash')
    .eq('token_hash', hash)
    .maybeSingle();
  return Boolean(data);
}

export async function resolveUserFromToken(
  supabase: SupabaseClient,
  rawToken: string,
): Promise<{ claims: Record<string, any>; userRow: Record<string, any> | null } | null> {
  const clean = rawToken.replace(/^Bearer\s+/i, '').trim();
  if (!clean) return null;
  if (await isTokenRevoked(supabase, clean)) return null;

  // 1. Try Hagzy JWT
  try {
    const claims = await verifyJwt(clean);
    let userRow = null;
    if (claims.id) {
      const { data } = await supabase.from('users').select('*').eq('id', claims.id).maybeSingle();
      userRow = data;
    }
    return { claims, userRow };
  } catch (_) {}

  // 2. Try native Supabase Auth JWT (from supabase_flutter)
  try {
    const { data: authData, error } = await supabase.auth.getUser(clean);
    if (error || !authData?.user) return null;
    const au = authData.user;
    let { data: userRow } = await supabase
      .from('users')
      .select('*')
      .eq('auth_user_id', au.id)
      .maybeSingle();

    if (!userRow && au.email) {
      const { data: byEmail } = await supabase
        .from('users')
        .select('*')
        .ilike('email', au.email)
        .maybeSingle();
      if (byEmail) {
        await supabase.from('users').update({ auth_user_id: au.id }).eq('id', byEmail.id);
        userRow = { ...byEmail, auth_user_id: au.id };
      }
    }

    if (!userRow) {
      const resolvedName = String(au.user_metadata?.full_name || au.user_metadata?.name || au.email?.split('@')[0] || 'Hagzy Member').slice(0, 80);
      const cleanEmail = (au.email || '').toLowerCase();
      const cleanPhone = au.phone ? normalizeLocalPhone(au.phone) : '';
      const newId = buildCleanUserId({ name: resolvedName, email: cleanEmail, phone: cleanPhone });
      const { data: inserted } = await supabase
        .from('users')
        .insert({
          id: newId,
          auth_user_id: au.id,
          email: cleanEmail,
          phone: cleanPhone,
          name: resolvedName,
          avatar: String(au.user_metadata?.avatar_url || ''),
          auth_provider: String(au.app_metadata?.provider || 'supabase'),
          email_verified: Boolean(au.email_confirmed_at),
          phone_verified: Boolean(au.phone_confirmed_at),
          wallet_balance: 0,
        })
        .select('*')
        .single();
      userRow = inserted;
    }

    if (userRow) {
      await claimCustomerBookings(supabase, userRow);
      await claimPartnerVenues(supabase, userRow);
      const meta = await buildPartnerAuthMeta(supabase, userRow);
      return {
        claims: {
          id: userRow.id,
          email: userRow.email,
          phone: userRow.phone,
          name: userRow.name,
          isAdmin: meta.isOwner,
          isPartner: meta.isPartner,
          partnerStatus: meta.partnerStatus,
          role: meta.role,
          venueIds: meta.venueIds,
        },
        userRow,
      };
    }
  } catch (_) {}

  return null;
}

export async function verifyGoogleIdToken(idToken: string) {
  const resp = await fetch(`https://oauth2.googleapis.com/tokeninfo?id_token=${encodeURIComponent(idToken)}`);
  if (!resp.ok) throw new Error('Invalid Google ID token');
  const payload = await resp.json();
  const configuredCid = getEnv('GOOGLE_CLIENT_ID');
  if (configuredCid && payload.aud !== configuredCid && payload.azp !== configuredCid) {
    throw new Error('Google token audience mismatch');
  }
  if (!payload.email) throw new Error('Google account email missing');
  return payload;
}

let appleKeysCache: { keys: any[] | null; fetchedAt: number } = { keys: null, fetchedAt: 0 };
export async function verifyAppleIdentityToken(identityToken: string) {
  const audience = getEnv('APPLE_CLIENT_ID');
  const parts = String(identityToken).split('.');
  if (parts.length !== 3) throw new Error('Malformed Apple identity token');
  const [h, p, s] = parts;
  const header = JSON.parse(decoder.decode(fromBase64Url(h)));
  if (header.alg !== 'RS256') throw new Error('Unexpected Apple JWT algorithm');

  if (!appleKeysCache.keys || Date.now() - appleKeysCache.fetchedAt > 3600_000) {
    const r = await fetch('https://appleid.apple.com/auth/keys');
    if (!r.ok) throw new Error('Could not fetch Apple public keys');
    appleKeysCache = { keys: (await r.json()).keys, fetchedAt: Date.now() };
  }
  const jwk = appleKeysCache.keys!.find((k: any) => k.kid === header.kid);
  if (!jwk) throw new Error('Unknown Apple signing key');

  const pubKey = await crypto.subtle.importKey(
    'jwk',
    jwk,
    { name: 'RSASSA-PKCS1-v1_5', hash: 'SHA-256' },
    false,
    ['verify'],
  );
  const ok = await crypto.subtle.verify(
    'RSASSA-PKCS1-v1_5',
    pubKey,
    fromBase64Url(s),
    encoder.encode(`${h}.${p}`),
  );
  if (!ok) throw new Error('Invalid Apple token signature');

  const claims = JSON.parse(decoder.decode(fromBase64Url(p)));
  if (claims.iss !== 'https://appleid.apple.com') throw new Error('Bad issuer');
  if (audience && claims.aud !== audience) throw new Error('Bad audience');
  if (!claims.exp || claims.exp * 1000 < Date.now()) throw new Error('Token expired');
  return claims;
}

export async function sanitizeUserResponse(supabase: SupabaseClient, userRow: Record<string, any>) {
  const meta = await buildPartnerAuthMeta(supabase, userRow);
  const u = mapUserRowToJson(userRow);
  return {
    id: u.id,
    authUserId: u.authUserId,
    name: u.name,
    phone: u.phone || '',
    email: u.email || '',
    walletBalance: Number(u.walletBalance || 0),
    role: meta.role,
    isAdmin: meta.isOwner,
    isPartner: meta.isPartner,
    partnerStatus: meta.partnerStatus,
    venueIds: meta.venueIds,
  };
}
