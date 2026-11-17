import { getEnv } from './db.ts';

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

  const subject = `رمز التحقق الخاص بك في منصة حجزي: ${code}`;
  const html = `
    <div style="font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif; max-width: 480px; margin: 20px auto; padding: 24px; border: 1px solid #e2e8f0; border-radius: 18px; background: #ffffff;">
      <h2 style="color: #059669; margin: 0 0 10px;">حجزي · Hagzy</h2>
      <p style="color: #334155; font-size: 15px; margin: 0 0 18px;">رمز التحقق لتسجيل الدخول إلى حسابك هو:</p>
      <div style="background: #f0fdf4; border: 1.5px solid #86efac; border-radius: 12px; padding: 16px; text-align: center; font-size: 32px; font-weight: 900; letter-spacing: 8px; color: #166534; font-family: monospace;">
        ${code}
      </div>
      <p style="color: #64748b; font-size: 12px; margin: 18px 0 0;">صلاحية هذا الرمز 5 دقائق فقط. لا تشارك هذا الرمز مع أي شخص.</p>
    </div>
  `;

  try {
    const res = await fetch('https://api.resend.com/emails', {
      method: 'POST',
      headers: {
        Authorization: `Bearer ${resendKey}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        from: getEnv('EMAIL_FROM', 'Hagzy <onboarding@resend.dev>'),
        to: [email],
        subject,
        html,
      }),
    });
    return { sent: res.ok, provider: 'resend' };
  } catch (e) {
    console.error('Resend error:', (e as Error).message);
    return { sent: false, provider: 'resend_error' };
  }
}
