const admin = require('firebase-admin');
const { getFirestore } = require('firebase-admin/firestore');
const { getAuth } = require('firebase-admin/auth');
const sa = require('../firebase-credentials.js');

const app = admin.initializeApp({ credential: admin.cert(sa) });
const db = getFirestore(app);
const auth = getAuth(app);

function normalizeLocalPhone(rawPhone) {
  if (!rawPhone) return '';
  const digits = String(rawPhone).replace(/\D/g, '');
  if (!digits) return '';
  if (digits.startsWith('20') && digits.length >= 12) {
    return '0' + digits.slice(2);
  }
  if (digits.length === 10 && /^(10|11|12|15)/.test(digits)) {
    return '0' + digits;
  }
  return digits;
}

function formatE164Phone(rawPhone) {
  const clean = normalizeLocalPhone(rawPhone);
  if (!clean) return '';
  if (clean.startsWith('0') && clean.length === 11) {
    return '+2' + clean;
  }
  return '+' + clean.replace(/^\+/, '');
}

function buildCleanUserId({ name, email, phone }) {
  const rawName = String(name || '').trim().toLowerCase();
  const rawEmail = String(email || '').trim().toLowerCase();
  const cleanPhone = normalizeLocalPhone(phone);
  let slug = rawName.replace(/[^a-z0-9]+/g, '_').replace(/^_+|_+$/g, '');
  if (!slug || slug === 'hagzy_member' || slug === 'member' || slug === 'apple_member') {
    if (rawEmail && rawEmail.includes('@')) {
      slug = rawEmail.split('@')[0].replace(/[^a-z0-9]+/g, '_').replace(/^_+|_+$/g, '');
    } else if (cleanPhone) {
      slug = 'user_' + cleanPhone.slice(-6);
    } else {
      slug = 'member';
    }
  }
  return 'usr_' + slug.slice(0, 28);
}

async function run() {
  console.log('🚀 Starting Cloud Firestore Database Cleanup & User-Booking Linking...');

  // 1. Load Venues for human-readable venueName lookup
  const venuesSnap = await db.collection('venues').get();
  const venuesMap = new Map();
  venuesSnap.forEach(doc => {
    const v = doc.data();
    venuesMap.set(doc.id, v);
  });
  console.log(`📍 Loaded ${venuesMap.size} venues.`);

  // 2. Load Firebase Auth Users & unify duplicate identities (e.g. Mohamed Hegazy phone + email)
  const authList = await auth.listUsers();
  const canonicalUsers = new Map();

  for (const au of authList.users) {
    const name = (au.displayName || '').trim();
    const email = (au.email || '').trim().toLowerCase();
    const phone = normalizeLocalPhone(au.phoneNumber || '');
    const id = buildCleanUserId({ name, email, phone });

    if (canonicalUsers.has(id)) {
      const existing = canonicalUsers.get(id);
      if (!existing.email && email) existing.email = email;
      if (!existing.phone && phone) {
        existing.phone = phone;
        existing.phoneE164 = formatE164Phone(phone);
      }
      if (!existing.firebaseUids.includes(au.uid)) {
        existing.firebaseUids.push(au.uid);
      }
    } else {
      canonicalUsers.set(id, {
        id,
        name: name || (email ? email.split('@')[0] : 'Hagzy Member'),
        phone,
        phoneE164: phone ? formatE164Phone(phone) : '',
        email,
        firebaseUid: au.uid,
        firebaseUids: [au.uid],
        authProvider: email && phone ? 'google_and_phone' : (email ? 'google' : 'phone'),
        walletBalance: 50,
        createdAt: au.metadata.creationTime ? new Date(au.metadata.creationTime).toISOString() : new Date().toISOString(),
        bookings: []
      });
    }
  }

  console.log(`👥 Unified ${canonicalUsers.size} canonical users from Firebase Auth:`);
  for (const [id, u] of canonicalUsers.entries()) {
    console.log(`   - ${id}: ${u.name} | phone: ${u.phone || '-'} | email: ${u.email || '-'}`);
  }

  // 3. Inspect all bookings in Firestore: purge fake/test bookings & link real bookings to users
  const bookingsSnap = await db.collection('bookings').get();
  let deletedJunkCount = 0;
  let linkedBookingsCount = 0;

  for (const bDoc of bookingsSnap.docs) {
    const b = bDoc.data();
    const bId = bDoc.id;
    const custName = String(b.customer || '').trim();
    const bPhone = normalizeLocalPhone(b.phone || b.customerPhone || '');
    const bEmail = String(b.email || '').trim().toLowerCase();

    // Detect obvious fake/junk test bookings
    const isJunkTest =
      bId.startsWith('bk_test_') ||
      custName.toLowerCase() === 'name' ||
      custName.toLowerCase() === 'mo' ||
      custName.toLowerCase() === 'mo1' ||
      custName.toLowerCase().includes('multi device test') ||
      bPhone === '32423432423425' ||
      bPhone === '1235444444' ||
      bPhone === '0615121';

    if (isJunkTest) {
      await db.collection('bookings').doc(bId).delete();
      deletedJunkCount++;
      console.log(`🗑️ Deleted junk test booking: ${bId} (${custName} / ${bPhone})`);
      continue;
    }

    // Match booking to canonical user
    let matchedUser = null;
    const candidateId = buildCleanUserId({ name: custName, email: bEmail, phone: bPhone });
    if (canonicalUsers.has(candidateId)) {
      matchedUser = canonicalUsers.get(candidateId);
    }
    if (!matchedUser && bEmail) {
      for (const u of canonicalUsers.values()) {
        if (u.email && u.email === bEmail) {
          matchedUser = u;
          break;
        }
      }
    }
    if (!matchedUser && bPhone) {
      for (const u of canonicalUsers.values()) {
        if (u.phone && u.phone === bPhone) {
          matchedUser = u;
          break;
        }
      }
    }
    if (!matchedUser) {
      for (const u of canonicalUsers.values()) {
        if (custName && u.name.toLowerCase().startsWith(custName.toLowerCase())) {
          matchedUser = u;
          break;
        }
      }
    }

    // Backfill user phone if booking had a valid Egyptian mobile number and user didn't have one yet
    if (matchedUser && !matchedUser.phone && /^01[0125]\d{8}$/.test(bPhone)) {
      matchedUser.phone = bPhone;
      matchedUser.phoneE164 = formatE164Phone(bPhone);
    }

    const venueObj = venuesMap.get(b.venueId);
    const venueName = (venueObj && venueObj.name) || b.venueName || b.venueId || '';
    const userId = matchedUser ? matchedUser.id : candidateId;
    const finalPhone = (matchedUser && matchedUser.phone) || bPhone;
    const finalEmail = (matchedUser && matchedUser.email) || bEmail;
    const finalCustomerName = (matchedUser && matchedUser.name) || custName;

    const cleanBookingDoc = {
      id: String(bId),
      userId,
      ownerId: userId,
      customerId: userId,
      userRef: db.doc(`users/${userId}`),
      userBookingRef: db.doc(`users/${userId}/bookings/${bId}`),
      venueId: String(b.venueId || ''),
      venueName: String(venueName),
      ...(b.venueId ? { venueRef: db.doc(`venues/${b.venueId}`) } : {}),
      itemId: String(b.itemId || ''),
      customer: String(finalCustomerName),
      phone: String(finalPhone),
      email: String(finalEmail),
      startsAt: String(b.startsAt || ''),
      durationMinutes: Number(b.durationMinutes) || 60,
      price: Number(b.price) || 0,
      dueNow: Number(b.dueNow !== undefined ? b.dueNow : 0),
      status: String(b.status || 'pending_payment'),
      paymentStatus: String(b.paymentStatus || (b.status === 'confirmed' ? 'paid' : 'unpaid')),
      paymentMethod: String(b.paymentMethod || (b.paymentProof && b.paymentProof.method) || ''),
      paymentReference: String(b.paymentReference || (b.paymentProof && b.paymentProof.reference) || ''),
      ...(b.paymentProof ? { paymentProof: b.paymentProof } : {}),
      cancelled: Boolean(b.cancelled || b.status === 'cancelled'),
      createdAt: String(b.createdAt || new Date().toISOString()),
      updatedAt: new Date().toISOString()
    };

    // Update top-level bookings/{bookingId}
    await db.collection('bookings').doc(bId).set(cleanBookingDoc);

    // Write directly inside users/{userId}/bookings/{bookingId} subcollection
    await db.collection('users').doc(userId).collection('bookings').doc(bId).set(cleanBookingDoc);

    if (matchedUser) {
      matchedUser.bookings.push({
        id: String(bId),
        venueId: cleanBookingDoc.venueId,
        venueName: cleanBookingDoc.venueName,
        itemId: cleanBookingDoc.itemId,
        startsAt: cleanBookingDoc.startsAt,
        durationMinutes: cleanBookingDoc.durationMinutes,
        price: cleanBookingDoc.price,
        dueNow: cleanBookingDoc.dueNow,
        status: cleanBookingDoc.status,
        paymentStatus: cleanBookingDoc.paymentStatus,
        paymentMethod: cleanBookingDoc.paymentMethod,
        paymentReference: cleanBookingDoc.paymentReference,
        createdAt: cleanBookingDoc.createdAt,
        bookingRef: db.doc(`bookings/${bId}`)
      });
    }
    linkedBookingsCount++;
    console.log(`🔗 Linked booking ${bId} -> users/${userId}/bookings/${bId}`);
  }

  // 4. Write all canonical users to users/{userId} with their embedded bookings summary & counts
  for (const [id, u] of canonicalUsers.entries()) {
    u.bookings.sort((a, b) => String(b.startsAt || '').localeCompare(String(a.startsAt || '')));
    const confirmedCount = u.bookings.filter(x => x.status === 'confirmed').length;
    const pendingCount = u.bookings.filter(x => x.status !== 'confirmed' && x.status !== 'cancelled').length;

    const userDoc = {
      id: u.id,
      name: u.name,
      phone: u.phone,
      phoneE164: u.phoneE164,
      email: u.email,
      firebaseUid: u.firebaseUid,
      firebaseUids: u.firebaseUids,
      authProvider: u.authProvider,
      walletBalance: u.walletBalance,
      bookingsCount: u.bookings.length,
      confirmedBookingsCount: confirmedCount,
      pendingBookingsCount: pendingCount,
      bookings: u.bookings,
      createdAt: u.createdAt,
      updatedAt: new Date().toISOString()
    };

    await db.collection('users').doc(id).set(userDoc);
    console.log(`✅ Saved user doc users/${id} (${u.name}) with ${u.bookings.length} linked bookings.`);
  }

  console.log(`\n🎉 Firestore Reorganization Complete!`);
  console.log(`   - Canonical Users in 'users' collection: ${canonicalUsers.size}`);
  console.log(`   - Deleted junk/test bookings: ${deletedJunkCount}`);
  console.log(`   - Linked real bookings (in 'users/{id}/bookings' + 'bookings'): ${linkedBookingsCount}`);
}

run().catch(err => {
  console.error('Migration error:', err);
  process.exit(1);
});

