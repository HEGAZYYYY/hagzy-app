const fs = require('fs');
const path = require('path');
const { execSync } = require('child_process');

function getOtpEmailTemplate({ code, email }) {
  const brandDark = '#047857';
  const slate900 = '#111827';
  const slate600 = '#4b5563';
  const slate400 = '#9ca3af';
  const borderSubtle = '#e5e7eb';
  const bgSubtle = '#f9fafb';

  const subject = `${code} هو رمز التحقق الخاص بك · Hagzy`;

  const text = `حجزي · Hagzy

رمز تسجيل الدخول الخاص بك:
${code}

هذا الرمز لمرة واحدة فقط. يُرجى عدم مشاركته مع أي شخص.
إذا لم تكن قد طلبت هذا الرمز، يمكنك تجاهل هذه الرسالة بأمان.

Hagzy · حجزي
https://hagzy.shop`;

  const html = `<!DOCTYPE html>
<html lang="ar" dir="rtl">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>${subject}</title>
</head>
<body style="margin: 0; padding: 0; background-color: #f3f4f6; font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, 'Helvetica Neue', Arial, sans-serif; -webkit-font-smoothing: antialiased; color: ${slate900};">
  
  <table role="presentation" width="100%" border="0" cellspacing="0" cellpadding="0" style="background-color: #f3f4f6; padding: 48px 16px;">
    <tr>
      <td align="center">
        <!-- Main Card Container -->
        <table role="presentation" width="100%" border="0" cellspacing="0" cellpadding="0" style="max-width: 460px; background-color: #ffffff; border: 1px solid ${borderSubtle}; border-radius: 12px; overflow: hidden;">
          
          <tr>
            <td style="padding: 36px 36px 32px 36px;">
              
              <!-- Clean Minimal Header -->
              <table role="presentation" width="100%" border="0" cellspacing="0" cellpadding="0" style="margin-bottom: 32px;">
                <tr>
                  <td>
                    <table role="presentation" border="0" cellspacing="0" cellpadding="0">
                      <tr>
                        <td style="vertical-align: middle; padding-left: 10px;">
                          <!-- Real Hagzy Logo Icon -->
                          <img src="https://hagzy.shop/favicon.png" width="30" height="30" alt="Hagzy" style="border-radius: 7px; display: block; border: 0;" />
                        </td>
                        <td style="vertical-align: middle;">
                          <span style="font-size: 18px; font-weight: 700; color: ${slate900}; letter-spacing: -0.2px;">Hagzy</span>
                          <span style="font-size: 15px; font-weight: 400; color: ${slate400}; margin-right: 4px;">· حجزي</span>
                        </td>
                      </tr>
                    </table>
                  </td>
                </tr>
              </table>

              <!-- Main Copy -->
              <h1 style="margin: 0 0 10px 0; font-size: 18px; font-weight: 600; color: ${slate900}; line-height: 1.4;">
                رمز تسجيل الدخول
              </h1>
              
              <p style="margin: 0 0 4px 0; font-size: 14px; line-height: 1.6; color: ${slate600};">
                أدخل هذا الرمز لإتمام تسجيل الدخول إلى حسابك:
              </p>
              
              <p style="margin: 0 0 24px 0; font-size: 13px; line-height: 1.5; color: ${slate400};" dir="ltr">
                Enter this code to complete signing in to your account:
              </p>

              <!-- Clean Monospace OTP Box (No generic dashed borders or emoji pills) -->
              <div style="background-color: ${bgSubtle}; border: 1px solid ${borderSubtle}; border-radius: 8px; padding: 18px 16px; text-align: center; margin: 24px 0;">
                <span style="font-family: ui-monospace, 'SF Mono', Consolas, 'Liberation Mono', Menlo, monospace; font-size: 32px; font-weight: 700; letter-spacing: 8px; color: ${brandDark}; display: inline-block; text-indent: 8px;" dir="ltr">
                  ${code}
                </span>
              </div>

              <!-- Reassurance / Plain text notice -->
              <p style="margin: 20px 0 0 0; font-size: 13px; line-height: 1.6; color: ${slate600};">
                هذا الرمز يُستخدم لمرة واحدة فقط. يُرجى عدم مشاركته مع أي شخص.
              </p>
              
              <p style="margin: 6px 0 0 0; font-size: 12px; line-height: 1.5; color: ${slate400};">
                إذا لم تكن قد طلبت هذا الرمز، يمكنك تجاهل هذه الرسالة بأمان.
              </p>

            </td>
          </tr>

          <!-- Subtle Footer -->
          <tr>
            <td style="background-color: #fafafa; border-top: 1px solid ${borderSubtle}; padding: 18px 36px; text-align: center;">
              <p style="margin: 0 0 4px 0; font-size: 12px; color: ${slate600}; font-weight: 500;">
                Hagzy · حجوزاتك بسهولة
              </p>
              <p style="margin: 0; font-size: 11px; color: ${slate400};">
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

  return { subject, html, text };
}

module.exports = { getOtpEmailTemplate };

// Preview rendering
if (require.main === module) {
  const { html } = getOtpEmailTemplate({ code: '739482', email: 'user@example.com' });
  const previewPath = path.resolve(__dirname, 'preview_email.html');
  fs.writeFileSync(previewPath, html, 'utf8');
  console.log('Written clean email HTML to:', previewPath);

  const chromePath = 'C:\\Program Files\\Google\\Chrome\\Application\\chrome.exe';
  const outShot = path.resolve(__dirname, 'preview_email.png');
  execSync(`"${chromePath}" --headless=new --screenshot="${outShot}" --window-size=540,750 "file://${previewPath.replace(/\\/g, '/')}"`);
  console.log('Rendered preview image:', outShot);
}
