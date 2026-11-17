import { Hono } from '@hono/hono';
import {
  doesPartnerOwnVenue,
  isUserAdmin,
  resolveUserFromToken,
} from './_shared/auth.ts';
import {
  getSupabaseAdmin,
  loadAllVenuesWithUnits,
  loadFullVenueWithUnits,
  mapBookingRowToJson,
  normalizeLocalPhone,
} from './_shared/db.ts';
import { sendSmsOrWhatsApp } from './_shared/notifications.ts';
import { BOOKING_STATUS, canTransition } from './_shared/state_machine.ts';

async function requireAdmin(c: any) {
  const authHeader = c.req.header('authorization') || '';
  if (!authHeader.startsWith('Bearer ')) return { error: c.json({ error: 'Missing admin token' }, 401) };
  const resolved = await resolveUserFromToken(getSupabaseAdmin(), authHeader.slice(7));
  if (!resolved) return { error: c.json({ error: 'Invalid admin token' }, 401) };
  const { claims } = resolved;
  const isOwner = (claims.role === 'owner' || claims.isAdmin) && isUserAdmin(claims);
  const isPartner = claims.role === 'partner' || claims.role === 'merchant';
  if (!isOwner && !isPartner) {
    return { error: c.json({ error: 'Forbidden: Admin access restricted to authorized owner' }, 403) };
  }
  return { claims, isOwner, userRow: resolved.userRow };
}

function mapPartnerRequestRow(r: Record<string, any>) {
  return {
    id: r.id,
    userId: r.user_id || '',
    venueId: r.approved_venue_id || undefined,
    venueName: r.venue_name || '',
    venueType: r.category || 'padel',
    city: r.city || 'Cairo',
    area: r.area || '',
    address: r.address || '',
    ownerName: r.owner_name || '',
    email: r.owner_email || '',
    phone: r.owner_phone || '',
    notes: r.extra?.notes || '',
    status: r.status || 'pending',
    reviewedBy: r.reviewed_by || undefined,
    reviewedAt: r.reviewed_at || undefined,
    rejectionReason: r.rejection_reason || undefined,
    createdAt: r.created_at,
    updatedAt: r.updated_at,
  };
}

export function registerAdminAndPartnerRoutes(app: Hono) {
  const supabase = getSupabaseAdmin();

  // Admin Users CRM (backed by v_user_overview + linked bookings)
  app.get('/api/admin/users', async c => {
    const auth = await requireAdmin(c);
    if ('error' in auth) return auth.error;

    if (auth.isOwner) {
      const [{ data: users }, { data: bookings }] = await Promise.all([
        supabase.from('v_user_overview').select('*').order('created_at', { ascending: false }),
        supabase.from('bookings').select('*').order('starts_at', { ascending: false }),
      ]);
      const bookingsByUser = new Map<string, any[]>();
      for (const b of bookings || []) {
        if (!b.customer_id) continue;
        const arr = bookingsByUser.get(b.customer_id) || [];
        arr.push(mapBookingRowToJson(b));
        bookingsByUser.set(b.customer_id, arr);
      }
      const list = (users || []).map(u => {
        const userBookings = bookingsByUser.get(u.user_id) || [];
        return {
          id: u.user_id,
          authUserId: u.auth_user_id,
          name: u.name || 'Hagzy Member',
          phone: u.phone || '',
          email: u.email || '',
          role: u.role,
          partnerStatus: u.partner_status,
          walletBalance: Number(u.wallet_balance || 0),
          bookingsCount: Number(u.total_bookings || userBookings.length),
          confirmedBookingsCount: Number(u.confirmed_bookings || 0),
          pendingBookingsCount: userBookings.filter(b => b.status === 'pending_payment').length,
          bookings: userBookings,
          createdAt: u.created_at,
        };
      });
      return c.json({ success: true, users: list });
    }

    // Partners see only customers who booked at their owned venues
    const allVenues = await loadAllVenuesWithUnits(supabase);
    const ownedIds = allVenues.filter(v => doesPartnerOwnVenue(auth.claims, v)).map(v => v.id);
    if (ownedIds.length === 0) return c.json({ success: true, users: [] });

    const { data: bookings } = await supabase
      .from('bookings')
      .select('*')
      .in('venue_id', ownedIds)
      .order('starts_at', { ascending: false });

    const customerIds = Array.from(new Set((bookings || []).map(b => b.customer_id).filter(Boolean)));
    const { data: users } = customerIds.length > 0
      ? await supabase.from('users').select('id, name, phone, email, wallet_balance, created_at').in('id', customerIds)
      : { data: [] };

    const userMap = new Map((users || []).map(u => [u.id, u]));
    const grouped = new Map<string, any>();
    for (const b of bookings || []) {
      const uid = b.customer_id || `guest_${b.customer_phone || b.customer_email || b.id}`;
      const u = b.customer_id ? userMap.get(b.customer_id) : null;
      if (!grouped.has(uid)) {
        grouped.set(uid, {
          id: uid,
          name: u?.name || b.customer_name || 'Hagzy Member',
          phone: u?.phone || b.customer_phone || '',
          email: u?.email || b.customer_email || '',
          walletBalance: 0,
          bookings: [],
        });
      }
      grouped.get(uid).bookings.push(mapBookingRowToJson(b));
    }
    const list = Array.from(grouped.values()).map(entry => ({
      ...entry,
      bookingsCount: entry.bookings.length,
      confirmedBookingsCount: entry.bookings.filter((b: any) => b.confirmed || b.status === 'confirmed').length,
      pendingBookingsCount: entry.bookings.filter((b: any) => b.status === 'pending_payment').length,
    }));
    return c.json({ success: true, users: list });
  });

  // Partner onboarding moderation
  app.get('/api/admin/partner-requests', async c => {
    const auth = await requireAdmin(c);
    if ('error' in auth) return auth.error;
    if (!auth.isOwner) return c.json({ error: 'Forbidden: Only platform owner can review partner requests' }, 403);
    const { data } = await supabase.from('partner_requests').select('*').order('created_at', { ascending: false });
    return c.json({ success: true, requests: (data || []).map(mapPartnerRequestRow) });
  });

  app.post('/api/admin/partner-requests/:id/approve', async c => {
    const auth = await requireAdmin(c);
    if ('error' in auth) return auth.error;
    if (!auth.isOwner) return c.json({ error: 'Forbidden: Only platform owner can approve partner requests' }, 403);

    const { data: reqRow } = await supabase.from('partner_requests').select('*').eq('id', c.req.param('id')).maybeSingle();
    if (!reqRow) return c.json({ error: 'Partner request not found' }, 404);

    const { data: users } = await supabase.from('users').select('*');
    let userRow = (users || []).find(u =>
      (reqRow.user_id && u.id === reqRow.user_id) ||
      (reqRow.owner_email && (u.email || '').toLowerCase() === reqRow.owner_email.toLowerCase()) ||
      (reqRow.owner_phone && normalizeLocalPhone(u.phone) === normalizeLocalPhone(reqRow.owner_phone)),
    );

    if (!userRow) {
      const uid = reqRow.user_id || `usr_${crypto.randomUUID().slice(0, 8)}`;
      const { data: created } = await supabase
        .from('users')
        .insert({
          id: uid,
          name: reqRow.owner_name || 'Venue Owner',
          email: reqRow.owner_email || '',
          phone: reqRow.owner_phone || '',
          role: 'partner',
          partner_status: 'approved',
        })
        .select('*')
        .single();
      userRow = created;
    } else {
      const nextRole = userRow.role === 'owner' ? 'owner' : 'partner';
      await supabase.from('users').update({ role: nextRole, partner_status: 'approved' }).eq('id', userRow.id);
    }

    const allVenues = await loadAllVenuesWithUnits(supabase);
    let venue = allVenues.find(v => doesPartnerOwnVenue(userRow!, v));
    let venueId = venue?.id;
    if (!venue) {
      venueId = `ven_${crypto.randomUUID().slice(0, 8)}`;
      await supabase.from('venues').insert({
        id: venueId,
        name: reqRow.venue_name || 'My Venue',
        category: reqRow.category || 'padel',
        city: reqRow.city || 'Cairo',
        address: reqRow.address || '',
        owner_id: userRow!.id,
        owner_email: userRow!.email || reqRow.owner_email || '',
        owner_phone: userRow!.phone || reqRow.owner_phone || '',
        phone: userRow!.phone || reqRow.owner_phone || '',
        deposit_percent: 30,
        is_active: true,
        extra: { type: reqRow.category || 'padel' },
      });
      venue = await loadFullVenueWithUnits(supabase, venueId) || undefined;
    } else {
      await supabase.from('venues').update({
        owner_id: venue.ownerId || userRow!.id,
        owner_email: venue.ownerEmail || userRow!.email || reqRow.owner_email || '',
        owner_phone: venue.ownerPhone || userRow!.phone || reqRow.owner_phone || '',
      }).eq('id', venueId!);
    }

    const { data: updatedReq } = await supabase
      .from('partner_requests')
      .update({
        status: 'approved',
        approved_venue_id: venueId,
        reviewed_at: new Date().toISOString(),
        reviewed_by: String(auth.claims.email || auth.claims.id || 'owner'),
      })
      .eq('id', reqRow.id)
      .select('*')
      .single();

    return c.json({ success: true, request: mapPartnerRequestRow(updatedReq!), venue });
  });

  app.post('/api/admin/partner-requests/:id/reject', async c => {
    const auth = await requireAdmin(c);
    if ('error' in auth) return auth.error;
    if (!auth.isOwner) return c.json({ error: 'Forbidden: Only platform owner can reject partner requests' }, 403);

    const { data: reqRow } = await supabase.from('partner_requests').select('*').eq('id', c.req.param('id')).maybeSingle();
    if (!reqRow) return c.json({ error: 'Partner request not found' }, 404);
    const { reason } = await c.req.json().catch(() => ({}));

    const { data: updatedReq } = await supabase
      .from('partner_requests')
      .update({
        status: 'rejected',
        rejection_reason: String(reason || '').trim(),
        reviewed_at: new Date().toISOString(),
        reviewed_by: String(auth.claims.email || auth.claims.id || 'owner'),
      })
      .eq('id', reqRow.id)
      .select('*')
      .single();

    if (reqRow.user_id) {
      await supabase
        .from('users')
        .update({ partner_status: 'rejected' })
        .eq('id', reqRow.user_id)
        .neq('partner_status', 'approved');
    }

    return c.json({ success: true, request: mapPartnerRequestRow(updatedReq!) });
  });

  // Venues CRUD (multi-tenant)
  app.get('/api/admin/venues', async c => {
    const auth = await requireAdmin(c);
    if ('error' in auth) return auth.error;
    const all = await loadAllVenuesWithUnits(supabase, { includeDeleted: false });
    if (auth.isOwner) return c.json({ success: true, venues: all });
    return c.json({ success: true, venues: all.filter(v => doesPartnerOwnVenue(auth.claims, v)) });
  });

  app.put('/api/admin/venues/:id', async c => {
    const auth = await requireAdmin(c);
    if ('error' in auth) return auth.error;

    const venueId = c.req.param('id');
    const body = await c.req.json().catch(() => ({}));
    const existing = await loadFullVenueWithUnits(supabase, venueId);

    const name = typeof body.name === 'string' ? body.name.trim() : '';
    if (!name && !existing) return c.json({ error: 'Venue name is required' }, 400);
    if (name.length > 100) return c.json({ error: 'Venue name cannot exceed 100 characters' }, 400);

    if (body.depositPercent !== undefined) {
      const dp = Number(body.depositPercent);
      if (!Number.isFinite(dp) || dp < 0 || dp > 100) {
        return c.json({ error: 'depositPercent must be between 0 and 100' }, 400);
      }
    }

    if (existing) {
      if (!auth.isOwner && !doesPartnerOwnVenue(auth.claims, existing)) {
        return c.json({ error: 'Forbidden: You do not own this venue' }, 403);
      }
    } else if (!auth.isOwner) {
      const all = await loadAllVenuesWithUnits(supabase);
      if (all.some(v => doesPartnerOwnVenue(auth.claims, v))) {
        return c.json({ error: 'Forbidden: Partners are limited to one active venue' }, 403);
      }
    }

    const merged: Record<string, any> = {
      ...(existing || {}),
      ...body,
      id: venueId,
    };

    if (!auth.isOwner && existing) {
      merged.ownerEmail = existing.ownerEmail;
      merged.ownerPhone = existing.ownerPhone;
      merged.ownerId = existing.ownerId;
    } else if (!existing) {
      const hasAssigned = Boolean(body.ownerEmail || body.ownerPhone);
      if (!hasAssigned) {
        merged.ownerId = auth.claims.id || null;
        merged.ownerEmail = auth.claims.email || '';
        merged.ownerPhone = auth.claims.phone || '';
      }
    }

    let resolvedOwnerId: string | null = null;
    if (merged.ownerEmail || merged.ownerPhone || merged.ownerId) {
      const { data: users } = await supabase.from('users').select('*');
      const targetEmail = String(merged.ownerEmail || '').trim().toLowerCase();
      const targetPhone = normalizeLocalPhone(merged.ownerPhone || '');
      const found = (users || []).find(u =>
        (merged.ownerId && u.id === merged.ownerId) ||
        (targetEmail && (u.email || '').toLowerCase() === targetEmail) ||
        (targetPhone && normalizeLocalPhone(u.phone) === targetPhone),
      );
      if (found) {
        resolvedOwnerId = found.id;
        if (found.role !== 'owner' && auth.isOwner) {
          await supabase.from('users').update({ role: 'partner', partner_status: 'approved' }).eq('id', found.id);
        }
      }
    }

    const extra: Record<string, unknown> = { ...(existing?.extra || {}) };
    for (const k of ['nameAr', 'type', 'categories', 'addressAr', 'instapayHandle', 'vodafoneCashNumber', 'latitude', 'longitude', 'lat', 'lng', 'image', 'openingTime', 'closingTime', 'currency']) {
      if (merged[k] !== undefined) extra[k] = merged[k];
    }

    await supabase.from('venues').upsert({
      id: venueId,
      name: merged.name || 'Venue',
      name_en: merged.nameEn || '',
      category: merged.category || merged.type || '',
      city: merged.city || '',
      area: merged.area || '',
      address: merged.address || '',
      description: merged.description || '',
      phone: merged.phone || '',
      owner_id: resolvedOwnerId,
      owner_email: String(merged.ownerEmail || '').trim().toLowerCase(),
      owner_phone: String(merged.ownerPhone || '').trim(),
      price_per_hour: Math.max(0, Number(merged.pricePerHour || 0)),
      deposit_percent: Math.min(100, Math.max(0, Math.round(Number(merged.depositPercent ?? 30)))),
      pricing_mode: merged.pricingMode || 'per_hour',
      is_active: merged.isActive !== false,
      is_deleted: false,
      images: Array.isArray(merged.images) ? merged.images : [],
      amenities: Array.isArray(merged.amenities) ? merged.amenities : [],
      rules: Array.isArray(merged.rules) ? merged.rules : [],
      services: Array.isArray(merged.services) ? merged.services : [],
      extra,
    });

    // Sync bookable_units for this venue
    const unitRows: any[] = [];
    const seenIds = new Set<string>();
    for (const sourceKey of ['units', 'items', 'spaces'] as const) {
      const arr = merged[sourceKey];
      if (!Array.isArray(arr)) continue;
      arr.forEach((u: any, idx: number) => {
        if (!u || typeof u !== 'object') return;
        const unitId = String(u.id || `${venueId}_${sourceKey}_${idx + 1}`).trim();
        if (seenIds.has(unitId)) return;
        seenIds.add(unitId);
        const priceVal = u.pricePerHour ?? u.hourlyRate ?? u.price;
        unitRows.push({
          id: unitId,
          venue_id: venueId,
          name: String(u.name || unitId),
          name_en: String(u.nameEn || ''),
          unit_type: String(u.unitType || u.type || 'unit'),
          capacity: u.capacity != null && Number.isFinite(Number(u.capacity)) ? Math.round(Number(u.capacity)) : null,
          price_per_hour: priceVal != null && Number.isFinite(Number(priceVal)) ? Number(priceVal) : null,
          is_active: u.isActive !== false,
          source_key: sourceKey,
          sort_order: idx,
        });
      });
    }

    const keepUnitIds = unitRows.map(u => u.id);
    if (keepUnitIds.length === 0) {
      await supabase.from('bookable_units').delete().eq('venue_id', venueId);
    } else {
      const { data: existingUnits } = await supabase.from('bookable_units').select('id').eq('venue_id', venueId);
      const toRemove = (existingUnits || []).map(u => u.id).filter(id => !seenIds.has(id));
      if (toRemove.length > 0) {
        await supabase.from('bookable_units').delete().eq('venue_id', venueId).in('id', toRemove);
      }
      await supabase.from('bookable_units').upsert(unitRows);
    }

    await supabase.from('audit_log').insert({
      id: `aud_${crypto.randomUUID().slice(0, 8)}`,
      venue_id: venueId,
      action: existing ? 'VENUE_UPDATE' : 'VENUE_CREATE',
      actor: String(auth.claims.email || auth.claims.id || 'admin'),
      details: { name: merged.name },
    });

    const saved = await loadFullVenueWithUnits(supabase, venueId);
    return c.json({ success: true, venue: saved });
  });

  app.delete('/api/admin/venues/:id', async c => {
    const auth = await requireAdmin(c);
    if ('error' in auth) return auth.error;
    const venueId = c.req.param('id');
    const existing = await loadFullVenueWithUnits(supabase, venueId);
    if (!existing) return c.json({ error: 'Venue not found' }, 404);
    if (!auth.isOwner && !doesPartnerOwnVenue(auth.claims, existing)) {
      return c.json({ error: 'Forbidden: You do not own this venue' }, 403);
    }

    await supabase.from('venues').update({ is_deleted: true, is_active: false }).eq('id', venueId);
    await supabase.from('audit_log').insert({
      id: `aud_${crypto.randomUUID().slice(0, 8)}`,
      venue_id: venueId,
      action: 'VENUE_SOFT_DELETE',
      actor: String(auth.claims.email || auth.claims.id || 'admin'),
    });
    return c.json({ success: true, message: 'Venue deleted' });
  });

  // Compatibility refresh endpoint replacing old sync-firebase call
  app.post('/api/admin/venues/sync-firebase', async c => {
    const auth = await requireAdmin(c);
    if ('error' in auth) return auth.error;
    const venues = await loadAllVenuesWithUnits(supabase, { includeDeleted: false });
    const count = auth.isOwner ? venues.length : venues.filter(v => doesPartnerOwnVenue(auth.claims, v)).length;
    return c.json({ success: true, syncedCount: count, totalVenues: count, firebaseReady: false, supabaseReady: true });
  });

  // Admin Bookings & Analytics
  app.get('/api/admin/bookings', async c => {
    const auth = await requireAdmin(c);
    if ('error' in auth) return auth.error;
    const { data: rows } = await supabase.from('bookings').select('*').order('created_at', { ascending: false });
    if (auth.isOwner) return c.json({ success: true, bookings: (rows || []).map(mapBookingRowToJson) });

    const venues = await loadAllVenuesWithUnits(supabase);
    const ownedIds = new Set(venues.filter(v => doesPartnerOwnVenue(auth.claims, v)).map(v => v.id));
    const scoped = (rows || []).filter(b => ownedIds.has(b.venue_id)).map(mapBookingRowToJson);
    return c.json({ success: true, bookings: scoped });
  });

  app.get('/api/admin/analytics', async c => {
    const auth = await requireAdmin(c);
    if ('error' in auth) return auth.error;
    const startDate = c.req.query('startDate');
    const endDate = c.req.query('endDate');
    const venueId = c.req.query('venueId');

    let query = supabase.from('bookings').select('*');
    if (venueId) query = query.eq('venue_id', venueId);
    if (startDate) query = query.gte('starts_at', new Date(startDate).toISOString());
    if (endDate) query = query.lte('starts_at', new Date(endDate).toISOString());

    const { data: rows } = await query;
    let bookings = rows || [];
    if (!auth.isOwner) {
      const venues = await loadAllVenuesWithUnits(supabase);
      const ownedIds = new Set(venues.filter(v => doesPartnerOwnVenue(auth.claims, v)).map(v => v.id));
      bookings = bookings.filter(b => ownedIds.has(b.venue_id));
    }

    let totalRevenueEgp = 0, totalDepositsEgp = 0, totalBalanceDueEgp = 0, lostRevenueEgp = 0;
    let confirmedCount = 0, cancelledCount = 0, expiredCount = 0, noShowCount = 0, completedCount = 0;
    for (const b of bookings) {
      const p = Number(b.total_price || 0);
      const dep = Number(b.deposit_amount || b.due_now || 0);
      if (b.status === 'confirmed' || b.status === 'completed') {
        totalRevenueEgp += p;
        totalDepositsEgp += dep;
        totalBalanceDueEgp += Math.max(0, p - dep);
        if (b.status === 'confirmed') confirmedCount++;
        if (b.status === 'completed') completedCount++;
      } else if (b.status === 'cancelled') {
        cancelledCount++; lostRevenueEgp += p;
      } else if (b.status === 'expired') {
        expiredCount++; lostRevenueEgp += p;
      } else if (b.status === 'no_show') {
        noShowCount++; lostRevenueEgp += p;
      }
    }

    return c.json({
      success: true,
      analytics: {
        totalBookings: bookings.length,
        confirmedCount, completedCount, cancelledCount, expiredCount, noShowCount,
        totalRevenueEgp, totalDepositsEgp, totalBalanceDueEgp, lostRevenueEgp,
      },
    });
  });

  app.post('/api/admin/bookings/:id/confirm', async c => {
    const auth = await requireAdmin(c);
    if ('error' in auth) return auth.error;
    const { data: bRow } = await supabase.from('bookings').select('*').eq('id', c.req.param('id')).maybeSingle();
    if (!bRow) return c.json({ error: 'Booking not found' }, 404);

    if (!auth.isOwner) {
      const venue = await loadFullVenueWithUnits(supabase, bRow.venue_id);
      if (!venue || !doesPartnerOwnVenue(auth.claims, venue)) {
        return c.json({ error: 'Forbidden: You do not have permission to manage bookings for this venue' }, 403);
      }
    }
    if (!canTransition(bRow.status, BOOKING_STATUS.CONFIRMED)) {
      return c.json({ error: `Cannot confirm booking from status '${bRow.status}'` }, 409);
    }

    const bEnds = new Date(new Date(bRow.starts_at).getTime() + Number(bRow.duration_minutes || 60) * 60000).toISOString();
    const { data: conflicts } = await supabase
      .from('bookings')
      .select('id, status, confirmed, expires_at')
      .eq('venue_id', bRow.venue_id)
      .eq('cancelled', false)
      .neq('id', bRow.id)
      .not('status', 'in', '("cancelled","expired","no_show")')
      .lt('starts_at', bEnds)
      .gt('ends_at', bRow.starts_at);

    const hasConflict = (conflicts || []).some(other =>
      other.status === 'confirmed' || other.confirmed || !other.expires_at || new Date(other.expires_at).getTime() > Date.now(),
    );
    if (hasConflict) {
      return c.json({ error: 'Cannot confirm: this slot is already booked by another confirmed booking.' }, 409);
    }

    await supabase.from('bookings').update({
      status: BOOKING_STATUS.CONFIRMED,
      confirmed: true,
      due_now: 0,
      confirmed_at: new Date().toISOString(),
      expires_at: null,
    }).eq('id', bRow.id);

    await supabase.from('audit_log').insert({
      id: `aud_${Date.now()}_${crypto.randomUUID().slice(0, 5)}`,
      booking_id: bRow.id,
      venue_id: bRow.venue_id,
      user_id: bRow.customer_id,
      action: 'booking_transition',
      from_status: bRow.status,
      to_status: BOOKING_STATUS.CONFIRMED,
      actor: String(auth.claims.email || 'admin'),
      reason: 'Admin verified deposit',
    });

    if (bRow.customer_phone) {
      await sendSmsOrWhatsApp({
        phone: bRow.customer_phone,
        message: `✅ تم تأكيد حجزك رسمياً في حجزي! رقم الحجز: ${bRow.id}. نتمنى لك وقتاً ممتعاً.`,
      });
    }

    const { data: updated } = await supabase.from('bookings').select('*').eq('id', bRow.id).single();
    return c.json({ success: true, booking: mapBookingRowToJson(updated!) });
  });

  app.delete('/api/admin/bookings/:id', async c => {
    const auth = await requireAdmin(c);
    if ('error' in auth) return auth.error;
    const { data: bRow } = await supabase.from('bookings').select('*').eq('id', c.req.param('id')).maybeSingle();
    if (!bRow) return c.json({ error: 'Booking not found' }, 404);

    if (!auth.isOwner) {
      const venue = await loadFullVenueWithUnits(supabase, bRow.venue_id);
      if (!venue || !doesPartnerOwnVenue(auth.claims, venue)) {
        return c.json({ error: 'Forbidden: You do not have permission to manage bookings for this venue' }, 403);
      }
    }
    if (!canTransition(bRow.status, BOOKING_STATUS.CANCELLED)) {
      return c.json({ error: `Cannot cancel booking from status '${bRow.status}'` }, 409);
    }

    await supabase.from('bookings').update({
      status: BOOKING_STATUS.CANCELLED,
      cancelled: true,
      cancelled_at: new Date().toISOString(),
      expires_at: null,
    }).eq('id', bRow.id);

    await supabase.from('audit_log').insert({
      id: `aud_${Date.now()}_${crypto.randomUUID().slice(0, 5)}`,
      booking_id: bRow.id,
      venue_id: bRow.venue_id,
      user_id: bRow.customer_id,
      action: 'booking_transition',
      from_status: bRow.status,
      to_status: BOOKING_STATUS.CANCELLED,
      actor: String(auth.claims.email || 'admin'),
      reason: 'Admin cancelled booking',
    });

    if (bRow.payment_method === 'wallet' && bRow.customer_id) {
      const refundAmt = Number(bRow.actual_paid_amount || bRow.due_now || bRow.deposit_amount || bRow.total_price || 0);
      if (refundAmt > 0) {
        await supabase.rpc('rpc_apply_wallet_entry_atomic', {
          p_entry_id: `led_${Date.now()}_${crypto.randomUUID().slice(0, 6)}`,
          p_user_id: bRow.customer_id,
          p_booking_id: bRow.id,
          p_amount: refundAmt,
          p_entry_type: 'REFUND',
          p_reference_id: bRow.id,
          p_description: `Admin cancellation refund for booking ${bRow.id}`,
          p_actor: String(auth.claims.email || 'admin'),
        });
      }
    }

    if (bRow.customer_phone) {
      await sendSmsOrWhatsApp({
        phone: bRow.customer_phone,
        message: `⚠️ تم إلغاء حجزك في حجزي (رقم الحجز: ${bRow.id}).`,
      });
    }
    return c.json({ success: true, message: 'Booking cancelled' });
  });

  // Review queue moderation
  app.get('/api/admin/payments/review-queue', async c => {
    const auth = await requireAdmin(c);
    if ('error' in auth) return auth.error;
    const { data: items } = await supabase
      .from('payment_review_queue')
      .select('*')
      .order('received_at', { ascending: false });
    return c.json({ success: true, count: (items || []).length, items: items || [] });
  });

  app.post('/api/admin/payments/review-queue/:id/attach', async c => {
    const auth = await requireAdmin(c);
    if ('error' in auth) return auth.error;
    const { data: item } = await supabase.from('payment_review_queue').select('*').eq('id', c.req.param('id')).maybeSingle();
    if (!item) return c.json({ error: 'Review queue item not found' }, 404);
    if (item.status === 'RESOLVED') return c.json({ error: 'Item already resolved' }, 409);

    const { bookingId, userId } = await c.req.json().catch(() => ({}));
    if (!bookingId && !userId) return c.json({ error: 'bookingId or userId is required to attach payment' }, 400);

    if (bookingId) {
      const { data: bRow } = await supabase.from('bookings').select('*').eq('id', bookingId).maybeSingle();
      if (!bRow) return c.json({ error: 'Booking not found' }, 404);
      await supabase.from('bookings').update({
        status: 'confirmed',
        confirmed: true,
        due_now: 0,
        actual_paid_amount: Number(item.amount || 0),
        payment_method: item.payment_method,
        payment_reference: item.provider_ref || '',
        confirmed_at: new Date().toISOString(),
      }).eq('id', bRow.id);
    }

    if (userId) {
      await supabase.rpc('rpc_apply_wallet_entry_atomic', {
        p_entry_id: `led_${Date.now()}_${crypto.randomUUID().slice(0, 6)}`,
        p_user_id: userId,
        p_booking_id: bookingId || null,
        p_amount: Number(item.amount || 0),
        p_entry_type: 'ADMIN_ADJUSTMENT',
        p_reference_id: item.id,
        p_description: `Manual credit from review queue (${item.payment_method})`,
        p_actor: String(auth.claims.email || 'admin'),
      });
    }

    const { data: resolvedItem } = await supabase
      .from('payment_review_queue')
      .update({
        status: 'RESOLVED',
        resolved_by: String(auth.claims.email || 'admin'),
        resolved_at: new Date().toISOString(),
        attached_to: { bookingId, userId },
      })
      .eq('id', item.id)
      .select('*')
      .single();

    return c.json({ success: true, item: resolvedItem });
  });
}
