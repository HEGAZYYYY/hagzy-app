import { Hono } from '@hono/hono';
import bcrypt from 'bcryptjs';
import {
  buildPartnerAuthMeta,
  claimCustomerBookings,
  claimPartnerVenues,
  ensureSupabaseAuthUser,
  getAdminWhitelist,
  isUserAdmin,
  resolveUserFromToken,
  revokeToken,
  safeEqual,
  sanitizeUserResponse,
  sha256Hex,
  signJwt,
  verifyAppleIdentityToken,
  verifyGoogleIdToken,
} from './_shared/auth.ts';
import {
  buildCleanUserId,
  getEnv,
  getSupabaseAdmin,
  getSupabaseAnon,
  normalizeLocalPhone,
  normalizeTarget,
} from './_shared/db.ts';
import { sendRealEmail, sendSmsOrWhatsApp } from './_shared/notifications.ts';

function generateSixDigitOtp(): string {
  const arr = new Uint32Array(1);
  crypto.getRandomValues(arr);
  return String(100000 + (arr[0] % 900000));
}

export function registerAuthRoutes(app: Hono) {
  // 1. Request OTP (Email or Egyptian Phone)
  app.post('/api/auth/customer-otp/request', async c => {
    const supabase = getSupabaseAdmin();
    const body = await c.req.json().catch(() => ({}));
    const { phone, email, name, isSignUp, isPartner } = body || {};
    const target = normalizeTarget(phone || email);
    if (!target || target.length < 5) {
      return c.json({ error: 'Valid email or phone number is required' }, 400);
    }

    const isEmail = target.includes('@');
    const normPhone = isEmail ? '' : normalizeLocalPhone(target);
    if (!isEmail && !/^01[0125]\d{8}$/.test(normPhone)) {
      return c.json({ error: 'Please enter a valid 11-digit Egyptian mobile number (e.g., 010...)' }, 400);
    }

    const { data: users } = await supabase.from('users').select('id, email, phone');
    const accountExists = (users || []).some(u =>
      isEmail
        ? (u.email || '').toLowerCase() === target
        : normalizeLocalPhone(u.phone) === normPhone,
    );

    if (isPartner !== true && isSignUp === false && !accountExists) {
      return c.json({
        error: 'No account found for this phone/email. Please click "Create Account" below to register.',
        code: 'ACCOUNT_NOT_FOUND',
      }, 404);
    }
    if (isPartner !== true && isSignUp === true && accountExists) {
      return c.json({
        error: 'This phone/email is already registered. Please click "Log In" instead.',
        code: 'ACCOUNT_EXISTS',
      }, 409);
    }

    const revTarget = getEnv('REVIEWER_TARGET');
    const revCode = getEnv('REVIEWER_CODE');
    const isReviewer = Boolean(revTarget && revCode && target === revTarget);
    const otp = isReviewer ? revCode : generateSixDigitOtp();
    const hashedCode = await sha256Hex(otp);

    await supabase.from('otp_challenges').upsert({
      target,
      hashed_code: hashedCode,
      expires_at: new Date(Date.now() + 5 * 60 * 1000).toISOString(),
      attempts: 0,
      name: String(name || '').slice(0, 80),
      is_sign_up: isSignUp === true,
      is_partner: isPartner === true,
    });

    if (!isReviewer) {
      if (isEmail) {
        await sendRealEmail({ email: target, code: otp });
      } else {
        const smsBody = `رمز التحقق الخاص بك في منصة حجزي (Hagzy) هو: ${otp}. لا تشارك هذا الرمز مع أحد.`;
        await sendSmsOrWhatsApp({ phone: target, message: smsBody, otp });
      }
    }

    return c.json({ success: true, message: `Verification code sent to ${target}` });
  });

  // 2. Verify OTP
  app.post('/api/auth/customer-otp/verify', async c => {
    const supabase = getSupabaseAdmin();
    const body = await c.req.json().catch(() => ({}));
    const { phone, email, code, name } = body || {};
    const target = normalizeTarget(phone || email);
    const inputCode = String(code || '').trim();

    const { data: record } = await supabase
      .from('otp_challenges')
      .select('*')
      .eq('target', target)
      .maybeSingle();

    if (!record) {
      return c.json({ error: 'No verification code was requested for this phone/email. Please request a code.' }, 400);
    }
    if (Date.now() > new Date(record.expires_at).getTime()) {
      await supabase.from('otp_challenges').delete().eq('target', target);
      return c.json({ error: 'Verification code has expired. Please request a new one.' }, 400);
    }

    const nextAttempts = Number(record.attempts || 0) + 1;
    if (nextAttempts > 5) {
      await supabase.from('otp_challenges').delete().eq('target', target);
      return c.json({ error: 'Too many attempts. Please request a new code.' }, 429);
    }

    const inputHash = await sha256Hex(inputCode);
    if (!safeEqual(record.hashed_code, inputHash)) {
      await supabase.from('otp_challenges').update({ attempts: nextAttempts }).eq('target', target);
      return c.json({ error: 'Invalid verification code. Please enter the code sent to your email/phone.' }, 400);
    }

    await supabase.from('otp_challenges').delete().eq('target', target);

    const isEmail = target.includes('@');
    const normPhone = isEmail ? '' : normalizeLocalPhone(target);
    const { data: users } = await supabase.from('users').select('*');
    let userRow = (users || []).find(u =>
      isEmail
        ? (u.email || '').toLowerCase() === target
        : (u.phone === target || normalizeLocalPhone(u.phone) === normPhone),
    );

    const resolvedName = String(name || record.name || 'Hagzy Member').slice(0, 80);
    if (!userRow) {
      const userId = buildCleanUserId({
        name: resolvedName,
        email: isEmail ? target : '',
        phone: isEmail ? '' : (normPhone || target),
      });
      const authUserId = await ensureSupabaseAuthUser(supabase, {
        email: isEmail ? target : '',
        phone: isEmail ? '' : (normPhone || target),
        name: resolvedName,
        existingAuthId: null,
      });

      const { data: created, error } = await supabase
        .from('users')
        .insert({
          id: userId,
          auth_user_id: authUserId,
          phone: isEmail ? '' : (normPhone || target),
          email: isEmail ? target : '',
          name: resolvedName,
          auth_provider: 'otp',
          email_verified: isEmail,
          phone_verified: !isEmail,
          wallet_balance: 0,
        })
        .select('*')
        .single();
      if (error || !created) return c.json({ error: error?.message || 'Failed to create user' }, 500);

      userRow = created;
      await supabase.rpc('rpc_apply_wallet_entry_atomic', {
        p_entry_id: `led_welcome_${Date.now()}_${crypto.randomUUID().slice(0, 5)}`,
        p_user_id: userRow.id,
        p_booking_id: null,
        p_amount: 50.0,
        p_entry_type: 'WELCOME_BONUS',
        p_reference_id: null,
        p_description: 'Welcome gift balance',
        p_actor: 'system',
      });
      const { data: refreshed } = await supabase.from('users').select('*').eq('id', userRow.id).single();
      if (refreshed) userRow = refreshed;
    } else {
      const updates: Record<string, unknown> = isEmail ? { email_verified: true } : { phone_verified: true };
      if (name && (!userRow.name || userRow.name === 'Hagzy Member')) {
        updates.name = String(name).slice(0, 80);
      }
      if (!userRow.auth_user_id) {
        const authUserId = await ensureSupabaseAuthUser(supabase, {
          email: userRow.email || (isEmail ? target : ''),
          phone: userRow.phone || (isEmail ? '' : (normPhone || target)),
          name: String(updates.name || userRow.name || resolvedName),
          existingAuthId: null,
        });
        if (authUserId) updates.auth_user_id = authUserId;
      }
      const { data: updated } = await supabase.from('users').update(updates).eq('id', userRow.id).select('*').single();
      if (updated) userRow = updated;
    }

    await claimCustomerBookings(supabase, userRow);
    await claimPartnerVenues(supabase, userRow);

    const partnerMeta = await buildPartnerAuthMeta(supabase, userRow);
    const isAdmin = partnerMeta.isOwner || isUserAdmin({ phone: target, email: target });
    const role = isAdmin ? 'owner' : partnerMeta.role;
    const isPartner = isAdmin || partnerMeta.isPartner;
    const partnerStatus = isAdmin ? 'approved' : partnerMeta.partnerStatus;

    const token = await signJwt({
      id: userRow.id,
      phone: userRow.phone,
      email: userRow.email,
      name: userRow.name,
      isAdmin,
      isPartner,
      role,
    });
    const customer = await sanitizeUserResponse(supabase, userRow);

    return c.json({
      success: true,
      token,
      isAdmin,
      isPartner,
      partnerStatus,
      role,
      venueIds: partnerMeta.venueIds,
      customer: { ...customer, isAdmin, isPartner, partnerStatus, role, venueIds: partnerMeta.venueIds },
    });
  });

  // 3. Google Social Sign-In (Supabase Auth JWT or Google ID Token)
  app.post('/api/auth/social/google', async c => {
    const supabase = getSupabaseAdmin();
    const { idToken } = await c.req.json().catch(() => ({}));
    if (!idToken || typeof idToken !== 'string') {
      return c.json({ error: 'Google idToken or Supabase access token is required' }, 400);
    }

    let verifiedEmail = '';
    let verifiedName = '';
    let verifiedAvatar = '';
    let verifiedId = '';
    let authUserId: string | null = null;

    // Try Supabase Auth session token first
    try {
      const { data } = await supabase.auth.getUser(idToken);
      if (data?.user?.email) {
        authUserId = data.user.id;
        verifiedEmail = data.user.email.toLowerCase();
        verifiedName = String(data.user.user_metadata?.full_name || data.user.user_metadata?.name || '').trim();
        verifiedAvatar = String(data.user.user_metadata?.avatar_url || '').trim();
        verifiedId = String(data.user.user_metadata?.provider_id || data.user.id);
      }
    } catch (_) {}

    if (!verifiedEmail) {
      try {
        const g = await verifyGoogleIdToken(idToken);
        const emailOk = g.email_verified === true || g.email_verified === 'true';
        if (!emailOk) return c.json({ error: 'Google email is not verified' }, 401);
        verifiedEmail = String(g.email).toLowerCase();
        verifiedName = String(g.name || '').trim();
        verifiedAvatar = String(g.picture || '').trim();
        verifiedId = String(g.sub || '');
      } catch (err) {
        return c.json({ error: `Invalid Google token: ${(err as Error).message}` }, 401);
      }
    }

    const { data: users } = await supabase.from('users').select('*');
    let userRow = (users || []).find(u =>
      (authUserId && u.auth_user_id === authUserId) ||
      (verifiedId && u.google_id === verifiedId) ||
      (u.email || '').toLowerCase() === verifiedEmail,
    );

    if (!userRow) {
      const resolvedAuthId = await ensureSupabaseAuthUser(supabase, {
        email: verifiedEmail,
        name: verifiedName || verifiedEmail.split('@')[0],
        existingAuthId: authUserId,
      });
      const { data: created, error } = await supabase
        .from('users')
        .insert({
          id: buildCleanUserId({ name: verifiedName, email: verifiedEmail }),
          auth_user_id: resolvedAuthId,
          google_id: verifiedId || null,
          email: verifiedEmail,
          phone: '',
          name: verifiedName || verifiedEmail.split('@')[0],
          avatar: verifiedAvatar,
          auth_provider: 'google',
          email_verified: true,
          wallet_balance: 0,
        })
        .select('*')
        .single();
      if (error || !created) return c.json({ error: error?.message || 'Failed to save user' }, 500);
      userRow = created;
    } else {
      const updates: Record<string, unknown> = { email_verified: true };
      if (!userRow.google_id && verifiedId) updates.google_id = verifiedId;
      if (verifiedName && (!userRow.name || userRow.name === 'Hagzy Member')) updates.name = verifiedName;
      if (verifiedAvatar && !userRow.avatar) updates.avatar = verifiedAvatar;
      if (!userRow.auth_user_id) {
        updates.auth_user_id = await ensureSupabaseAuthUser(supabase, {
          email: verifiedEmail,
          name: String(updates.name || userRow.name),
          existingAuthId: authUserId,
        });
      }
      const { data: updated } = await supabase.from('users').update(updates).eq('id', userRow.id).select('*').single();
      if (updated) userRow = updated;
    }

    await claimCustomerBookings(supabase, userRow);
    await claimPartnerVenues(supabase, userRow);

    const partnerMeta = await buildPartnerAuthMeta(supabase, userRow);
    const isAdmin = partnerMeta.isOwner || isUserAdmin({ email: verifiedEmail });
    const role = isAdmin ? 'owner' : partnerMeta.role;
    const isPartner = isAdmin || partnerMeta.isPartner;
    const partnerStatus = isAdmin ? 'approved' : partnerMeta.partnerStatus;

    const token = await signJwt({
      id: userRow.id,
      email: userRow.email,
      phone: userRow.phone || '',
      name: userRow.name,
      provider: 'google',
      isAdmin,
      isPartner,
      role,
    }, 90 * 24 * 3600);
    const customer = await sanitizeUserResponse(supabase, userRow);

    return c.json({
      success: true,
      token,
      isAdmin,
      isPartner,
      partnerStatus,
      role,
      venueIds: partnerMeta.venueIds,
      customer: { ...customer, avatar: userRow.avatar || '', authProvider: 'google' },
    });
  });

  // 4. Apple Social Sign-In
  app.post('/api/auth/social/apple', async c => {
    const supabase = getSupabaseAdmin();
    const { email, name, identityToken } = await c.req.json().catch(() => ({}));
    if (!identityToken || typeof identityToken !== 'string') {
      return c.json({ error: 'Apple identityToken is required' }, 400);
    }

    let verifiedId = '';
    let verifiedEmail = '';
    let authUserId: string | null = null;

    try {
      const { data } = await supabase.auth.getUser(identityToken);
      if (data?.user) {
        authUserId = data.user.id;
        verifiedId = String(data.user.user_metadata?.provider_id || data.user.id);
        verifiedEmail = String(data.user.email || email || '').toLowerCase();
      }
    } catch (_) {}

    if (!verifiedId) {
      try {
        const claims = await verifyAppleIdentityToken(identityToken);
        verifiedId = String(claims.sub || '');
        verifiedEmail = String(claims.email || email || '').toLowerCase();
      } catch (err) {
        return c.json({ error: `Invalid Apple identity token: ${(err as Error).message}` }, 401);
      }
    }

    if (!verifiedEmail && verifiedId) {
      verifiedEmail = `${verifiedId.slice(0, 10)}@privaterelay.appleid.com`;
    }

    const { data: users } = await supabase.from('users').select('*');
    let userRow = (users || []).find(u =>
      (authUserId && u.auth_user_id === authUserId) ||
      (verifiedId && u.apple_user_id === verifiedId) ||
      (verifiedEmail && (u.email || '').toLowerCase() === verifiedEmail),
    );

    const isRealEmail = Boolean(verifiedEmail && !verifiedEmail.endsWith('@privaterelay.appleid.com'));
    if (!userRow) {
      const resolvedAuthId = await ensureSupabaseAuthUser(supabase, {
        email: verifiedEmail,
        name: name || 'Apple Member',
        existingAuthId: authUserId,
      });
      const { data: created, error } = await supabase
        .from('users')
        .insert({
          id: buildCleanUserId({ name: name || 'Apple Member', email: verifiedEmail }),
          auth_user_id: resolvedAuthId,
          apple_user_id: verifiedId || null,
          email: verifiedEmail,
          phone: '',
          name: String(name || 'Apple Member').slice(0, 80),
          auth_provider: 'apple',
          email_verified: isRealEmail,
          wallet_balance: 0,
        })
        .select('*')
        .single();
      if (error || !created) return c.json({ error: error?.message || 'Failed to save user' }, 500);
      userRow = created;
    } else if (!userRow.auth_user_id && authUserId) {
      await supabase.from('users').update({ auth_user_id: authUserId }).eq('id', userRow.id);
      userRow.auth_user_id = authUserId;
    }

    await claimCustomerBookings(supabase, userRow);
    await claimPartnerVenues(supabase, userRow);
    const partnerMeta = await buildPartnerAuthMeta(supabase, userRow);
    const isAdmin = partnerMeta.isOwner || isUserAdmin({ email: verifiedEmail });
    const role = isAdmin ? 'owner' : partnerMeta.role;
    const isPartner = isAdmin || partnerMeta.isPartner;
    const partnerStatus = isAdmin ? 'approved' : partnerMeta.partnerStatus;

    const token = await signJwt({
      id: userRow.id,
      email: userRow.email,
      phone: userRow.phone || '',
      name: userRow.name,
      provider: 'apple',
      isAdmin,
      isPartner,
      role,
    }, 90 * 24 * 3600);
    const customer = await sanitizeUserResponse(supabase, userRow);

    return c.json({
      success: true,
      token,
      isAdmin,
      isPartner,
      partnerStatus,
      role,
      venueIds: partnerMeta.venueIds,
      customer: { ...customer, authProvider: 'apple' },
    });
  });

  // 5. Email + Password Registration
  app.post('/api/auth/customer/register', async c => {
    const supabase = getSupabaseAdmin();
    const body = await c.req.json().catch(() => ({}));
    const cleanEmail = String(body.email || '').trim().toLowerCase();
    const cleanName = String(body.name || '').trim();
    const cleanPhone = String(body.phone || '').trim();
    const password = String(body.password || '');

    if (!cleanEmail || !password) return c.json({ error: 'Email and password are required' }, 400);
    if (!cleanEmail.includes('@') || !cleanEmail.includes('.')) {
      return c.json({ error: 'Please enter a valid email address' }, 400);
    }
    if (password.length < 8) return c.json({ error: 'Password must be at least 8 characters long' }, 400);

    const { emails, phones } = getAdminWhitelist();
    if (
      isUserAdmin({ email: cleanEmail, phone: cleanPhone }) ||
      emails.includes(cleanEmail) ||
      (cleanPhone && phones.includes(normalizeLocalPhone(cleanPhone)))
    ) {
      return c.json({
        error: 'Administrative identities cannot be registered through customer registration.',
      }, 403);
    }

    const { data: users } = await supabase.from('users').select('id, email, phone');
    if ((users || []).some(u => (u.email || '').toLowerCase() === cleanEmail)) {
      return c.json({ error: 'An account with this email already exists. Please sign in.' }, 409);
    }
    if (cleanPhone && (users || []).some(u => normalizeLocalPhone(u.phone) === normalizeLocalPhone(cleanPhone))) {
      return c.json({ error: 'This phone number is already registered to another account.' }, 409);
    }

    let emailVerified = false;
    if (body.code || body.otp) {
      const { data: rec } = await supabase.from('otp_challenges').select('*').eq('target', cleanEmail).maybeSingle();
      if (rec && Date.now() <= new Date(rec.expires_at).getTime()) {
        const inputHash = await sha256Hex(String(body.code || body.otp).trim());
        if (safeEqual(rec.hashed_code, inputHash)) {
          emailVerified = true;
          await supabase.from('otp_challenges').delete().eq('target', cleanEmail);
        }
      }
    }

    const passwordHash = bcrypt.hashSync(password, 10);
    let authUserId: string | null = null;
    try {
      const { data: auData } = await supabase.auth.admin.createUser({
        email: cleanEmail,
        password,
        email_confirm: true,
        user_metadata: { name: cleanName || cleanEmail.split('@')[0] },
      });
      authUserId = auData?.user?.id || null;
    } catch (_) {}

    const userId = buildCleanUserId({ name: cleanName || cleanEmail.split('@')[0], email: cleanEmail, phone: cleanPhone });
    const { data: created, error } = await supabase
      .from('users')
      .insert({
        id: userId,
        auth_user_id: authUserId,
        email: cleanEmail,
        name: cleanName || cleanEmail.split('@')[0],
        phone: normalizeLocalPhone(cleanPhone) || cleanPhone,
        password_hash: passwordHash,
        wallet_balance: 0,
        auth_provider: 'email_password',
        email_verified: emailVerified,
      })
      .select('*')
      .single();

    if (error || !created) return c.json({ error: error?.message || 'Registration failed' }, 500);
    await claimCustomerBookings(supabase, created);

    const token = await signJwt({
      id: created.id,
      email: created.email,
      name: created.name,
      phone: created.phone,
      role: 'customer',
      isAdmin: false,
    });

    return c.json({
      success: true,
      token,
      customer: {
        id: created.id,
        name: created.name,
        email: created.email,
        phone: created.phone,
        walletBalance: 0.0,
        emailVerified: Boolean(created.email_verified),
      },
    }, 201);
  });

  // 6. Email + Password Login
  app.post('/api/auth/customer/login', async c => {
    const supabase = getSupabaseAdmin();
    const { email, password } = await c.req.json().catch(() => ({}));
    const cleanEmail = String(email || '').trim().toLowerCase();
    if (!cleanEmail || !password) return c.json({ error: 'Email and password are required' }, 400);

    const { data: userRow } = await supabase
      .from('users')
      .select('*')
      .ilike('email', cleanEmail)
      .maybeSingle();

    let authenticated = false;
    if (userRow?.password_hash && !userRow.password_hash.includes(':')) {
      authenticated = bcrypt.compareSync(password, userRow.password_hash);
    }
    if (!authenticated) {
      const anon = getSupabaseAnon();
      const { error } = await anon.auth.signInWithPassword({ email: cleanEmail, password });
      if (!error) authenticated = true;
    }

    if (!authenticated || !userRow) {
      return c.json({ error: 'Invalid email or password.' }, 401);
    }

    await claimCustomerBookings(supabase, userRow);
    const meta = await buildPartnerAuthMeta(supabase, userRow);
    const token = await signJwt({
      id: userRow.id,
      email: userRow.email,
      name: userRow.name,
      phone: userRow.phone,
      isAdmin: meta.isAdmin,
      isPartner: meta.isPartner,
      partnerStatus: meta.partnerStatus,
      role: meta.role,
      venueIds: meta.venueIds,
    });

    return c.json({
      success: true,
      token,
      isAdmin: meta.isAdmin,
      isPartner: meta.isPartner,
      partnerStatus: meta.partnerStatus,
      role: meta.role,
      venueIds: meta.venueIds,
      customer: await sanitizeUserResponse(supabase, userRow),
    });
  });

  // 7. Verify Email OTP for signed-up user
  app.post('/api/auth/customer/verify-email', async c => {
    const supabase = getSupabaseAdmin();
    const { email, code } = await c.req.json().catch(() => ({}));
    const cleanEmail = normalizeTarget(email);
    if (!cleanEmail || !cleanEmail.includes('@') || !code) {
      return c.json({ error: 'Email and verification code are required' }, 400);
    }

    const { data: record } = await supabase.from('otp_challenges').select('*').eq('target', cleanEmail).maybeSingle();
    if (!record || Date.now() > new Date(record.expires_at).getTime()) {
      await supabase.from('otp_challenges').delete().eq('target', cleanEmail);
      return c.json({ error: 'No verification code was requested for this email, or it has expired.' }, 400);
    }

    const inputHash = await sha256Hex(String(code).trim());
    if (!safeEqual(record.hashed_code, inputHash)) {
      return c.json({ error: 'Invalid verification code.' }, 400);
    }

    await supabase.from('otp_challenges').delete().eq('target', cleanEmail);
    const { data: userRow } = await supabase.from('users').select('*').ilike('email', cleanEmail).maybeSingle();
    if (!userRow) return c.json({ error: 'User account not found' }, 404);

    await supabase.from('users').update({ email_verified: true }).eq('id', userRow.id);
    await claimCustomerBookings(supabase, { ...userRow, email_verified: true });
    return c.json({ success: true, emailVerified: true, message: 'Email verified successfully.' });
  });

  // 8. Logout
  const handleLogout = async (c: any) => {
    const authHeader = c.req.header('authorization') || '';
    if (authHeader.startsWith('Bearer ')) {
      await revokeToken(getSupabaseAdmin(), authHeader.slice(7));
    }
    return c.json({ success: true, message: 'Logged out successfully.' });
  };
  app.post('/api/auth/customer/logout', handleLogout);
  app.post('/api/auth/logout', handleLogout);

  // 9. Admin / Partner Portal Login
  app.post('/api/auth/login', async c => {
    const supabase = getSupabaseAdmin();
    const { email, password, token } = await c.req.json().catch(() => ({}));

    if (token && typeof token === 'string') {
      const resolved = await resolveUserFromToken(supabase, token);
      if (resolved?.userRow) {
        await claimPartnerVenues(supabase, resolved.userRow);
        const meta = await buildPartnerAuthMeta(supabase, resolved.userRow);
        if (meta.isAdmin || meta.isPartner) {
          const adminToken = await signJwt({
            id: resolved.userRow.id,
            email: resolved.userRow.email,
            phone: resolved.userRow.phone,
            isAdmin: meta.isAdmin,
            isPartner: meta.isPartner,
            partnerStatus: meta.partnerStatus,
            role: meta.role,
            venueIds: meta.venueIds,
          }, 12 * 3600);
          return c.json({
            success: true,
            token: adminToken,
            isAdmin: meta.isAdmin,
            isPartner: meta.isPartner,
            partnerStatus: meta.partnerStatus,
            role: meta.role,
            venueIds: meta.venueIds,
            admin: await sanitizeUserResponse(supabase, resolved.userRow),
          });
        }
      }
      return c.json({ error: 'Access denied: Identity is not authorized for administrative access.' }, 403);
    }

    if (typeof email === 'string' && typeof password === 'string') {
      const cleanEmail = email.trim().toLowerCase();
      const { emails } = getAdminWhitelist();
      const adminPassword = getEnv('ADMIN_PASSWORD');
      if (emails.includes(cleanEmail) && adminPassword && safeEqual(password, adminPassword)) {
        const adminToken = await signJwt({
          email: cleanEmail,
          isAdmin: true,
          isPartner: false,
          partnerStatus: 'approved',
          role: 'owner',
        }, 12 * 3600);
        return c.json({
          success: true,
          token: adminToken,
          isAdmin: true,
          isPartner: false,
          partnerStatus: 'approved',
          role: 'owner',
          admin: { email: cleanEmail, role: 'owner', isAdmin: true },
        });
      }

      const { data: userRow } = await supabase.from('users').select('*').ilike('email', cleanEmail).maybeSingle();
      if (userRow?.password_hash && bcrypt.compareSync(password, userRow.password_hash)) {
        await claimPartnerVenues(supabase, userRow);
        const meta = await buildPartnerAuthMeta(supabase, userRow);
        if (!meta.isAdmin && !meta.isPartner) {
          return c.json({ error: 'Partner account is pending verification.', partnerStatus: meta.partnerStatus }, 403);
        }
        const adminToken = await signJwt({
          id: userRow.id,
          email: userRow.email,
          phone: userRow.phone,
          isAdmin: meta.isAdmin,
          isPartner: meta.isPartner,
          partnerStatus: meta.partnerStatus,
          role: meta.role,
          venueIds: meta.venueIds,
        }, 12 * 3600);
        return c.json({
          success: true,
          token: adminToken,
          isAdmin: meta.isAdmin,
          isPartner: meta.isPartner,
          partnerStatus: meta.partnerStatus,
          role: meta.role,
          venueIds: meta.venueIds,
          admin: await sanitizeUserResponse(supabase, userRow),
        });
      }
    }

    return c.json({ error: 'Invalid credentials' }, 401);
  });
}
