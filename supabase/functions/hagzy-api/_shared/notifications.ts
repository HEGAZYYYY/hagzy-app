import { SupabaseClient } from '@supabase/supabase-js';
import { getEnv } from './db.ts';

function formatEgyptWhatsAppNumber(phone: string): string {
  const clean = phone.replace(/\D/g, '');
  let formatted = clean;
  if (formatted.startsWith('0')) formatted = `2${formatted}`;
  else if (!formatted.startsWith('20') && formatted.length === 10) formatted = `20${formatted}`;
  return formatted.startsWith('+') ? formatted : `+${formatted}`;
}

export async function sendWhatsAppMessage({
  phone,
  message,
}: {
  phone: string;
  message: string;
}) {
  if (!phone) return { sent: false, provider: 'none' };

  const instanceId = getEnv('ULTRAMSG_INSTANCE_ID');
  const ultraToken = getEnv('ULTRAMSG_TOKEN');
  if (instanceId && ultraToken) {
    try {
      const formatted = formatEgyptWhatsAppNumber(phone);
      const params = new URLSearchParams({ token: ultraToken, to: formatted, body: message });
      const resp = await fetch(`https://api.ultramsg.com/${instanceId}/messages/chat`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
        body: params,
      });
      const data = await resp.json().catch(() => ({}));
      return { sent: resp.ok, provider: 'ultramsg', data };
    } catch (e) {
      console.error('UltraMsg error:', (e as Error).message);
    }
  }

  return await sendSmsOrWhatsApp({ phone, message });
}

export async function notifyVenueOwner(
  supabase: SupabaseClient,
  {
    venue,
    booking,
    eventType,
    extraReason = '',
  }: {
    venue: Record<string, any> | null;
    booking: Record<string, any>;
    eventType: 'booking_created' | 'booking_confirmed' | 'booking_cancelled' | 'booking_checked_in';
    extraReason?: string;
  },
) {
  const venueId = String(venue?.id || booking?.venueId || booking?.venue_id || '');
  const venueName = String(venue?.name || booking?.venueName || booking?.venue_name || venueId);
  const unitName = String(booking?.unitName || booking?.unit_name || '');
  const customerName = String(booking?.customerName || booking?.customer_name || 'Guest');
  const customerPhone = String(booking?.customerPhone || booking?.phone || booking?.customer_phone || '');
  const startsAtRaw = booking?.startsAt || booking?.starts_at || '';
  const totalPrice = Number(booking?.totalPrice ?? booking?.total_price ?? booking?.price ?? 0);
  const paidAmount = Number(booking?.actualPaidAmount ?? booking?.actual_paid_amount ?? 0);
  const depositAmount = Number(booking?.depositAmount ?? booking?.deposit_amount ?? 0);
  const paidSoFar = paidAmount > 0 ? paidAmount : (booking?.confirmed ? depositAmount : 0);
  const remainingDue = Math.max(0, Number((totalPrice - paidSoFar).toFixed(2)));
  const statusLabel = eventType === 'booking_confirmed'
    ? 'مؤكد ✓ (تم استلام العربون)'
    : eventType === 'booking_cancelled'
      ? 'ملغي ✕'
      : eventType === 'booking_checked_in'
        ? 'تم تسجيل الحضور ✓'
        : 'حجز جديد (بانتظار الدفع)';

  const titles: Record<string, string> = {
    booking_created: `حجز جديد في ${venueName}${unitName ? ` — ${unitName}` : ''}`,
    booking_confirmed: `تم تأكيد حجز ${customerName} في ${venueName}`,
    booking_cancelled: `تم إلغاء حجز ${customerName} في ${venueName}`,
    booking_checked_in: `تم تسجيل وصول ${customerName} في ${venueName}`,
  };
  const title = titles[eventType] || `تحديث حجز في ${venueName}`;
  const bodyLines = [
    `🏟️ المكان: ${venueName}${unitName ? ` (${unitName})` : ''}`,
    `👤 العميل: ${customerName}${customerPhone ? ` · ${customerPhone}` : ''}`,
    `📅 الموعد: ${startsAtRaw}`,
    `📌 الحالة: ${statusLabel}`,
    `💰 المدفوع: ${paidSoFar} ج.م | المتبقي عند الوصول: ${remainingDue} ج.م`,
    `🆔 رقم الحجز: ${booking?.id || ''}`,
  ];
  if (extraReason) bodyLines.push(`ℹ️ السبب: ${extraReason}`);
  const body = bodyLines.join('\n');

  const ownerPhone = String(
    venue?.ownerPhone || venue?.phone || venue?.extra?.ownerPhone || venue?.extra?.phone || '',
  ).trim();
  let whatsappSent = false;
  if (ownerPhone) {
    const waRes = await sendWhatsAppMessage({
      phone: ownerPhone,
      message: `🔔 *${title}*\n\n${body}`,
    });
    whatsappSent = Boolean(waRes?.sent);
  }

  const notifRow = {
    id: `pn_${Date.now()}_${crypto.randomUUID().slice(0, 6)}`,
    owner_id: venue?.ownerId && venue.ownerId !== 'admin' ? venue.ownerId : null,
    venue_id: venueId || null,
    booking_id: booking?.id || null,
    event_type: eventType,
    title,
    body,
    whatsapp_sent: whatsappSent,
    read: false,
    created_at: new Date().toISOString(),
  };

  try {
    const { error } = await supabase.from('partner_notifications').insert(notifRow);
    if (error && notifRow.owner_id) {
      await supabase.from('partner_notifications').insert({ ...notifRow, owner_id: null });
    }
  } catch (e) {
    console.warn('[notifyVenueOwner] Failed to persist in-app notification:', (e as Error).message);
  }

  return { title, whatsappSent };
}

export async function sendSmsOrWhatsApp({
  phone,
  message,
  otp = '',
}: {
  phone: string;
  message: string;
  otp?: string;
}) {
  if (!phone) return { sent: false, provider: 'none' };

  const smsmisrUser = getEnv('SMSMISR_USERNAME');
  const smsmisrPass = getEnv('SMSMISR_PASSWORD');
  if (smsmisrUser && smsmisrPass) {
    try {
      const clean = phone.replace(/\D/g, '');
      const formatted = clean.startsWith('0')
        ? `2${clean}`
        : (clean.startsWith('20') ? clean : `20${clean}`);
      const payload = new URLSearchParams({
        environment: getEnv('SMSMISR_ENV', '1'),
        username: smsmisrUser,
        password: smsmisrPass,
        sender: getEnv('SMSMISR_SENDER', 'HAGZY'),
        mobile: formatted,
        language: '2',
        message,
      });
      const resp = await fetch('https://smsmisr.com/api/SMS/', {
        method: 'POST',
        headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
        body: payload,
      });
      const data = await resp.json().catch(() => ({}));
      return { sent: resp.ok, provider: 'smsmisr', data };
    } catch (e) {
      console.error('SMS Misr error:', (e as Error).message);
    }
  }

  const instanceId = getEnv('ULTRAMSG_INSTANCE_ID');
  const ultraToken = getEnv('ULTRAMSG_TOKEN');
  if (instanceId && ultraToken) {
    try {
      const clean = phone.replace(/\D/g, '');
      let formatted = clean;
      if (formatted.startsWith('0')) formatted = `2${formatted}`;
      else if (!formatted.startsWith('20') && formatted.length === 10) formatted = `20${formatted}`;
      if (!formatted.startsWith('+')) formatted = `+${formatted}`;

      const params = new URLSearchParams({ token: ultraToken, to: formatted, body: message });
      const resp = await fetch(`https://api.ultramsg.com/${instanceId}/messages/chat`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
        body: params,
      });
      const data = await resp.json().catch(() => ({}));
      return { sent: resp.ok, provider: 'ultramsg', data };
    } catch (e) {
      console.error('UltraMsg error:', (e as Error).message);
    }
  }

  const twilioSid = getEnv('TWILIO_ACCOUNT_SID');
  const twilioToken = getEnv('TWILIO_AUTH_TOKEN');
  const twilioFrom = getEnv('TWILIO_PHONE_NUMBER');
  if (twilioSid && twilioToken && twilioFrom) {
    try {
      const clean = phone.replace(/\D/g, '');
      const formatted = clean.startsWith('0') ? `+2${clean}` : `+${clean}`;
      const auth = btoa(`${twilioSid}:${twilioToken}`);
      const params = new URLSearchParams({ To: formatted, From: twilioFrom, Body: message });
      const resp = await fetch(`https://api.twilio.com/2010-04-01/Accounts/${twilioSid}/Messages.json`, {
        method: 'POST',
        headers: {
          Authorization: `Basic ${auth}`,
          'Content-Type': 'application/x-www-form-urlencoded',
        },
        body: params.toString(),
      });
      return { sent: resp.ok, provider: 'twilio' };
    } catch (e) {
      console.error('Twilio error:', (e as Error).message);
    }
  }

  console.log(`[OTP/SMS simulated] to=${phone} otp=${otp ? '***' : ''}`);
  return { sent: false, provider: 'unconfigured' };
}

export async function sendRealEmail({ email, code }: { email: string; code: string }) {
  const resendKey = getEnv('RESEND_API_KEY');
  if (!resendKey) {
    console.warn(`[EMAIL skipped] RESEND_API_KEY not configured (to=${email})`);
    return { sent: false, provider: 'unconfigured' };
  }

  const subject = `${code} هو رمز التحقق الخاص بك · Hagzy`;
  const text = `حجزي · Hagzy

رمز تسجيل الدخول الخاص بك:
${code}

هذا الرمز لمرة واحدة فقط. يُرجى عدم مشاركته مع أي شخص.
إذا لم تكن قد طلبت هذا الرمز، يمكنك تجاهل هذه الرسالة بأمان.

Hagzy · حجزي
https://hagzy-booking.web.app`;

  const html = `<!DOCTYPE html>
<html lang="ar" dir="rtl">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>${subject}</title>
</head>
<body style="margin: 0; padding: 0; background-color: #f3f4f6; font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, 'Helvetica Neue', Arial, sans-serif; -webkit-font-smoothing: antialiased; color: #111827;">
  <table role="presentation" width="100%" border="0" cellspacing="0" cellpadding="0" style="background-color: #f3f4f6; padding: 48px 16px;">
    <tr>
      <td align="center">
        <table role="presentation" width="100%" border="0" cellspacing="0" cellpadding="0" style="max-width: 460px; background-color: #ffffff; border: 1px solid #e5e7eb; border-radius: 12px; overflow: hidden;">
          <tr>
            <td style="padding: 36px 36px 32px 36px;">
              <table role="presentation" width="100%" border="0" cellspacing="0" cellpadding="0" style="margin-bottom: 32px;">
                <tr>
                  <td>
                    <table role="presentation" border="0" cellspacing="0" cellpadding="0">
                      <tr>
                        <td style="vertical-align: middle; padding-left: 10px;">
                          <img src="https://hagzy-booking.web.app/favicon.png" width="30" height="30" alt="Hagzy" style="border-radius: 7px; display: block; border: 0;" />
                        </td>
                        <td style="vertical-align: middle;">
                          <span style="font-size: 18px; font-weight: 700; color: #111827; letter-spacing: -0.2px;">Hagzy</span>
                          <span style="font-size: 15px; font-weight: 400; color: #9ca3af; margin-right: 4px;">· حجزي</span>
                        </td>
                      </tr>
                    </table>
                  </td>
                </tr>
              </table>

              <h1 style="margin: 0 0 10px 0; font-size: 18px; font-weight: 600; color: #111827; line-height: 1.4;">
                رمز تسجيل الدخول
              </h1>
              
              <p style="margin: 0 0 4px 0; font-size: 14px; line-height: 1.6; color: #4b5563;">
                أدخل هذا الرمز لإتمام تسجيل الدخول إلى حسابك:
              </p>
              
              <p style="margin: 0 0 24px 0; font-size: 13px; line-height: 1.5; color: #9ca3af;" dir="ltr">
                Enter this code to complete signing in to your account:
              </p>

              <div style="background-color: #f9fafb; border: 1px solid #e5e7eb; border-radius: 8px; padding: 18px 16px; text-align: center; margin: 24px 0;">
                <span style="font-family: ui-monospace, 'SF Mono', Consolas, 'Liberation Mono', Menlo, monospace; font-size: 32px; font-weight: 700; letter-spacing: 8px; color: #047857; display: inline-block; text-indent: 8px;" dir="ltr">
                  ${code}
                </span>
              </div>

              <p style="margin: 20px 0 0 0; font-size: 13px; line-height: 1.6; color: #4b5563;">
                هذا الرمز يُستخدم لمرة واحدة فقط. يُرجى عدم مشاركته مع أي شخص.
              </p>
              
              <p style="margin: 6px 0 0 0; font-size: 12px; line-height: 1.5; color: #9ca3af;">
                إذا لم تكن قد طلبت هذا الرمز، يمكنك تجاهل هذه الرسالة بأمان.
              </p>
            </td>
          </tr>

          <tr>
            <td style="background-color: #fafafa; border-top: 1px solid #e5e7eb; padding: 18px 36px; text-align: center;">
              <p style="margin: 0 0 4px 0; font-size: 12px; color: #4b5563; font-weight: 500;">
                Hagzy · حجوزاتك بسهولة
              </p>
              <p style="margin: 0; font-size: 11px; color: #9ca3af;">
                © 2026 Hagzy. All rights reserved.
              </p>
            </td>
          </tr>
        </table>
      </td>
    </tr>
  </table>
</body>
</html>`;

  try {
    const res = await fetch('https://api.resend.com/emails', {
      method: 'POST',
      headers: {
        Authorization: `Bearer ${resendKey}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        from: getEnv('EMAIL_FROM', 'Hagzy <noreply@hagzy.shop>'),
        to: [email],
        subject,
        html,
        text,
      }),
    });
    return { sent: res.ok, provider: 'resend' };
  } catch (e) {
    console.error('Resend error:', (e as Error).message);
    return { sent: false, provider: 'resend_error' };
  }
}
