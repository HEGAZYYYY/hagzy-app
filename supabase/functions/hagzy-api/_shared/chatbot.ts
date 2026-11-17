import { SupabaseClient } from '@supabase/supabase-js';
import { getEnv, normalizeLocalPhone } from './db.ts';

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

  let matchedBooking: Record<string, any> | null = null;
  if (bookingId) {
    const { data } = await supabase
      .from('bookings')
      .select('*')
      .eq('id', bookingId)
      .eq('cancelled', false)
      .maybeSingle();
    matchedBooking = data;
  }

  if (!matchedBooking && cleanPhone) {
    const norm = normalizeLocalPhone(cleanPhone);
    const { data: candidates } = await supabase
      .from('bookings')
      .select('*')
      .eq('cancelled', false)
      .order('created_at', { ascending: false })
      .limit(50);
    matchedBooking = (candidates || []).find(b => {
      const bp = normalizeLocalPhone(b.customer_phone);
      return bp && (bp === norm || cleanPhone.endsWith(bp));
    }) || null;
  }

  const idMatch = cleanMsg.match(/(?:bk_[a-zA-Z0-9_]+|\b17\d{14,}\b)/i);
  if (idMatch && !matchedBooking) {
    const { data } = await supabase
      .from('bookings')
      .select('*')
      .eq('id', idMatch[0])
      .eq('cancelled', false)
      .maybeSingle();
    matchedBooking = data;
  }

  let venue: Record<string, any> | null = null;
  if (matchedBooking) {
    const { data } = await supabase
      .from('venues')
      .select('id, name, extra')
      .eq('id', matchedBooking.venue_id)
      .maybeSingle();
    venue = data;
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

  if (lower.includes('status') || lower.includes('booking') || lower.includes('حجز') || lower.includes('حالة') || idMatch) {
    if (matchedBooking) {
      const isConfirmed = matchedBooking.status === 'confirmed';
      const venueName = venue?.name || matchedBooking.venue_name || matchedBooking.venue_id;
      const price = matchedBooking.total_price || matchedBooking.due_now || 0;
      return arabic
        ? `📌 تفاصيل حجزك في حجزي:\n• المكان: ${venueName}\n• الموعد: ${matchedBooking.starts_at}\n• الحالة: ${isConfirmed ? 'مؤكد رسمياً ✓' : 'حجز مؤقت (بانتظار العربون) ⏳'}\n• المبلغ: ${price} جنيه\n• رقم الحجز: ${matchedBooking.id}`
        : `📌 Your Hagzy Reservation:\n• Venue: ${venueName}\n• Start: ${matchedBooking.starts_at}\n• Status: ${isConfirmed ? 'Confirmed ✓' : 'Pending Deposit ⏳'}\n• Price: ${price} EGP\n• ID: ${matchedBooking.id}`;
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
    ? 'أهلاً بك في خدمة عملاء حجزي! أرسل "حجزي" لمعرفة تفاصيل حجزك، أو "دفع" لطرق الدفع، أو "إلغاء".'
    : 'Welcome to Hagzy Assistant! Reply "status" for booking details, "pay" for deposit options, or "cancel".';
}
