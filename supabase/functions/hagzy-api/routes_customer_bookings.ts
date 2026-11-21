import { Hono } from '@hono/hono';
import {
  attachBookingQrMeta,
  claimCustomerBookings,
  doesPartnerOwnVenue,
  isUserAdmin,
  resolveUserFromToken,
  revokeToken,
  sanitizeUserResponse,
} from './_shared/auth.ts';
import {
  getSupabaseAdmin,
  loadAllVenuesWithUnits,
  loadFullVenueWithUnits,
  mapBookingRowToJson,
  normalizeLocalPhone,
} from './_shared/db.ts';
import { notifyVenueOwner } from './_shared/notifications.ts';
import { normalizeSenderId } from './_shared/payments.ts';
import { calculateServerPricing, PricingError } from './_shared/pricing.ts';
import { BOOKING_STATUS, canTransition } from './_shared/state_machine.ts';

async function requireCustomer(c: any) {
  const authHeader = c.req.header('authorization') || '';
  if (!authHeader.startsWith('Bearer ')) return { error: c.json({ error: 'Missing customer token' }, 401) };
  const resolved = await resolveUserFromToken(getSupabaseAdmin(), authHeader.slice(7));
  if (!resolved?.userRow) {
    return { error: c.json({ error: 'Account not found or session expired. Please sign in again.' }, 401) };
  }
  return { userRow: resolved.userRow, claims: resolved.claims, token: authHeader.slice(7) };
}

async function requireAdminOrOwner(c: any) {
  const authHeader = c.req.header('authorization') || '';
  if (!authHeader.startsWith('Bearer ')) return { error: c.json({ error: 'Missing admin token' }, 401) };
  const resolved = await resolveUserFromToken(getSupabaseAdmin(), authHeader.slice(7));
  if (!resolved) return { error: c.json({ error: 'Invalid admin token' }, 401) };
  const { claims } = resolved;
  const isOwner = (claims.role === 'owner' || claims.isAdmin) && isUserAdmin(claims);
  const isPartner = claims.role === 'partner' || claims.role === 'merchant';
  if (!isOwner && !isPartner) return { error: c.json({ error: 'Forbidden' }, 403) };
  return { claims, isOwner, userRow: resolved.userRow };
}

export function registerCustomerAndBookingRoutes(app: Hono) {
  const supabase = getSupabaseAdmin();

  // Profile GET/PUT/DELETE
  app.get('/api/customer/profile', async c => {
    const auth = await requireCustomer(c);
    if ('error' in auth) return auth.error;
    return c.json({ success: true, customer: await sanitizeUserResponse(supabase, auth.userRow) });
  });

  app.put('/api/customer/profile', async c => {
    const auth = await requireCustomer(c);
    if ('error' in auth) return auth.error;
    const { name, phone, email } = await c.req.json().catch(() => ({}));
    const updates: Record<string, unknown> = {};

    if (email) {
      const cleanEmail = String(email).trim().toLowerCase();
      const { data: dup } = await supabase.from('users').select('id').neq('id', auth.userRow.id).ilike('email', cleanEmail).maybeSingle();
      if (dup) return c.json({ error: 'This email is already in use by another account.' }, 409);
      updates.email = cleanEmail;
    }
    if (phone) {
      const cleanPhone = String(phone).replace(/\D/g, '');
      const { data: allUsers } = await supabase.from('users').select('id, phone').neq('id', auth.userRow.id);
      if ((allUsers || []).some(u => normalizeLocalPhone(u.phone) === normalizeLocalPhone(cleanPhone))) {
        return c.json({ error: 'This phone number is already in use by another account.' }, 409);
      }
      updates.phone = normalizeLocalPhone(cleanPhone) || cleanPhone;
    }
    if (name && typeof name === 'string') updates.name = name.trim();

    const { data: updated } = await supabase.from('users').update(updates).eq('id', auth.userRow.id).select('*').single();
    if (updated) await claimCustomerBookings(supabase, updated);
    return c.json({ success: true, customer: await sanitizeUserResponse(supabase, updated || auth.userRow) });
  });

  app.delete('/api/customer/account', async c => {
    const auth = await requireCustomer(c);
    if ('error' in auth) return auth.error;
    const authUserId = auth.userRow.auth_user_id;
    await supabase.from('users').delete().eq('id', auth.userRow.id);
    if (authUserId) {
      try { await supabase.auth.admin.deleteUser(authUserId); } catch (_) {}
    }
    await revokeToken(supabase, auth.token);
    return c.json({ success: true, message: 'Account deleted permanently.' });
  });

  // Wallet
  app.post('/api/customer/wallet/deduct', async c => {
    const auth = await requireCustomer(c);
    if ('error' in auth) return auth.error;
    const body = await c.req.json().catch(() => ({}));
    const numAmount = Number(body.amount);
    if (!Number.isFinite(numAmount) || numAmount <= 0) return c.json({ error: 'Invalid amount' }, 400);

    const { data, error } = await supabase.rpc('rpc_apply_wallet_entry_atomic', {
      p_entry_id: `led_${Date.now()}_${crypto.randomUUID().slice(0, 6)}`,
      p_user_id: auth.userRow.id,
      p_booking_id: null,
      p_amount: -numAmount,
      p_entry_type: 'BOOKING_DEPOSIT',
      p_reference_id: null,
      p_description: String(body.description || 'Wallet payment deduction'),
      p_actor: 'customer',
    });
    if (error || !data?.ok) {
      return c.json({ error: data?.error || error?.message || 'Wallet deduction failed' }, data?.status || 400);
    }
    return c.json({ success: true, walletBalance: Number(data.walletBalance) });
  });

  app.post('/api/customer/wallet/add', async c => {
    const auth = await requireAdminOrOwner(c);
    if ('error' in auth) return auth.error;
    if (!auth.isOwner) return c.json({ error: 'Forbidden: Only platform owner can adjust customer wallets' }, 403);
    const { amount, userId, email, phone, description } = await c.req.json().catch(() => ({}));

    const { data: users } = await supabase.from('users').select('id, email, phone');
    const target = (users || []).find(u =>
      (userId && u.id === userId) ||
      (email && (u.email || '').toLowerCase() === String(email).trim().toLowerCase()) ||
      (phone && normalizeLocalPhone(u.phone) === normalizeLocalPhone(phone)),
    );
    if (!target) return c.json({ error: 'User not found' }, 404);
    const numAmount = Number(amount);
    if (!Number.isFinite(numAmount) || numAmount <= 0 || numAmount > 100000) {
      return c.json({ error: 'Invalid amount' }, 400);
    }

    const { data, error } = await supabase.rpc('rpc_apply_wallet_entry_atomic', {
      p_entry_id: `led_${Date.now()}_${crypto.randomUUID().slice(0, 6)}`,
      p_user_id: target.id,
      p_booking_id: null,
      p_amount: numAmount,
      p_entry_type: 'ADMIN_ADJUSTMENT',
      p_reference_id: null,
      p_description: String(description || 'Admin adjustment'),
      p_actor: String(auth.claims.email || 'admin'),
    });
    if (error || !data?.ok) {
      return c.json({ error: data?.error || error?.message || 'Wallet adjustment failed' }, data?.status || 400);
    }
    return c.json({ success: true, walletBalance: Number(data.walletBalance) });
  });

  app.get('/api/customer/wallet/transactions', async c => {
    const auth = await requireCustomer(c);
    if ('error' in auth) return auth.error;
    const { data: rows } = await supabase
      .from('wallet_ledger')
      .select('*')
      .eq('user_id', auth.userRow.id)
      .order('created_at', { ascending: false });

    const transactions = (rows || []).map(r => ({
      id: r.id,
      userId: r.user_id,
      bookingId: r.booking_id || undefined,
      amount: Number(r.amount),
      type: r.entry_type,
      referenceId: r.reference_id || undefined,
      description: r.description || '',
      actor: r.actor || 'system',
      createdAt: r.created_at,
    }));
    return c.json({
      success: true,
      walletBalance: Number(auth.userRow.wallet_balance || 0),
      transactions,
    });
  });

  // Partner onboarding requests
  app.post('/api/partner/requests', async c => {
    const auth = await requireCustomer(c);
    if ('error' in auth) return auth.error;
    const body = await c.req.json().catch(() => ({}));
    const cleanVenueName = String(body.venueName || '').trim().slice(0, 120);
    if (cleanVenueName.length < 2) {
      return c.json({ error: 'Venue name is required (at least 2 characters).' }, 400);
    }

    const { data: existing } = await supabase
      .from('partner_requests')
      .select('*')
      .eq('user_id', auth.userRow.id)
      .order('created_at', { ascending: false })
      .limit(1)
      .maybeSingle();

    const payload = {
      id: existing?.id || `preq_${Date.now()}_${crypto.randomUUID().slice(0, 5)}`,
      user_id: auth.userRow.id,
      owner_name: String(body.ownerName || auth.userRow.name || '').trim().slice(0, 80),
      owner_email: auth.userRow.email || '',
      owner_phone: auth.userRow.phone || '',
      venue_name: cleanVenueName,
      category: String(body.venueType || 'padel').trim().slice(0, 40),
      city: String(body.city || 'Cairo').trim().slice(0, 60),
      address: String(body.address || '').trim().slice(0, 200),
      status: 'pending',
      extra: { notes: String(body.notes || '').trim().slice(0, 400) },
    };

    const { data: saved, error } = await supabase
      .from('partner_requests')
      .upsert(payload)
      .select('*')
      .single();
    if (error) return c.json({ error: error.message }, 500);

    await supabase
      .from('users')
      .update({ partner_status: auth.userRow.partner_status === 'approved' ? 'approved' : 'pending' })
      .eq('id', auth.userRow.id);

    return c.json({ success: true, request: saved });
  });

  app.get('/api/partner/requests/me', async c => {
    const auth = await requireCustomer(c);
    if ('error' in auth) return auth.error;
    const { data: myReq } = await supabase
      .from('partner_requests')
      .select('*')
      .eq('user_id', auth.userRow.id)
      .order('created_at', { ascending: false })
      .limit(1)
      .maybeSingle();

    const sanitized = await sanitizeUserResponse(supabase, auth.userRow);
    return c.json({
      success: true,
      request: myReq || null,
      partnerStatus: sanitized.partnerStatus,
      isPartner: sanitized.isPartner,
      venueIds: sanitized.venueIds,
    });
  });

  // Public Venues & Reviews
  app.get('/api/venues', async c => {
    const all = await loadAllVenuesWithUnits(supabase, { includeDeleted: false });
    const publicVenues = all
      .filter(v => v.isActive !== false)
      .map(v => {
        const copy = { ...v };
        delete copy.ownerEmail;
        delete copy.ownerPhone;
        delete copy.ownerId;
        return copy;
      });
    return c.json({ success: true, venues: publicVenues });
  });

  app.post('/api/venues/:id/reviews', async c => {
    const venueId = c.req.param('id');
    const venue = await loadFullVenueWithUnits(supabase, venueId);
    if (!venue) return c.json({ error: 'Venue not found' }, 404);

    const authHeader = c.req.header('authorization') || '';
    const resolved = authHeader.startsWith('Bearer ')
      ? await resolveUserFromToken(supabase, authHeader.slice(7))
      : null;

    const { authorName, author, rating, comment, bookingId } = await c.req.json().catch(() => ({}));
    const numRating = Number(rating);
    if (!Number.isFinite(numRating) || numRating < 1 || numRating > 5) {
      return c.json({ error: 'Rating must be between 1 and 5' }, 400);
    }

    const revId = `rev_${crypto.randomUUID().slice(0, 8)}`;
    const reviewDate = new Date().toISOString().split('T')[0];
    const cleanAuthor = String(authorName || author || resolved?.userRow?.name || 'Member').slice(0, 60);
    await supabase.from('venue_reviews').insert({
      id: revId,
      venue_id: venueId,
      user_id: resolved?.userRow?.id || null,
      booking_id: bookingId || null,
      author_name: cleanAuthor,
      rating: numRating,
      comment: String(comment || '').slice(0, 500),
      review_date: reviewDate,
      verified_booking: true,
    });

    const { data: allReviews } = await supabase.from('venue_reviews').select('rating').eq('venue_id', venueId);
    const count = (allReviews || []).length;
    const avg = count > 0
      ? Math.round(((allReviews || []).reduce((acc, r) => acc + Number(r.rating), 0) / count) * 10) / 10
      : numRating;
    await supabase.from('venues').update({ reviews_count: count, rating: avg }).eq('id', venueId);

    const updatedVenue = await loadFullVenueWithUnits(supabase, venueId);
    return c.json({
      success: true,
      review: { id: revId, authorName: cleanAuthor, rating: numRating, comment: String(comment || ''), date: reviewDate },
      venue: updatedVenue,
    });
  });

  // Create Booking (Atomic Postgres RPC with Advisory Lock)
  app.post('/api/bookings', async c => {
    const authHeader = c.req.header('authorization') || '';
    const resolved = authHeader.startsWith('Bearer ')
      ? await resolveUserFromToken(supabase, authHeader.slice(7))
      : null;
    const body = await c.req.json().catch(() => ({}));

    const claims = resolved?.claims;
    let isAdmin = Boolean(
      claims &&
      ((claims.role === 'owner' || claims.isAdmin) && isUserAdmin(claims) || claims.role === 'partner' || claims.role === 'merchant'),
    );
    const isPlatformOwner = Boolean(claims && (claims.role === 'owner' || claims.isAdmin) && isUserAdmin(claims));

    const venue = await loadFullVenueWithUnits(supabase, String(body.venueId || ''));
    if (!venue) return c.json({ error: 'Venue not found' }, 404);

    if (isAdmin && !isPlatformOwner && !doesPartnerOwnVenue(claims!, venue)) {
      if (body.walkIn || body.blockReason) {
        return c.json({ error: 'Forbidden: You can only create walk-in bookings for your own venue' }, 403);
      }
      isAdmin = false;
    }

    const start = new Date(body.startsAt);
    const duration = Number(body.durationMinutes);
    if (Number.isNaN(start.getTime())) return c.json({ error: 'Invalid start time' }, 400);
    if (!Number.isInteger(duration) || duration < 15 || duration > 720) {
      return c.json({ error: 'Invalid duration' }, 400);
    }
    if (!isAdmin && start.getTime() < Date.now() - 5 * 60 * 1000) {
      return c.json({ error: 'Cannot book a time in the past' }, 400);
    }
    if (typeof body.itemId !== 'string' || !body.itemId) {
      return c.json({ error: 'itemId is required' }, 400);
    }

    let pricing: any;
    try {
      pricing = calculateServerPricing({
        venue,
        itemId: body.itemId,
        durationMinutes: duration,
        serviceIds: body.services || body.serviceIds || [],
        splitCount: body.splitCount,
        promoCode: body.promoCode,
      });
    } catch (err) {
      if (err instanceof PricingError && !(isAdmin && Number.isFinite(Number(body.price)))) {
        return c.json({ error: err.message }, err.statusCode as any);
      }
      const fallbackPrice = Number(body.price || 0);
      pricing = {
        unitId: body.itemId,
        unitName: body.unitName || body.itemId,
        finalPrice: fallbackPrice,
        subtotal: fallbackPrice,
        discountAmount: 0,
        appliedPromo: null,
        depositAmount: Math.round((fallbackPrice * Number(venue.depositPercent || 30)) / 100),
        dueNow: Number(body.dueNow ?? fallbackPrice),
        services: [],
      };
    }

    let finalPrice = pricing.finalPrice;
    if (Number.isFinite(Number(body.price)) && Number(body.price) > finalPrice) {
      finalPrice = Number(body.price);
    }

    let ownerRow = resolved?.userRow || null;
    if (!ownerRow && !isAdmin) {
      const cleanEmail = String(body.email || '').trim().toLowerCase();
      const normPhone = normalizeLocalPhone(body.phone || body.customerPhone);
      if (cleanEmail || normPhone) {
        const { data: users } = await supabase.from('users').select('*');
        ownerRow = (users || []).find(u =>
          (cleanEmail && (u.email || '').toLowerCase() === cleanEmail) ||
          (normPhone && normalizeLocalPhone(u.phone) === normPhone),
        ) || null;
      }
    }

    const chargeWallet = !isAdmin && body.paymentMethod === 'wallet';
    if (chargeWallet && !resolved?.userRow) {
      return c.json({ error: 'Sign in to pay with your wallet' }, 401);
    }

    const bookingId =
      typeof body.id === 'string' && /^[\w-]{1,64}$/.test(body.id)
        ? body.id
        : `bk_${crypto.randomUUID()}`;
    const status = isAdmin
      ? (body.walkIn ? 'confirmed' : String(body.status || 'confirmed'))
      : (chargeWallet ? 'confirmed' : 'pending_payment');
    const confirmed = isAdmin ? status === 'confirmed' : chargeWallet;
    const dueNow = chargeWallet ? 0 : Number(pricing.dueNow ?? body.dueNow ?? finalPrice);
    const holdExpiresAt = isAdmin
      ? (body.holdExpiresAt || null)
      : (chargeWallet ? null : new Date(Date.now() + 15 * 60 * 1000).toISOString());

    const unitMatches = (venue.units || venue.items || venue.spaces || []).some(
      (u: any) => String(u.id) === String(body.itemId),
    );
    const rawReminderOffset = Number(body.reminderOffsetMinutes);
    const reminderOffsetMinutes =
      body.reminderOffsetMinutes !== undefined &&
      body.reminderOffsetMinutes !== null &&
      body.reminderOffsetMinutes !== '' &&
      Number.isFinite(rawReminderOffset)
        ? Math.max(0, Math.min(10080, Math.round(rawReminderOffset)))
        : 120;

    const { data: rpcRes, error: rpcErr } = await supabase.rpc('rpc_book_slot_atomic', {
      p_payload: {
        id: bookingId,
        customerId: ownerRow?.id || '',
        venueId: venue.id,
        unitId: unitMatches ? body.itemId : '',
        unitName: pricing.unitName || '',
        venueName: venue.name || '',
        customerName: String(body.customer || '').slice(0, 80),
        customerPhone: String(body.phone || body.customerPhone || '').slice(0, 30),
        customerEmail: String(body.email || '').trim().toLowerCase(),
        startsAt: start.toISOString(),
        durationMinutes: duration,
        status,
        totalPrice: finalPrice,
        depositAmount: pricing.depositAmount,
        dueNow: chargeWallet ? pricing.dueNow : dueNow,
        actualPaidAmount: chargeWallet ? pricing.dueNow : 0,
        paymentMethod: String(body.paymentMethod || ''),
        confirmed,
        expiresAt: holdExpiresAt || '',
        reminderOffsetMinutes,
        chargeWallet,
        actor: claims?.email || ownerRow?.email || 'customer',
        extra: {
          subtotal: pricing.subtotal,
          discountAmount: pricing.discountAmount,
          promoCode: pricing.appliedPromo,
          services: pricing.services,
          ...(body.serviceNames ? { serviceNames: body.serviceNames } : {}),
          ...(body.splitCount ? { splitCount: body.splitCount } : {}),
          ...(body.multiController ? { multiController: body.multiController } : {}),
          ...(body.staffMember ? { staffMember: body.staffMember } : {}),
          ...(body.blockReason ? { blockReason: String(body.blockReason).slice(0, 200), isBlocked: true } : {}),
          ...(!unitMatches ? { _rawUnitId: body.itemId } : {}),
        },
      },
    });

    if (rpcErr || !rpcRes?.ok) {
      return c.json(
        { error: rpcRes?.error || rpcErr?.message || 'Booking failed' },
        (rpcRes?.status || 500) as any,
      );
    }

    if (chargeWallet) {
      await supabase.from('bookings').update({ due_now: 0 }).eq('id', bookingId);
    }

    const { data: bRow } = await supabase.from('bookings').select('*').eq('id', bookingId).single();
    if (bRow && !body.blockReason) {
      await notifyVenueOwner(supabase, {
        venue,
        booking: bRow,
        eventType: bRow.confirmed ? 'booking_confirmed' : 'booking_created',
      });
    }

    return c.json({
      success: true,
      booking: await attachBookingQrMeta(mapBookingRowToJson(bRow!)),
      ...(rpcRes.walletBalance != null ? { walletBalance: Number(rpcRes.walletBalance) } : {}),
    });
  });

  // Customer own bookings
  app.get('/api/bookings', async c => {
    const auth = await requireCustomer(c);
    if ('error' in auth) return auth.error;
    await claimCustomerBookings(supabase, auth.userRow);

    const userPhone = auth.userRow.phone_verified ? normalizeLocalPhone(auth.userRow.phone) : '';
    const userEmail = auth.userRow.email_verified ? String(auth.userRow.email || '').trim().toLowerCase() : '';
    const { data: rows } = await supabase.from('bookings').select('*').order('created_at', { ascending: false });

    const matched = (rows || []).filter(b => {
      if (b.customer_id === auth.userRow.id) return true;
      if (userPhone && normalizeLocalPhone(b.customer_phone) === userPhone) return true;
      if (userEmail && String(b.customer_email || '').trim().toLowerCase() === userEmail) return true;
      return false;
    });
    const mine = await Promise.all(matched.map(b => attachBookingQrMeta(mapBookingRowToJson(b))));

    return c.json({ success: true, bookings: mine });
  });

  // Update per-booking WhatsApp reminder timing
  app.put('/api/bookings/:id/reminder', async c => {
    const auth = await requireCustomer(c);
    if ('error' in auth) return auth.error;
    const { data: bRow } = await supabase.from('bookings').select('*').eq('id', c.req.param('id')).maybeSingle();
    if (!bRow) return c.json({ error: 'Booking not found' }, 404);

    const isOwner =
      bRow.customer_id === auth.userRow.id ||
      (auth.userRow.phone_verified && normalizeLocalPhone(auth.userRow.phone) === normalizeLocalPhone(bRow.customer_phone)) ||
      (auth.userRow.email_verified && String(auth.userRow.email || '').toLowerCase() === String(bRow.customer_email || '').toLowerCase());
    if (!isOwner) return c.json({ error: 'Forbidden' }, 403);

    const body = await c.req.json().catch(() => ({}));
    const rawOffset = Number(body.reminderOffsetMinutes);
    if (!Number.isFinite(rawOffset) || rawOffset < 0 || rawOffset > 10080) {
      return c.json({ error: 'reminderOffsetMinutes must be between 0 and 10080' }, 400);
    }
    const clamped = Math.round(rawOffset);
    const { data: updated } = await supabase
      .from('bookings')
      .update({ reminder_offset_minutes: clamped, reminder_sent_at: null })
      .eq('id', bRow.id)
      .select('*')
      .single();

    return c.json({
      success: true,
      reminderOffsetMinutes: clamped,
      booking: await attachBookingQrMeta(mapBookingRowToJson(updated!)),
    });
  });

  // Customer booking cancel + >= 6h wallet refund
  app.post('/api/bookings/:id/cancel', async c => {
    const auth = await requireCustomer(c);
    if ('error' in auth) return auth.error;
    const { data: bRow } = await supabase.from('bookings').select('*').eq('id', c.req.param('id')).maybeSingle();
    if (!bRow) return c.json({ error: 'Booking not found' }, 404);

    const isOwner =
      bRow.customer_id === auth.userRow.id ||
      (auth.userRow.phone_verified && normalizeLocalPhone(auth.userRow.phone) === normalizeLocalPhone(bRow.customer_phone)) ||
      (auth.userRow.email_verified && String(auth.userRow.email || '').toLowerCase() === String(bRow.customer_email || '').toLowerCase());

    if (!isOwner) return c.json({ error: 'You are not authorized to cancel this booking.' }, 403);
    if (bRow.cancelled || bRow.status === 'cancelled') return c.json({ error: 'This booking has already been cancelled.' }, 400);
    if (bRow.status === 'expired') return c.json({ error: 'This reservation hold has already expired.' }, 400);
    if (new Date(bRow.starts_at).getTime() <= Date.now()) {
      return c.json({ error: 'Cannot cancel a booking that has already started or elapsed.' }, 400);
    }
    if (!canTransition(bRow.status, BOOKING_STATUS.CANCELLED)) {
      return c.json({ error: 'Cannot cancel booking in current status.' }, 409);
    }

    await supabase
      .from('bookings')
      .update({
        status: BOOKING_STATUS.CANCELLED,
        cancelled: true,
        cancelled_at: new Date().toISOString(),
        expires_at: null,
      })
      .eq('id', bRow.id);

    await supabase.from('audit_log').insert({
      id: `aud_${Date.now()}_${crypto.randomUUID().slice(0, 5)}`,
      booking_id: bRow.id,
      venue_id: bRow.venue_id,
      user_id: auth.userRow.id,
      action: 'booking_transition',
      from_status: bRow.status,
      to_status: BOOKING_STATUS.CANCELLED,
      actor: auth.userRow.email || auth.userRow.phone || 'customer',
      reason: 'Customer cancelled booking',
    });

    const hoursUntil = (new Date(bRow.starts_at).getTime() - Date.now()) / (3600 * 1000);
    if (bRow.payment_method === 'wallet' && hoursUntil >= 6) {
      const refundAmt = Number(bRow.deposit_amount || bRow.due_now || bRow.actual_paid_amount || bRow.total_price || 0);
      if (refundAmt > 0) {
        await supabase.rpc('rpc_apply_wallet_entry_atomic', {
          p_entry_id: `led_${Date.now()}_${crypto.randomUUID().slice(0, 6)}`,
          p_user_id: auth.userRow.id,
          p_booking_id: bRow.id,
          p_amount: refundAmt,
          p_entry_type: 'REFUND',
          p_reference_id: bRow.id,
          p_description: `Full refund for cancellation >=6h before start (${bRow.id})`,
          p_actor: 'system',
        });
      }
    }

    const { data: updated } = await supabase.from('bookings').select('*').eq('id', bRow.id).single();
    if (updated) {
      const venueObj = await loadFullVenueWithUnits(supabase, updated.venue_id);
      await notifyVenueOwner(supabase, { venue: venueObj, booking: updated, eventType: 'booking_cancelled' });
    }
    return c.json({
      success: true,
      message: 'Booking cancelled successfully.',
      booking: await attachBookingQrMeta(mapBookingRowToJson(updated!)),
    });
  });

  // Public booking status poll
  app.get('/api/bookings/:id', async c => {
    const { data: bRow } = await supabase.from('bookings').select('*').eq('id', c.req.param('id')).maybeSingle();
    if (!bRow) return c.json({ error: 'Booking not found' }, 404);
    const full = mapBookingRowToJson(bRow);
    const { phone: _p, email: _e, customerPhone: _cp, customerEmail: _ce, ownerId: _o, paymentReference: _pr, ...safe } = full;
    return c.json({ success: true, booking: safe });
  });

  // Payment proof submission
  app.post('/api/bookings/:id/payment-proof', async c => {
    const { data: bRow } = await supabase.from('bookings').select('*').eq('id', c.req.param('id')).maybeSingle();
    if (!bRow) return c.json({ error: 'Booking not found' }, 404);
    if (bRow.status !== 'pending_payment') return c.json({ error: 'This booking is not awaiting payment' }, 409);

    const body = await c.req.json().catch(() => ({}));
    const method = String(body.method || '');
    const reference = String(body.reference || '').trim();
    if (!['instapay', 'vodafone_cash', 'vodafoneCash', 'fawry', 'card'].includes(method) && !/^[\w \-]{2,32}$/.test(method)) {
      return c.json({ error: 'Invalid payment method' }, 400);
    }
    if (reference.length < 4 || reference.length > 64) {
      return c.json({ error: 'Invalid payment reference' }, 400);
    }

    const holdExpiresAt = new Date(Date.now() + 60 * 60 * 1000).toISOString();
    const extra = { ...(bRow.extra || {}), proofSubmitted: true, paymentProof: { method, reference, submittedAt: new Date().toISOString() } };
    const lowerM = method.toLowerCase();
    if (lowerM.includes('insta') || lowerM.includes('vodafone') || lowerM.includes('wallet')) {
      const intentMethod = (lowerM.includes('vodafone') || lowerM.includes('wallet')) ? 'MOBILE_WALLET' : 'INSTAPAY';
      const normalizedSender = normalizeSenderId(intentMethod, reference);
      if (normalizedSender) {
        extra.expectedSenderIdentifier = normalizedSender;
        const intentId = `intent_${bRow.id}_${intentMethod.toLowerCase()}`;
        const expectedAmt = Math.max(5, Number(bRow.due_now ?? bRow.deposit_amount ?? bRow.total_price ?? 5));
        await supabase.from('payment_intents').upsert({
          id: intentId,
          booking_id: bRow.id,
          raw_booking_id: bRow.id,
          user_id: bRow.customer_id || null,
          payment_method: intentMethod,
          expected_sender_identifier: normalizedSender,
          expected_amount: expectedAmt,
          status: 'AWAITING_TRANSFER',
          expires_at: holdExpiresAt,
        });
      }
    }

    const { data: updated } = await supabase
      .from('bookings')
      .update({
        payment_method: method,
        payment_reference: reference,
        expires_at: holdExpiresAt,
        extra,
      })
      .eq('id', bRow.id)
      .select('*')
      .single();

    return c.json({ success: true, booking: mapBookingRowToJson(updated!) });
  });

  // Fawry reference generation
  app.post('/api/bookings/:id/fawry-reference', async c => {
    const { data: bRow } = await supabase.from('bookings').select('*').eq('id', c.req.param('id')).maybeSingle();
    if (!bRow) return c.json({ error: 'Booking not found' }, 404);
    if (bRow.cancelled || bRow.status === 'cancelled') {
      return c.json({ error: 'Cannot issue reference for a cancelled booking' }, 409);
    }

    const { customerName, phone } = await c.req.json().catch(() => ({}));
    let hash = 918273645;
    for (const ch of String(bRow.id)) hash = ((hash * 31) + ch.charCodeAt(0)) & 0x7fffffff;
    const digits = String(9000000000 + (hash % 999999999));
    const referenceNumber = `${digits.slice(0, 3)} ${digits.slice(3, 6)} ${digits.slice(6)}`;
    const expiresAt = new Date(Date.now() + 60 * 60 * 1000).toISOString();

    await supabase.from('bookings').update({
      ...(customerName ? { customer_name: String(customerName).slice(0, 80) } : {}),
      ...(phone ? { customer_phone: String(phone).slice(0, 30) } : {}),
      payment_method: 'fawry',
      expires_at: expiresAt,
      extra: { ...(bRow.extra || {}), fawryReference: referenceNumber },
    }).eq('id', bRow.id);

    return c.json({
      success: true,
      referenceNumber,
      expiresAt,
      amount: Number(bRow.due_now || bRow.deposit_amount || bRow.total_price || 0),
    });
  });

  app.post('/api/bookings/:id/paymob-intention', async c => {
    return c.json({ error: 'Paymob live integration requires PAYMOB_API_KEY configuration.' }, 503);
  });
}
