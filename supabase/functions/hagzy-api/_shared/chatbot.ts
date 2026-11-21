import { SupabaseClient } from '@supabase/supabase-js';
import { computeBookingQrSig, buildBookingQrCheckInUrl } from './auth.ts';
import { getEnv, normalizeLocalPhone } from './db.ts';

function formatReminderLabelArabic(mins: number): string {
  if (mins <= 0) return 'متوقف';
  if (mins < 60) return `قبل الموعد بـ ${mins} دقيقة`;
  if (mins === 60) return 'قبل الموعد بساعة واحدة';
  if (mins === 120) return 'قبل الموعد بساعتين';
  if (mins === 1440) return 'قبل الموعد بـ 24 ساعة';
  const hrs = Math.round(mins / 60);
  return `قبل الموعد بـ ${hrs} ساعات`;
}

function formatReminderLabelEnglish(mins: number): string {
  if (mins <= 0) return 'Disabled';
  if (mins < 60) return `${mins} minutes before`;
  if (mins === 1440) return '24 hours before';
  const hrs = Math.round(mins / 60);
  return `${hrs} hour${hrs === 1 ? '' : 's'} before`;
}

function parseRequestedReminderMinutes(text: string): number | null {
  const lower = text.toLowerCase().trim();
  if (/^(?:تذكير\s*(?:ايقاف|إيقاف|لا)|الغاء التذكير|إلغاء التذكير|remind\s*off)$/i.test(lower)) {
    return 0;
  }
  const arMatch = lower.match(/(?:تذكير|ذكرني)\s+(\d+)\s*(دقيق(?:ة|ه)|د|ساع(?:ة|ه)|س|ساعات|يوم)?/i);
  if (arMatch) {
    const val = Number(arMatch[1]);
    const unit = arMatch[2] || '';
    if (unit.startsWith('د')) return val;
    if (unit.startsWith('ي')) return val * 1440;
    if (val === 30) return 30;
    if (val === 24) return 1440;
    if ([1, 2, 6, 12].includes(val)) return val * 60;
    return val;
  }
  const enMatch = lower.match(/remind\s+(\d+)\s*(m|min|mins|minute|minutes|h|hr|hrs|hour|hours|d|day|days)?/i);
  if (enMatch) {
    const val = Number(enMatch[1]);
    const unit = (enMatch[2] || '').toLowerCase();
    if (unit.startsWith('m')) return val;
    if (unit.startsWith('d')) return val * 1440;
    if (unit.startsWith('h')) return val * 60;
    if (val === 30) return 30;
    if (val === 24) return 1440;
    return [1, 2, 6, 12].includes(val) ? val * 60 : val;
  }
  return null;
}

export async function processChatbotMessage(
  supabase: SupabaseClient,
  {
    message = '',
    senderPhone = '',
    bookingId = '',
    language = 'AR',
  }: {
    message: string;
    senderPhone?: string;
    bookingId?: string;
    language?: string;
  },
): Promise<string> {
  const arabic = language !== 'EN';
  const cleanMsg = String(message || '').trim();
  const lower = cleanMsg.toLowerCase();
  const cleanPhone = senderPhone.replace(/\D/g, '');
  const nowIso = new Date().toISOString();

  let activeBookings: Record<string, any>[] = [];
  if (bookingId) {
    const { data } = await supabase
      .from('bookings')
      .select('*')
      .eq('id', bookingId)
      .eq('cancelled', false)
      .maybeSingle();
    if (data) activeBookings = [data];
  }

  if (activeBookings.length === 0 && cleanPhone) {
    const norm = normalizeLocalPhone(cleanPhone);
    const { data: candidates } = await supabase
      .from('bookings')
      .select('*')
      .eq('cancelled', false)
      .not('status', 'in', '("cancelled","expired","no_show","completed")')
      .order('starts_at', { ascending: true })
      .limit(100);
    const matching = (candidates || []).filter(b => {
      const bp = normalizeLocalPhone(b.customer_phone);
      return bp && (bp === norm || cleanPhone.endsWith(bp));
    });
    const upcoming = matching.filter(b => !b.ends_at || b.ends_at >= nowIso || b.starts_at >= nowIso);
    activeBookings = (upcoming.length > 0 ? upcoming : matching).slice(0, 5);
  }

  const idMatch = cleanMsg.match(/(?:bk_[a-zA-Z0-9_]+|\b17\d{14,}\b)/i);
  if (idMatch && activeBookings.length === 0) {
    const { data } = await supabase
      .from('bookings')
      .select('*')
      .eq('id', idMatch[0])
      .eq('cancelled', false)
      .maybeSingle();
    if (data) activeBookings = [data];
  }

  const matchedBooking = activeBookings[0] || null;
  const venueIds = Array.from(new Set(activeBookings.map(b => b.venue_id).filter(Boolean)));
  const venueMap = new Map<string, Record<string, any>>();
  if (venueIds.length > 0) {
    const { data: venues } = await supabase
      .from('venues')
      .select('id, name, extra')
      .in('id', venueIds);
    for (const v of venues || []) venueMap.set(v.id, v);
  }
  const venue = matchedBooking ? venueMap.get(matchedBooking.venue_id) || null : null;

  const requestedReminder = parseRequestedReminderMinutes(cleanMsg);
  if (requestedReminder !== null) {
    if (!matchedBooking) {
      return arabic
        ? 'لم يتم العثور على حجز نشط مرتبط برقمك لتعديل وقت التذكير.'
        : 'No active booking found for your phone number to update reminder timing.';
    }
    const clamped = Math.max(0, Math.min(10080, Math.round(requestedReminder)));
    await supabase
      .from('bookings')
      .update({ reminder_offset_minutes: clamped, reminder_sent_at: null })
      .eq('id', matchedBooking.id);
    return arabic
      ? `⏰ تم تحديث موعد التذكير لحجزك #${matchedBooking.id} إلى: *${formatReminderLabelArabic(clamped)}*.`
      : `⏰ WhatsApp reminder updated for booking #${matchedBooking.id}: *${formatReminderLabelEnglish(clamped)}*.`;
  }

  const isLikelyRefNumber =
    /^(?:ref\s*[:=]?\s*)?[0-9]{6,24}$/i.test(cleanMsg) ||
    /(?:رقم العملية|المرجعي|كود التحويل)\s*[:=]?\s*([0-9]{6,24})/i.test(cleanMsg);
  if (isLikelyRefNumber && matchedBooking) {
    const rawRef = cleanMsg.replace(/\D/g, '');
    if (rawRef.length >= 6) {
      await supabase
        .from('bookings')
        .update({ payment_reference: rawRef, status: 'pending_confirmation' })
        .eq('id', matchedBooking.id);
      return arabic
        ? `✅ تم استلام رقم العملية بنجاح (${rawRef})!\n\n📌 حجزك في "${venue?.name || matchedBooking.venue_id}" تم تحديثه إلى: "بانتظار المراجعة والتأكيد".`
        : `✅ Payment reference (${rawRef}) recorded successfully! Your reservation at "${venue?.name || matchedBooking.venue_id}" is now under review.`;
    }
  }

  if (lower.includes('pay') || lower.includes('deposit') || lower.includes('دفع') || lower.includes('عربون') || lower.includes('انستاباي') || lower.includes('فودافون')) {
    const insta = venue?.extra?.instaPayAddress || 'hagzy@instapay';
    const vf = venue?.extra?.vodafoneCashNumber || getEnv('ADMIN_PHONE', '01041570557');
    return arabic
      ? `💳 طرق دفع العربون المتاحة في حجزي:\n١. فوري باي: كود 78890\n٢. إنستاباي: ${insta}\n٣. فودافون كاش: ${vf}\n\n💡 أرسل رقم العملية هنا بعد التحويل لتأكيد حجزك.`
      : `💳 Deposit Payment Options:\n1. FawryPay: 78890\n2. InstaPay: ${insta}\n3. Vodafone Cash: ${vf}\n\n💡 Reply with your transaction reference number after transferring.`;
  }

  if (lower.includes('status') || lower.includes('booking') || lower.includes('حجز') || lower.includes('حجزي') || lower.includes('حالة') || idMatch) {
    if (activeBookings.length > 0) {
      const blocks: string[] = [];
      for (let i = 0; i < activeBookings.length; i++) {
        const b = activeBookings[i];
        const v = venueMap.get(b.venue_id);
        const venueName = v?.name || b.venue_name || b.venue_id;
        const unitLabel = b.unit_name ? ` — ${b.unit_name}` : '';
        const isConfirmed = Boolean(b.confirmed) || b.status === 'confirmed' || b.status === 'checked_in';
        const total = Number(b.total_price || b.due_now || 0);
        const paid = Number(b.actual_paid_amount || (isConfirmed ? b.deposit_amount || 0 : 0));
        const remaining = Math.max(0, Number((total - paid).toFixed(2)));
        const remOffset = b.reminder_offset_minutes !== undefined && b.reminder_offset_minutes !== null
          ? Number(b.reminder_offset_minutes)
          : 120;
        const sig = await computeBookingQrSig(b.id, b.venue_id);
        const qrUrl = buildBookingQrCheckInUrl(b.id, sig);
        blocks.push(
          arabic
            ? `*${i + 1}. ${venueName}${unitLabel}*\n• الموعد: ${b.starts_at}\n• الحالة: ${isConfirmed ? 'مؤكد ✓' : 'بانتظار العربون ⏳'}\n• العربون المدفوع: ${paid} ج.م | المتبقي بالمكان: ${remaining} ج.م\n• التذكير: ${formatReminderLabelArabic(remOffset)}\n• كود الدخول QR للمكان: ${qrUrl}\n• رقم الحجز: ${b.id}`
            : `*${i + 1}. ${venueName}${unitLabel}*\n• Start: ${b.starts_at}\n• Status: ${isConfirmed ? 'Confirmed ✓' : 'Pending Deposit ⏳'}\n• Deposit Paid: ${paid} EGP | Due at Venue: ${remaining} EGP\n• Reminder: ${formatReminderLabelEnglish(remOffset)}\n• Venue Check-In QR: ${qrUrl}\n• Booking ID: ${b.id}`,
        );
      }
      const footer = arabic
        ? '\n\n⏰ لتغيير وقت التذكير أرسل مثلاً: "تذكير 30" (دقيقة) أو "تذكير 1" / "تذكير 2" / "تذكير 6" / "تذكير 24" (ساعة) أو "تذكير ايقاف".'
        : '\n\n⏰ To change reminder timing reply e.g. "remind 30m", "remind 1h", "remind 2h", "remind 6h", "remind 24h", or "remind off".';
      return `${arabic ? '📌 *حجوزاتك النشطة في حجزي:*\n\n' : '📌 *Your Active Hagzy Bookings:*\n\n'}${blocks.join('\n\n')}${footer}`;
    }
    return arabic
      ? 'لم نتمكن من العثور على حجز نشط مرتبط برقمك حالياً. أرسل رقم الحجز إن وجد.'
      : 'No active reservation was found for your phone number. Reply with your Booking ID if you have one.';
  }

  if (lower.includes('cancel') || lower.includes('إلغاء') || lower.includes('الغاء')) {
    return arabic
      ? '⚠️ يمكنك إلغاء الحجز واسترداد العربون لمحفظتك قبل الموعد بـ 6 ساعات مباشرة من صفحة "حجوزاتي" في التطبيق.'
      : '⚠️ You can cancel your booking up to 6 hours before the slot from the My Bookings tab for a wallet refund.';
  }

  return arabic
    ? 'أهلاً بك في خدمة عملاء حجزي! أرسل "حجزي" لمعرفة تفاصيل حجوزاتك وQR الدخول، أو "تذكير 2" لضبط التنبيه، أو "دفع" لطرق الدفع.'
    : 'Welcome to Hagzy Assistant! Reply "status" for your bookings & QR pass, "remind 2h" to set reminder timing, "pay" for deposit options, or "cancel".';
}
