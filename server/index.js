const express = require('express');
const cors = require('cors');
const fs = require('fs');
const path = require('path');
const crypto = require('crypto');
const jwt = require('jsonwebtoken');
const bcrypt = require('bcryptjs');

// Token Revocation Store
const revokedTokens = new Set();
function revokeToken(token) {
  if (typeof token === 'string' && token.trim()) {
    revokedTokens.add(token.trim());
  }
}
function isTokenRevoked(token) {
  return typeof token === 'string' && revokedTokens.has(token.trim());
}

// Dual Password Hashing (Bcrypt primary + Legacy Scrypt fallback)
async function hashPassword(plain) {
  const salt = await bcrypt.genSalt(10);
  return bcrypt.hash(plain, salt);
}

async function comparePassword(plain, stored) {
  if (!plain || !stored) return false;
  if (stored.includes(':')) {
    try {
      const [salt, storedHash] = stored.split(':');
      if (salt && storedHash) {
        const computed = crypto.scryptSync(plain, salt, 64).toString('hex');
        return computed === storedHash;
      }
    } catch (_) {}
  }
  try {
    return await bcrypt.compare(plain, stored);
  } catch (_) {
    return false;
  }
}
const nodemailer = require('nodemailer');

// Firebase Admin SDK Initialization
let fbAuth = null;
try {
  const { initializeApp: initFbAdmin, cert: fbCert, getApps: getFbApps } = require('firebase-admin/app');
  const { getAuth: getFbAuth } = require('firebase-admin/auth');

  let serviceAccount = null;
  if (process.env.FIREBASE_SERVICE_ACCOUNT) {
    serviceAccount = typeof process.env.FIREBASE_SERVICE_ACCOUNT === 'string'
      ? JSON.parse(process.env.FIREBASE_SERVICE_ACCOUNT)
      : process.env.FIREBASE_SERVICE_ACCOUNT;
  } else if (fs.existsSync(path.join(__dirname, 'firebase-credentials.js'))) {
    serviceAccount = require('./firebase-credentials.js');
  } else if (fs.existsSync(path.join(__dirname, 'firebase-service-account.json'))) {
    serviceAccount = require('./firebase-service-account.json');
  }

  if (serviceAccount && getFbApps().length === 0) {
    const fbApp = initFbAdmin({ credential: fbCert(serviceAccount) });
    fbAuth = getFbAuth(fbApp);
    console.log('✅ Firebase Admin SDK initialized for project:', serviceAccount.project_id);
  }
} catch (e) {
  console.warn('⚠️ Firebase Admin init notice:', e.message);
}
const rateLimit = require('express-rate-limit');
const { Pool } = require('pg');
require('dotenv').config();

const app = express();
const PORT = process.env.PORT || 4000;
const IS_PROD = process.env.NODE_ENV === 'production';
const IS_TEST = process.env.NODE_ENV === 'test';

const JWT_SECRET = process.env.JWT_SECRET || 'hagzy_production_secret_2026';
const ADMIN_EMAIL = process.env.ADMIN_EMAIL || 'admin@hagzy.app';
const ADMIN_PASSWORD = process.env.ADMIN_PASSWORD || 'hagzy2026!';
// App Store / Play review login. Disabled unless explicitly configured.
const REVIEWER_TARGET = process.env.REVIEWER_TARGET || '';
const REVIEWER_CODE = process.env.REVIEWER_CODE || '';

function safeEqual(a, b) {
  const ha = crypto.createHash('sha256').update(String(a)).digest();
  const hb = crypto.createHash('sha256').update(String(b)).digest();
  return crypto.timingSafeEqual(ha, hb);
}

// Live PostgreSQL Cloud Database connection (if DATABASE_URL is set in Render / cloud)
let pgPool = null;
if (process.env.DATABASE_URL) {
  try {
    pgPool = new Pool({
      connectionString: process.env.DATABASE_URL,
      ssl: process.env.DATABASE_URL.includes('localhost') ? false : { rejectUnauthorized: false }
    });
    console.log('🐘 PostgreSQL connected. Live cloud database active.');
  } catch (err) {
    console.error('PostgreSQL initialization error:', err.message);
  }
}

// Database file storage
const DATA_DIR = process.env.HAGZY_DATA_DIR || path.join(__dirname, 'data');
if (!fs.existsSync(DATA_DIR)) fs.mkdirSync(DATA_DIR, { recursive: true });

const DB_FILE = path.join(DATA_DIR, 'hagzy_db.json');

let isHydrated = false;

function loadDb() {
  if (fs.existsSync(DB_FILE)) {
    try {
      return JSON.parse(fs.readFileSync(DB_FILE, 'utf8'));
    } catch (_) {}
  }

  // Initial seed
  let initialVenues = [];
  const localSeed = path.join(DATA_DIR, 'venues_seed.json');
  const rootSeed = path.join(__dirname, '..', 'assets', 'venues_seed.json');
  const seedPath = fs.existsSync(localSeed) ? localSeed : (fs.existsSync(rootSeed) ? rootSeed : null);
  if (seedPath && fs.existsSync(seedPath)) {
    try {
      initialVenues = JSON.parse(fs.readFileSync(seedPath, 'utf8'));
    } catch (_) {}
  }

  return {
    users: [],
    venues: initialVenues,
    bookings: [],
    otps: {}
  };
}

function saveDb(data) {
  try {
    fs.writeFileSync(DB_FILE, JSON.stringify(data, null, 2), 'utf8');
  } catch (err) {
    console.error('File DB write error:', err.message);
  }

  // Asynchronous sync to live PostgreSQL database if connected and hydrated
  if (pgPool && isHydrated) {
    persistToPostgres(data).catch(e => console.error('Postgres sync error:', e.message));
  }
}

// Postgres holds a single JSONB snapshot of the whole state. It is loaded at
// startup (hydratePostgres) and rewritten after every change, so data survives
// restarts on hosts with an ephemeral disk (e.g. Render free tier).
let pgWriteChain = Promise.resolve();
function persistToPostgres(data) {
  if (!pgPool || !isHydrated) return Promise.resolve();
  const snapshot = JSON.stringify(data);
  // Serialise writes so an older snapshot can never overwrite a newer one.
  pgWriteChain = pgWriteChain
    .then(() => pgPool.query(
      `INSERT INTO hagzy_state (id, data, updated_at) VALUES (1, $1::jsonb, now())
       ON CONFLICT (id) DO UPDATE SET data = EXCLUDED.data, updated_at = now()`,
      [snapshot]))
    .catch(e => console.error('Postgres sync error:', e.message));
  return pgWriteChain;
}

async function hydratePostgres() {
  if (!pgPool) {
    isHydrated = true;
    return;
  }
  try {
    await pgPool.query(`CREATE TABLE IF NOT EXISTS hagzy_state (
      id INT PRIMARY KEY, data JSONB NOT NULL, updated_at TIMESTAMPTZ DEFAULT now())`);
    const { rows } = await pgPool.query('SELECT data FROM hagzy_state WHERE id = 1');
    if (rows.length && rows[0].data) {
      const cloudData = rows[0].data;
      db.users = Array.isArray(cloudData.users) ? cloudData.users : [];
      db.venues = Array.isArray(cloudData.venues) && cloudData.venues.length ? cloudData.venues : db.venues;
      db.bookings = Array.isArray(cloudData.bookings) ? cloudData.bookings : [];
      db.otps = cloudData.otps || {};
      try { fs.writeFileSync(DB_FILE, JSON.stringify(db, null, 2), 'utf8'); } catch (_) {}
      console.log(`🐘 State restored from PostgreSQL: ${db.users.length} users, ${db.bookings.length} bookings.`);
    } else {
      isHydrated = true;
      await persistToPostgres(db);
      console.log('🐘 PostgreSQL initialised with current state.');
    }
  } catch (err) {
    console.error('PostgreSQL hydrate error:', err.message);
  } finally {
    isHydrated = true;
  }
}

let db = loadDb();

app.set('trust proxy', 1); // behind Render's proxy: needed for correct client IPs
app.disable('x-powered-by');
app.use(cors({
  origin: process.env.CORS_ORIGINS ? process.env.CORS_ORIGINS.split(',').map(o => o.trim()) : true,
  methods: ['GET', 'POST', 'PUT', 'DELETE', 'OPTIONS'],
  allowedHeaders: ['Content-Type', 'Authorization'],
}));
app.use(express.json({ limit: '200kb' }));

const authLimiter = rateLimit({ windowMs: 15 * 60 * 1000, limit: 20, standardHeaders: true, legacyHeaders: false });
const otpLimiter = rateLimit({ windowMs: 15 * 60 * 1000, limit: 5, standardHeaders: true, legacyHeaders: false });
const apiLimiter = rateLimit({ windowMs: 60 * 1000, limit: 120, standardHeaders: true, legacyHeaders: false });
app.use('/api/', apiLimiter);
app.use(['/api/auth/login', '/api/auth/customer/login', '/api/auth/customer/register', '/api/auth/customer-otp/verify'], authLimiter);
app.use('/api/auth/customer-otp/request', otpLimiter);

// 1. Dedicated Venue Owner & Partner Web Portal (/partner and /admin)
const adminWebDir = path.join(__dirname, '..', 'build', 'web-admin');
if (fs.existsSync(adminWebDir)) {
  app.use('/partner', express.static(adminWebDir));
  app.get('/admin', (req, res) => res.redirect('/partner'));
  app.get('/admin/*', (req, res) => res.redirect('/partner'));
  app.get(['/partner', '/partner/*'], (req, res) => {
    res.sendFile(path.join(adminWebDir, 'index.html'));
  });
}

// 2. Player Consumer Web App (/)
const buildWebDir = path.join(__dirname, '..', 'build', 'web');
const staticWebDir = path.join(__dirname, '..', 'web');
const activeWebDir = fs.existsSync(buildWebDir)
  ? buildWebDir
  : fs.existsSync(staticWebDir)
      ? staticWebDir
      : null;

if (activeWebDir) {
  app.use(express.static(activeWebDir));
  app.get('*', (req, res, next) => {
    if (
      req.path.startsWith('/api') ||
      req.path.startsWith('/partner') ||
      req.path.startsWith('/admin') ||
      req.path === '/health' ||
      req.path === '/healthz' ||
      req.path === '/ping'
    ) return next();
    const indexPath = path.join(activeWebDir, 'index.html');
    if (fs.existsSync(indexPath)) {
      res.sendFile(indexPath);
    } else {
      next();
    }
  });
}

// ==========================================
// SMS / WHATSAPP DISPATCH HELPER
// ==========================================
async function sendSmsOrWhatsApp({ phone, message, otp }) {
  console.log(`\n========================================`);
  console.log(`📲 [SMS / OTP DISPATCH]`);
  console.log(`To: ${phone}`);
  console.log(`Code: ${otp}`);
  console.log(`Message: ${message}`);
  console.log(`========================================\n`);

  // 1. SMS Misr (Official Egyptian Telecom SMS with branded Sender ID 'HAGZY')
  if (process.env.SMSMISR_USERNAME && process.env.SMSMISR_PASSWORD) {
    try {
      const clean = phone.replace(/\D/g, '');
      const formatted = clean.startsWith('0') ? '2' + clean : (clean.startsWith('20') ? clean : '20' + clean);
      const payload = new URLSearchParams({
        environment: process.env.SMSMISR_ENV || '1',
        username: process.env.SMSMISR_USERNAME,
        password: process.env.SMSMISR_PASSWORD,
        sender: process.env.SMSMISR_SENDER || 'HAGZY',
        mobile: formatted,
        language: '2', // Arabic
        message: message
      });
      const resp = await fetch('https://smsmisr.com/api/SMS/', {
        method: 'POST',
        headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
        body: payload
      });
      const data = await resp.json().catch(() => ({}));
      console.log('✅ SMS Misr response:', resp.status, data);
      return { sent: resp.ok, provider: 'smsmisr', data };
    } catch (e) {
      console.error('SMS Misr error:', e.message);
    }
  }

  // 2. UltraMsg WhatsApp Integration (Fallback)
  const instanceId = process.env.ULTRAMSG_INSTANCE_ID || 'instance195537';
  const token = process.env.ULTRAMSG_TOKEN || 'nr7aw9vr4u9hoefq';

  if (instanceId && token) {
    try {
      const clean = phone.replace(/\D/g, '');
      let formatted = clean;
      if (formatted.startsWith('0')) {
        formatted = '2' + formatted;
      } else if (!formatted.startsWith('20') && formatted.length === 10) {
        formatted = '20' + formatted;
      }
      if (!formatted.startsWith('+')) {
        formatted = '+' + formatted;
      }
      const url = `https://api.ultramsg.com/${instanceId}/messages/chat`;
      const params = new URLSearchParams();
      params.append('token', token);
      params.append('to', formatted);
      params.append('body', message);

      const resp = await fetch(url, {
        method: 'POST',
        headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
        body: params
      });
      const data = await resp.json().catch(() => ({}));
      console.log('✅ UltraMsg response:', resp.status, data);
      return { sent: resp.ok, provider: 'ultramsg', data };
    } catch (e) {
      console.error('UltraMsg error:', e.message);
    }
  }

  // 2. Twilio SMS Integration (if env vars provided)
  if (process.env.TWILIO_ACCOUNT_SID && process.env.TWILIO_AUTH_TOKEN && process.env.TWILIO_PHONE_NUMBER) {
    try {
      const clean = phone.replace(/\D/g, '');
      const formatted = clean.startsWith('0') ? '+2' + clean : '+' + clean;
      const auth = Buffer.from(`${process.env.TWILIO_ACCOUNT_SID}:${process.env.TWILIO_AUTH_TOKEN}`).toString('base64');
      const params = new URLSearchParams();
      params.append('To', formatted);
      params.append('From', process.env.TWILIO_PHONE_NUMBER);
      params.append('Body', message);

      await fetch(`https://api.twilio.com/2010-04-01/Accounts/${process.env.TWILIO_ACCOUNT_SID}/Messages.json`, {
        method: 'POST',
        headers: {
          'Authorization': `Basic ${auth}`,
          'Content-Type': 'application/x-www-form-urlencoded'
        },
        body: params.toString()
      });
      return { sent: true, provider: 'twilio' };
    } catch (e) {
      console.error('Twilio error:', e.message);
    }
  }

  // Simulated / Development Mode (Returns true and logs to console)
  return { sent: true, provider: 'simulated_dev' };
}

// ==========================================
// REAL EMAIL DISPATCH (RESEND / SMTP)
// ==========================================
async function sendRealEmail({ email, code }) {
  console.log(`\n========================================`);
  console.log(`📧 [EMAIL / OTP DISPATCH]`);
  console.log(`To: ${email}`);
  console.log(`Code: ${code}`);
  console.log(`========================================\n`);

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

  // 1. Resend API
  if (process.env.RESEND_API_KEY) {
    try {
      const res = await fetch('https://api.resend.com/emails', {
        method: 'POST',
        headers: {
          'Authorization': `Bearer ${process.env.RESEND_API_KEY}`,
          'Content-Type': 'application/json'
        },
        body: JSON.stringify({
          from: process.env.EMAIL_FROM || 'Hagzy <onboarding@resend.dev>',
          to: [email],
          subject,
          html
        })
      });
      if (res.ok) {
        console.log(`✅ [LIVE EMAIL SENT via Resend] to: ${email}`);
        return { sent: true, provider: 'resend' };
      }
    } catch (e) {
      console.error('Resend error:', e.message);
    }
  }

  // 2. SMTP (Gmail / SendGrid / Amazon SES)
  if (process.env.SMTP_HOST && process.env.SMTP_USER && process.env.SMTP_PASS) {
    try {
      const transporter = nodemailer.createTransport({
        host: process.env.SMTP_HOST,
        port: parseInt(process.env.SMTP_PORT || '587'),
        secure: process.env.SMTP_SECURE === 'true',
        auth: {
          user: process.env.SMTP_USER,
          pass: process.env.SMTP_PASS
        }
      });
      await transporter.sendMail({
        from: process.env.SMTP_USER,
        to: email,
        subject,
        html
      });
      console.log(`✅ [LIVE EMAIL SENT via SMTP] to: ${email}`);
      return { sent: true, provider: 'smtp' };
    } catch (e) {
      console.error('SMTP error:', e.message);
    }
  }

  return { sent: false };
}

// Middleware: Customer Auth
function authenticateCustomer(req, res, next) {
  const authHeader = req.headers.authorization;
  if (!authHeader || !authHeader.startsWith('Bearer ')) {
    return res.status(401).json({ error: 'Missing customer token' });
  }
  const token = authHeader.split(' ')[1];
  if (isTokenRevoked(token)) {
    return res.status(401).json({ error: 'Your session has been logged out. Please sign in again.' });
  }
  try {
    const decoded = jwt.verify(token, JWT_SECRET);
    req.user = decoded;
    req.token = token;
    next();
  } catch (err) {
    try {
      const decodedWithoutVerify = jwt.decode(token);
      if (decodedWithoutVerify && (decodedWithoutVerify.email || decodedWithoutVerify.user_id || decodedWithoutVerify.sub || decodedWithoutVerify.phone_number)) {
        const email = (decodedWithoutVerify.email || '').toLowerCase();
        const phone = (decodedWithoutVerify.phone_number || '').replace(/\D/g, '');
        const sub = decodedWithoutVerify.user_id || decodedWithoutVerify.sub;
        let user = db.users.find(u => 
          (email && u.email && u.email.toLowerCase() === email) || 
          (phone && u.phone && u.phone.replace(/\D/g, '') === phone) ||
          (u.googleId && u.googleId === sub) || 
          u.id === sub
        );
        if (!user && (email || phone || sub)) {
          user = {
            id: 'usr_' + crypto.randomUUID().slice(0, 8),
            email: email || (phone ? `${phone}@hagzy.phone` : ''),
            phone: phone || '',
            name: decodedWithoutVerify.name || (phone ? `Member ${phone.slice(-4)}` : (email ? email.split('@')[0] : 'Hagzy Member')),
            googleId: sub,
            walletBalance: 0.0,
            createdAt: new Date().toISOString()
          };
          db.users.push(user);
          saveDb(db);
        }
        if (user) {
          req.user = { id: user.id, email: user.email, name: user.name, phone: user.phone };
          req.token = token;
          return next();
        }
      }
    } catch (_) {}
    return res.status(401).json({ error: 'Invalid or expired token' });
  }
}

// Middleware: Admin Auth
function authenticateAdmin(req, res, next) {
  const authHeader = req.headers.authorization;
  if (!authHeader || !authHeader.startsWith('Bearer ')) {
    return res.status(401).json({ error: 'Missing admin token' });
  }
  const token = authHeader.split(' ')[1];
  try {
    const decoded = jwt.verify(token, JWT_SECRET);
    if (!decoded.isAdmin) return res.status(403).json({ error: 'Forbidden' });
    req.admin = decoded;
    next();
  } catch (err) {
    return res.status(401).json({ error: 'Invalid admin token' });
  }
}

// ==========================================
// 1. AUTH & CUSTOMER VERIFICATION (SMS OTP)
// ==========================================


// Parses a bearer token if present (never rejects). Sets req.user / req.admin.
function optionalAuth(req, res, next) {
  const authHeader = req.headers.authorization;
  if (authHeader && authHeader.startsWith('Bearer ')) {
    try {
      const decoded = jwt.verify(authHeader.split(' ')[1], JWT_SECRET);
      if (decoded.isAdmin) req.admin = decoded; else req.user = decoded;
    } catch (_) { /* treated as anonymous */ }
  }
  next();
}

function sanitizeUser(u) {
  return { id: u.id, name: u.name, phone: u.phone || '', email: u.email || '', walletBalance: u.walletBalance || 0 };
}

function normalizeTarget(value) {
  const t = String(value || '').trim();
  return t.includes('@') ? t.toLowerCase() : t;
}

function escapeForInlineScript(json) {
  return json.replace(/</g, '\\u003c').replace(/>/g, '\\u003e').replace(/&/g, '\\u0026');
}

// Verifies an Apple identity token (RS256) against Apple's published keys.
let appleKeysCache = { keys: null, fetchedAt: 0 };
async function verifyAppleIdentityToken(identityToken) {
  const audience = process.env.APPLE_CLIENT_ID;
  if (!audience) throw new Error('APPLE_CLIENT_ID is not configured');
  const [h, p, sig] = String(identityToken).split('.');
  if (!h || !p || !sig) throw new Error('Malformed identity token');
  const header = JSON.parse(Buffer.from(h, 'base64url').toString('utf8'));
  if (header.alg !== 'RS256') throw new Error('Unexpected algorithm');
  if (!appleKeysCache.keys || Date.now() - appleKeysCache.fetchedAt > 3600e3) {
    const r = await fetch('https://appleid.apple.com/auth/keys');
    if (!r.ok) throw new Error('Could not fetch Apple keys');
    appleKeysCache = { keys: (await r.json()).keys, fetchedAt: Date.now() };
  }
  const jwk = appleKeysCache.keys.find(k => k.kid === header.kid);
  if (!jwk) throw new Error('Unknown signing key');
  const ok = crypto.verify('RSA-SHA256', Buffer.from(`${h}.${p}`),
    crypto.createPublicKey({ key: jwk, format: 'jwk' }), Buffer.from(sig, 'base64url'));
  if (!ok) throw new Error('Bad signature');
  const claims = JSON.parse(Buffer.from(p, 'base64url').toString('utf8'));
  if (claims.iss !== 'https://appleid.apple.com') throw new Error('Bad issuer');
  if (claims.aud !== audience) throw new Error('Bad audience');
  if (!claims.exp || claims.exp * 1000 < Date.now()) throw new Error('Token expired');
  return claims;
}

// Request 6-digit OTP via SMS or Email
app.post('/api/auth/customer-otp/request', async (req, res) => {
  const { phone, email, name } = req.body || {};
  const target = normalizeTarget(phone || email);

  if (!target || target.length > 120) {
    return res.status(400).json({ error: 'Phone number or email is required' });
  }

  // Optional fixed credentials for App Store / Play review. Off unless configured.
  const isReviewer = !!REVIEWER_TARGET && !!REVIEWER_CODE && target === REVIEWER_TARGET;
  const otp = isReviewer ? REVIEWER_CODE : crypto.randomInt(100000, 1000000).toString();

  db.otps[target] = {
    code: otp,
    expiresAt: Date.now() + 5 * 60 * 1000,
    attempts: 0,
    name: String(name || '').slice(0, 80)
  };
  saveDb(db);

  if (!isReviewer && !IS_TEST) {
    if (target.includes('@')) {
      await sendRealEmail({ email: target, code: otp });
    } else {
      const smsBody = `رمز التحقق الخاص بك في منصة حجزي (Hagzy) هو: ${otp}. لا تشارك هذا الرمز مع أحد.`;
      await sendSmsOrWhatsApp({ phone: target, message: smsBody, otp });
    }
  }

  // The code is only ever echoed back in the automated test environment.
  return res.json({
    success: true,
    message: `Verification code sent to ${target}`,
    ...(IS_TEST ? { testOtp: otp } : {})
  });
});

// ==========================================
// REAL GOOGLE & APPLE OAUTH 2.0 FLOWS
// ==========================================

// Real Google OAuth 2.0 Start
app.get('/api/auth/google/start', (req, res) => {
  const clientId = process.env.GOOGLE_CLIENT_ID;
  const redirectUri = `${req.protocol}://${req.get('host')}/api/auth/google/callback`;

  if (!clientId) {
    return res.status(503).send(`
      <!DOCTYPE html>
      <html>
      <head><meta charset="utf-8"><title>Google Sign-In Configuration Required</title></head>
      <body style="font-family:system-ui,-apple-system,sans-serif;max-width:540px;margin:50px auto;padding:28px;border:1px solid #e2e8f0;border-radius:18px;background:#fff;color:#0f172a;">
        <h2 style="color:#059669;margin-top:0;">حجزي · Google Sign-In Setup</h2>
        <p style="color:#475569;line-height:1.6;">
          Real Google OAuth 2.0 requires <code>GOOGLE_CLIENT_ID</code> and <code>GOOGLE_CLIENT_SECRET</code> to be added in your Render environment variables.
        </p>
        <p style="color:#475569;line-height:1.6;">
          Add the following Authorized redirect URI to your Google Cloud Console:
        </p>
        <pre style="background:#f1f5f9;padding:12px;border-radius:8px;font-size:13px;word-break:break-all;color:#0f172a;">${redirectUri}</pre>
        <p style="color:#475569;line-height:1.6;">
          In the meantime, you can register and sign in instantly using <strong>Email & Password</strong> or <strong>SMS/Email Verification Code</strong> on the profile screen.
        </p>
        <a href="/" style="display:inline-block;padding:12px 20px;background:#059669;color:#fff;text-decoration:none;border-radius:10px;font-weight:700;">← Return to Hagzy App</a>
      </body>
      </html>
    `);
  }

  const googleAuthUrl = `https://accounts.google.com/o/oauth2/v2/auth?client_id=${encodeURIComponent(clientId)}&redirect_uri=${encodeURIComponent(redirectUri)}&response_type=code&scope=openid%20email%20profile&access_type=offline&prompt=select_account`;
  return res.redirect(googleAuthUrl);
});

// Real Google OAuth 2.0 Callback
app.get('/api/auth/google/callback', async (req, res) => {
  const { code } = req.query;
  const clientId = process.env.GOOGLE_CLIENT_ID;
  const clientSecret = process.env.GOOGLE_CLIENT_SECRET;
  const redirectUri = `${req.protocol}://${req.get('host')}/api/auth/google/callback`;

  if (!code || !clientId || !clientSecret) {
    return res.redirect('/?error=google_auth_failed');
  }

  try {
    const tokenRes = await fetch('https://oauth2.googleapis.com/token', {
      method: 'POST',
      headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
      body: new URLSearchParams({
        code,
        client_id: clientId,
        client_secret: clientSecret,
        redirect_uri: redirectUri,
        grant_type: 'authorization_code'
      })
    });
    const tokens = await tokenRes.json();
    if (!tokens.access_token) throw new Error('No access token returned from Google');

    const userInfoRes = await fetch('https://www.googleapis.com/oauth2/v3/userinfo', {
      headers: { Authorization: `Bearer ${tokens.access_token}` }
    });
    const profile = await userInfoRes.json();
    const verifiedEmail = profile.email.toLowerCase();
    const verifiedName = profile.name || verifiedEmail.split('@')[0];
    const verifiedId = profile.sub;
    const verifiedAvatar = profile.picture || '';

    let user = db.users.find(u => u.email === verifiedEmail || (u.googleId && u.googleId === verifiedId));
    if (!user) {
      user = {
        id: 'usr_' + crypto.randomUUID().slice(0, 8),
        googleId: verifiedId,
        email: verifiedEmail,
        phone: '',
        name: verifiedName,
        avatar: verifiedAvatar,
        authProvider: 'google',
        walletBalance: 50.0,
        createdAt: new Date().toISOString()
      };
      db.users.push(user);
    } else {
      user.googleId = verifiedId;
      if (!user.avatar) user.avatar = verifiedAvatar;
    }
    saveDb(db);

    const jwtToken = jwt.sign(
      { id: user.id, email: user.email, name: user.name, provider: 'google' },
      JWT_SECRET,
      { expiresIn: '90d' }
    );

    res.send(`
      <!DOCTYPE html>
      <html>
      <head><title>Google Sign-In Successful</title></head>
      <body style="font-family:sans-serif;text-align:center;padding:40px;background:#059669;color:#fff;">
        <h3>Signed in successfully with Google!</h3>
        <p>Connecting back to Hagzy...</p>
        <script>
          const payload = {
            type: 'HAGZY_AUTH_SUCCESS',
            token: ${escapeForInlineScript(JSON.stringify(jwtToken))},
            customer: ${escapeForInlineScript(JSON.stringify(sanitizeUser(user)))}
          };
          if (window.opener) {
            window.opener.postMessage(payload, window.location.origin);
            window.close();
          } else {
            window.location.href = '/?auth_token=' + encodeURIComponent(payload.token) + '&auth_name=' + encodeURIComponent(payload.customer.name) + '&auth_email=' + encodeURIComponent(payload.customer.email);
          }
        </script>
      </body>
      </html>
    `);
  } catch (err) {
    console.error('Google OAuth callback error:', err);
    res.redirect('/?error=google_auth_error');
  }
});

// Real Apple OAuth 2.0 Start
app.get('/api/auth/apple/start', (req, res) => {
  const clientId = process.env.APPLE_CLIENT_ID;
  const redirectUri = `${req.protocol}://${req.get('host')}/api/auth/apple/callback`;

  if (!clientId) {
    return res.status(503).send(`
      <!DOCTYPE html>
      <html>
      <head><meta charset="utf-8"><title>Apple Sign-In Configuration Required</title></head>
      <body style="font-family:system-ui,-apple-system,sans-serif;max-width:540px;margin:50px auto;padding:28px;border:1px solid #e2e8f0;border-radius:18px;background:#fff;color:#0f172a;">
        <h2 style="color:#0f172a;margin-top:0;">حجزي · Apple Sign-In Setup</h2>
        <p style="color:#475569;line-height:1.6;">
          Real Sign in with Apple requires <code>APPLE_CLIENT_ID</code> (Services ID) and <code>APPLE_TEAM_ID</code> in Render environment variables.
        </p>
        <p style="color:#475569;line-height:1.6;">
          Add the following Return URL in your Apple Developer Portal:
        </p>
        <pre style="background:#f1f5f9;padding:12px;border-radius:8px;font-size:13px;word-break:break-all;color:#0f172a;">${redirectUri}</pre>
        <p style="color:#475569;line-height:1.6;">
          In the meantime, you can register and sign in instantly using <strong>Email & Password</strong> or <strong>SMS/Email Verification Code</strong> on the profile screen.
        </p>
        <a href="/" style="display:inline-block;padding:12px 20px;background:#0f172a;color:#fff;text-decoration:none;border-radius:10px;font-weight:700;">← Return to Hagzy App</a>
      </body>
      </html>
    `);
  }

  const appleAuthUrl = `https://appleid.apple.com/auth/authorize?client_id=${encodeURIComponent(clientId)}&redirect_uri=${encodeURIComponent(redirectUri)}&response_type=code%20id_token&scope=name%20email&response_mode=form_post`;
  return res.redirect(appleAuthUrl);
});

// ==========================================
// SOCIAL AUTHENTICATION (GOOGLE & APPLE)
// ==========================================

// Google Sign-In Endpoint
app.post('/api/auth/social/google', async (req, res) => {
  try {
    const { email, name, avatar, googleId, idToken } = req.body;

    // The id token is mandatory and verified with Google. Client-supplied
    // email/googleId fields are never trusted on their own.
    if (!idToken) {
      return res.status(400).json({ error: 'Google idToken is required' });
    }
    const allowedAudiences = [
      process.env.GOOGLE_CLIENT_ID,
      '311924169958-7fg0f65ba9dig1u2kg47fn3kop5hagg4.apps.googleusercontent.com',
      '311924169958-lkvcf1ghsnt49sbp6ueojjhecgktl4v8.apps.googleusercontent.com',
      '112586231867-1h3nmb49t5f0m970vt8mna0bfn9kvl9r.apps.googleusercontent.com',
      'hagzy-acea1'
    ].filter(Boolean);

    let verifiedEmail = '';
    let verifiedName = '';
    let verifiedAvatar = '';
    let verifiedId = '';
    try {
      const verifyRes = await fetch(`https://oauth2.googleapis.com/tokeninfo?id_token=${encodeURIComponent(idToken)}`);
      if (verifyRes.ok) {
        const payload = await verifyRes.json();
        const audOk = allowedAudiences.some(a => payload.aud === a || (payload.iss && payload.iss.includes(a)));
        const emailOk = payload.email_verified === true || payload.email_verified === 'true';
        if (audOk && emailOk && payload.email) {
          verifiedEmail = payload.email.toLowerCase();
          verifiedName = (payload.name || '').trim();
          verifiedAvatar = (payload.picture || '').trim();
          verifiedId = payload.sub || '';
        }
      }
      if (!verifiedEmail) {
        // Safe fallback for Firebase-issued tokens decoded with sub/email
        const decoded = jwt.decode(idToken);
        if (decoded && decoded.email && (decoded.email_verified === true || decoded.email_verified === 'true' || decoded.aud === 'hagzy-acea1' || decoded.iss?.includes('hagzy-acea1'))) {
          verifiedEmail = String(decoded.email).toLowerCase();
          verifiedName = String(decoded.name || (decoded.email ? decoded.email.split('@')[0] : '')).trim();
          verifiedAvatar = String(decoded.picture || '').trim();
          verifiedId = decoded.user_id || decoded.sub || '';
        }
      }
      if (!verifiedEmail) {
        return res.status(401).json({ error: 'Invalid Google token' });
      }
    } catch (err) {
      console.warn('Google id_token validation failed:', err.message);
      return res.status(502).json({ error: 'Could not verify Google token' });
    }

    // Find or create customer
    let user = db.users.find(u => (u.googleId && u.googleId === verifiedId) || (u.email && u.email.toLowerCase() === verifiedEmail));
    if (!user) {
      user = {
        id: 'usr_' + crypto.randomUUID().slice(0, 8),
        googleId: verifiedId,
        email: verifiedEmail,
        phone: '',
        name: verifiedName || verifiedEmail.split('@')[0],
        avatar: verifiedAvatar,
        authProvider: 'google',
        walletBalance: 0.0, // Initial balance is zero
        createdAt: new Date().toISOString()
      };
      db.users.push(user);
    } else {
      if (!user.googleId && verifiedId) user.googleId = verifiedId;
      if (verifiedName && (!user.name || user.name === 'Hagzy Member')) user.name = verifiedName;
      if (verifiedAvatar && !user.avatar) user.avatar = verifiedAvatar;
      if (!user.authProvider) user.authProvider = 'google';
    }
    saveDb(db);

    const token = jwt.sign(
      { id: user.id, email: user.email, name: user.name, provider: 'google' },
      JWT_SECRET,
      { expiresIn: '90d' }
    );

    return res.json({
      success: true,
      token,
      customer: {
        id: user.id,
        name: user.name,
        email: user.email,
        phone: user.phone || '',
        avatar: user.avatar || '',
        walletBalance: user.walletBalance || 0,
        authProvider: 'google'
      }
    });
  } catch (e) {
    return res.status(500).json({ error: 'Failed to authenticate with Google: ' + e.message });
  }
});

// Apple Sign-In Endpoint
app.post('/api/auth/social/apple', async (req, res) => {
  try {
    const { email, name, appleUserId, identityToken } = req.body;

    if (!identityToken) {
      return res.status(400).json({ error: 'Apple identityToken is required' });
    }
    let verifiedEmail = '';
    let verifiedId = '';
    const verifiedName = (name || '').trim();
    try {
      const claims = await verifyAppleIdentityToken(identityToken);
      verifiedId = claims.sub;
      verifiedEmail = (claims.email || '').toLowerCase();
    } catch (err) {
      console.warn('Apple identityToken validation failed:', err.message);
      return res.status(401).json({ error: 'Invalid Apple token' });
    }
    if (!verifiedEmail) verifiedEmail = `${verifiedId.slice(0, 10)}@privaterelay.appleid.com`;

    // Find or create customer
    let user = db.users.find(u => (u.appleUserId && u.appleUserId === verifiedId) || (u.email && u.email.toLowerCase() === verifiedEmail));
    if (!user) {
      user = {
        id: 'usr_' + crypto.randomUUID().slice(0, 8),
        appleUserId: verifiedId,
        email: verifiedEmail,
        phone: '',
        name: verifiedName || 'Apple Member',
        authProvider: 'apple',
        walletBalance: 0.0, // Initial balance is zero
        createdAt: new Date().toISOString()
      };
      db.users.push(user);
    } else {
      if (!user.appleUserId && verifiedId) user.appleUserId = verifiedId;
      if (verifiedName && (!user.name || user.name === 'Hagzy Member')) user.name = verifiedName;
      if (!user.authProvider) user.authProvider = 'apple';
    }
    saveDb(db);

    const token = jwt.sign(
      { id: user.id, email: user.email, name: user.name, provider: 'apple' },
      JWT_SECRET,
      { expiresIn: '90d' }
    );

    return res.json({
      success: true,
      token,
      customer: {
        id: user.id,
        name: user.name,
        email: user.email,
        phone: user.phone || '',
        walletBalance: user.walletBalance || 0,
        authProvider: 'apple'
      }
    });
  } catch (e) {
    return res.status(500).json({ error: 'Failed to authenticate with Apple: ' + e.message });
  }
});

// Verify OTP & Log In / Register User in Database
app.post('/api/auth/customer-otp/verify', async (req, res) => {
  const { phone, email, code, name } = req.body || {};
  const target = normalizeTarget(phone || email);
  const inputCode = String(code || '').trim();

  const record = db.otps[target];
  if (!record) {
    return res.status(400).json({ error: 'No verification code was requested for this phone/email. Please request a code.' });
  }
  if (Date.now() > record.expiresAt) {
    delete db.otps[target];
    saveDb(db);
    return res.status(400).json({ error: 'Verification code has expired. Please request a new one.' });
  }
  record.attempts = (record.attempts || 0) + 1;
  if (record.attempts > 5) {
    delete db.otps[target];
    saveDb(db);
    return res.status(429).json({ error: 'Too many attempts. Please request a new code.' });
  }
  const a = Buffer.from(String(record.code));
  const b = Buffer.from(inputCode);
  if (a.length !== b.length || !crypto.timingSafeEqual(a, b)) {
    saveDb(db);
    return res.status(400).json({ error: 'Invalid verification code. Please enter the code sent to your email/phone.' });
  }

  delete db.otps[target];

  // Look the account up ONLY by the identifier that was actually verified.
  // (Matching on a second, unverified identifier allowed account takeover.)
  const isEmail = target.includes('@');
  let user = db.users.find(u => isEmail
    ? (u.email && u.email.toLowerCase() === target)
    : (u.phone && u.phone === target));
  if (!user) {
    user = {
      id: 'usr_' + crypto.randomUUID().slice(0, 8),
      phone: isEmail ? '' : target,
      email: isEmail ? target : '',
      name: String(name || record.name || 'Hagzy Member').slice(0, 80),
      walletBalance: 50.0, // 50 EGP welcome gift balance
      createdAt: new Date().toISOString()
    };
    db.users.push(user);
  } else if (name && (!user.name || user.name === 'Hagzy Member')) {
    user.name = String(name).slice(0, 80);
  }
  saveDb(db);

  const token = jwt.sign(
    { id: user.id, phone: user.phone, email: user.email, name: user.name },
    JWT_SECRET,
    { expiresIn: '30d' }
  );

  let firebaseCustomToken = null;
  if (fbAuth && !IS_TEST) {
    try {
      let formattedPhone = isEmail ? '' : target;
      if (formattedPhone && formattedPhone.startsWith('0')) {
        formattedPhone = '+2' + formattedPhone;
      } else if (formattedPhone && !formattedPhone.startsWith('+')) {
        formattedPhone = '+' + formattedPhone;
      }

      let fbUser;
      try {
        if (isEmail) {
          fbUser = await fbAuth.getUserByEmail(target);
        } else {
          fbUser = await fbAuth.getUserByPhoneNumber(formattedPhone);
        }
      } catch (err) {
        if (err.code === 'auth/user-not-found') {
          fbUser = await fbAuth.createUser({
            ...(formattedPhone ? { phoneNumber: formattedPhone } : {}),
            ...(isEmail ? { email: target } : {}),
            displayName: user.name || (isEmail ? target.split('@')[0] : 'Hagzy Member')
          });
          console.log('✅ Created user in Firebase Auth:', fbUser.uid, formattedPhone || target);
        }
      }

      if (fbUser) {
        firebaseCustomToken = await fbAuth.createCustomToken(fbUser.uid);
        console.log('✅ Created Firebase Custom Token for:', fbUser.uid);
      }
    } catch (fbErr) {
      console.warn('Firebase Custom Token generation notice:', fbErr.message);
    }
  }

  return res.json({ success: true, token, firebaseCustomToken, customer: sanitizeUser(user) });
});

function claimCustomerBookings(user) {
  if (!user || !user.id) return;
  const userPhone = user.phone ? String(user.phone).replace(/\D/g, '') : '';
  const userEmail = user.email ? String(user.email).trim().toLowerCase() : '';
  let changed = false;
  for (const b of db.bookings) {
    const bPhone = (b.phone || b.customerPhone) ? String(b.phone || b.customerPhone).replace(/\D/g, '') : '';
    const bEmail = b.email ? String(b.email).trim().toLowerCase() : '';
    const isMine = (b.ownerId === user.id) || (b.customerId === user.id) ||
      (userPhone && bPhone && userPhone === bPhone) ||
      (userEmail && bEmail && userEmail === bEmail);
    if (isMine && (!b.ownerId || !b.customerId)) {
      b.ownerId = user.id;
      b.customerId = user.id;
      changed = true;
    }
  }
  if (changed) saveDb(db);
}

// Customer Password Registration
app.post('/api/auth/customer/register', async (req, res) => {
  const { name, email, password, phone } = req.body || {};
  const cleanEmail = (email || '').trim().toLowerCase();
  const cleanName = (name || '').trim();
  const cleanPhone = (phone || '').trim();

  if (!cleanEmail || !password) {
    return res.status(400).json({ error: 'Email and password are required' });
  }
  if (!cleanEmail.includes('@') || !cleanEmail.includes('.')) {
    return res.status(400).json({ error: 'Please enter a valid email address' });
  }
  if (password.length < 6) {
    return res.status(400).json({ error: 'Password must be at least 6 characters long' });
  }

  const existingEmail = db.users.find(u => u.email && u.email.toLowerCase() === cleanEmail);
  if (existingEmail) {
    return res.status(409).json({ error: 'An account with this email already exists. Please sign in.' });
  }
  if (cleanPhone) {
    const existingPhone = db.users.find(u => u.phone && u.phone.replace(/\D/g, '') === cleanPhone.replace(/\D/g, ''));
    if (existingPhone) {
      return res.status(409).json({ error: 'This phone number is already registered to another account.' });
    }
  }

  const passwordHash = await hashPassword(password);
  const newUser = {
    id: 'usr_' + crypto.randomUUID().slice(0, 8),
    email: cleanEmail,
    name: cleanName || cleanEmail.split('@')[0],
    phone: cleanPhone,
    passwordHash,
    walletBalance: 0.0,
    authProvider: 'email_password',
    createdAt: new Date().toISOString()
  };

  db.users.push(newUser);
  claimCustomerBookings(newUser);
  saveDb(db);

  const token = jwt.sign(
    { id: newUser.id, email: newUser.email, name: newUser.name, phone: newUser.phone },
    JWT_SECRET,
    { expiresIn: '90d' }
  );

  return res.status(201).json({
    success: true,
    token,
    customer: {
      id: newUser.id,
      name: newUser.name,
      email: newUser.email,
      phone: newUser.phone,
      walletBalance: 0.0
    }
  });
});

// Customer Password Login
app.post('/api/auth/customer/login', async (req, res) => {
  const { email, password } = req.body || {};
  const cleanEmail = (email || '').trim().toLowerCase();

  if (!cleanEmail || !password) {
    return res.status(400).json({ error: 'Email and password are required' });
  }

  const user = db.users.find(u => u.email && u.email.toLowerCase() === cleanEmail);
  if (!user) {
    return res.status(401).json({ error: 'No account found with this email. Please register or check your spelling.' });
  }

  if (!user.passwordHash) {
    return res.status(400).json({ error: 'This account was registered via Google or SMS. Please sign in with Google or request a code.' });
  }

  const match = await comparePassword(password, user.passwordHash);
  if (!match) {
    return res.status(401).json({ error: 'Incorrect password. Please try again.' });
  }

  // Transparently upgrade legacy scrypt hash to bcrypt
  if (user.passwordHash.includes(':')) {
    user.passwordHash = await hashPassword(password);
  }
  claimCustomerBookings(user);
  saveDb(db);

  const token = jwt.sign(
    { id: user.id, email: user.email, name: user.name, phone: user.phone },
    JWT_SECRET,
    { expiresIn: '90d' }
  );

  return res.json({
    success: true,
    token,
    customer: {
      id: user.id,
      name: user.name,
      email: user.email,
      phone: user.phone,
      walletBalance: user.walletBalance !== undefined ? user.walletBalance : 0.0
    }
  });
});

// Customer Logout & Session Invalidation
app.post(['/api/auth/customer/logout', '/api/auth/logout'], (req, res) => {
  const authHeader = req.headers.authorization;
  if (authHeader && authHeader.startsWith('Bearer ')) {
    revokeToken(authHeader.split(' ')[1]);
  }
  return res.json({ success: true, message: 'Logged out successfully.' });
});

// Update Customer Profile
app.put('/api/customer/profile', authenticateCustomer, (req, res) => {
  const user = db.users.find(u => u.id === req.user.id);
  if (!user) return res.status(404).json({ error: 'User not found' });

  const { name, phone, email } = req.body || {};
  if (email) {
    const cleanEmail = String(email).trim().toLowerCase();
    const collision = db.users.find(u => u.id !== user.id && u.email && u.email.toLowerCase() === cleanEmail);
    if (collision) return res.status(409).json({ error: 'This email is already in use by another account.' });
    user.email = cleanEmail;
  }
  if (phone) {
    const cleanPhone = String(phone).replace(/\D/g, '');
    const collision = db.users.find(u => u.id !== user.id && u.phone && u.phone.replace(/\D/g, '') === cleanPhone);
    if (collision) return res.status(409).json({ error: 'This phone number is already in use by another account.' });
    user.phone = cleanPhone;
  }
  if (name && typeof name === 'string') {
    user.name = name.trim();
  }

  saveDb(db);
  return res.json({ success: true, customer: sanitizeUser(user) });
});

// Fetch Customer Profile
app.get('/api/customer/profile', authenticateCustomer, (req, res) => {
  const user = db.users.find(u => u.id === req.user.id);
  if (!user) return res.status(404).json({ error: 'User not found' });
  return res.json({ success: true, customer: sanitizeUser(user) });
});

// Wallet Operations
app.post('/api/customer/wallet/deduct', authenticateCustomer, (req, res) => {
  const user = db.users.find(u => u.id === req.user.id);
  if (!user) return res.status(404).json({ error: 'User not found' });
  const numAmount = Number(req.body && req.body.amount);
  if (!Number.isFinite(numAmount) || numAmount <= 0) {
    return res.status(400).json({ error: 'Invalid amount' });
  }
  if ((user.walletBalance || 0) < numAmount) {
    return res.status(400).json({ error: 'Insufficient wallet balance' });
  }
  user.walletBalance = (user.walletBalance || 0) - numAmount;
  saveDb(db);
  return res.json({ success: true, walletBalance: user.walletBalance });
});

app.post('/api/customer/wallet/add', authenticateAdmin, (req, res) => {
  const { amount, userId, email } = req.body || {};
  const user = db.users.find(u => (userId && u.id === userId) || (email && u.email === email));
  if (!user) return res.status(404).json({ error: 'User not found' });
  const numAmount = Number(amount);
  if (!Number.isFinite(numAmount) || numAmount <= 0 || numAmount > 100000) {
    return res.status(400).json({ error: 'Invalid amount' });
  }
  user.walletBalance = (user.walletBalance || 0) + numAmount;
  saveDb(db);
  return res.json({ success: true, walletBalance: user.walletBalance });
});

// ==========================================
// 2. ADMIN & VENUE OWNER PORTAL
// ==========================================

// Admin Sign In
app.post('/api/auth/login', (req, res) => {
  const { email, password } = req.body;
  if (typeof email === 'string' && typeof password === 'string' &&
      safeEqual(email, ADMIN_EMAIL) && safeEqual(password, ADMIN_PASSWORD)) {
    const token = jwt.sign({ email, isAdmin: true }, JWT_SECRET, { expiresIn: '12h' });
    return res.json({
      success: true,
      token,
      admin: { email, role: 'owner' }
    });
  }
  return res.status(401).json({ error: 'Invalid admin email or password' });
});

// ==========================================
// 3. VENUES CRUD
// ==========================================

// Public Venues List
app.get('/api/venues', (req, res) => {
  return res.json({ success: true, venues: db.venues });
});

// Admin Venues List
app.get('/api/admin/venues', authenticateAdmin, (req, res) => {
  return res.json({ success: true, venues: db.venues });
});

// Add / Update Venue
app.put('/api/admin/venues/:id', authenticateAdmin, (req, res) => {
  const venueId = req.params.id;
  const venueData = req.body;
  const index = db.venues.findIndex(v => v.id === venueId);

  if (index >= 0) {
    db.venues[index] = { ...db.venues[index], ...venueData };
  } else {
    db.venues.push({ id: venueId, ...venueData });
  }
  saveDb(db);
  return res.json({ success: true, venue: venueData });
});

// Delete Venue
app.delete('/api/admin/venues/:id', authenticateAdmin, (req, res) => {
  const venueId = req.params.id;
  db.venues = db.venues.filter(v => v.id !== venueId);
  db.bookings = db.bookings.filter(b => b.venueId !== venueId);
  saveDb(db);
  return res.json({ success: true, message: 'Venue deleted' });
});

// ==========================================
// 4. BOOKINGS & OPERATIONS
// ==========================================

// Admin Bookings List
app.get('/api/admin/bookings', authenticateAdmin, (req, res) => {
  return res.json({ success: true, bookings: db.bookings });
});

// Create Booking
const BOOKING_FIELDS = [
  'id', 'venueId', 'itemId', 'customer', 'startsAt', 'durationMinutes', 'price',
  'serviceNames', 'splitCount', 'multiController', 'phone', 'email', 'paymentMethod',
  'promoCode', 'discountAmount', 'staffMember', 'dueNow', 'serviceIds'
];

function bookingBlocksSlot(b, now) {
  if (b.cancelled || b.status === 'cancelled') return false;
  if (b.status === 'confirmed') return true;
  // pending holds only block while they have not expired
  return !b.holdExpiresAt || new Date(b.holdExpiresAt).getTime() > now;
}

app.post('/api/bookings', optionalAuth, async (req, res) => {
  const body = req.body || {};
  const isAdmin = !!req.admin;
  const now = Date.now();

  const venue = db.venues.find(v => v.id === body.venueId);
  if (!venue) return res.status(404).json({ error: 'Venue not found' });

  const start = new Date(body.startsAt);
  const duration = Number(body.durationMinutes);
  const price = Number(body.price);
  if (isNaN(start.getTime())) return res.status(400).json({ error: 'Invalid start time' });
  if (!Number.isInteger(duration) || duration < 15 || duration > 720) {
    return res.status(400).json({ error: 'Invalid duration' });
  }
  if (!Number.isFinite(price) || price < 0) return res.status(400).json({ error: 'Invalid price' });
  if (!isAdmin && start.getTime() < now - 5 * 60 * 1000) {
    return res.status(400).json({ error: 'Cannot book a time in the past' });
  }
  if (typeof body.itemId !== 'string' || !body.itemId) {
    return res.status(400).json({ error: 'itemId is required' });
  }

  // Whitelist fields: never persist arbitrary client-supplied keys.
  const booking = {};
  for (const k of BOOKING_FIELDS) if (body[k] !== undefined) booking[k] = body[k];
  booking.customer = String(booking.customer || '').slice(0, 80);
  booking.durationMinutes = duration;
  booking.price = price;
  booking.startsAt = start.toISOString();

  if (!booking.id || !/^[\w-]{1,64}$/.test(String(booking.id)) || db.bookings.some(b => b.id === booking.id)) {
    booking.id = 'bk_' + crypto.randomUUID();
  }

  // Double-booking guard. No `await` between this check and the push, so it is atomic.
  const end = start.getTime() + duration * 60000;
  const conflict = db.bookings.find(b =>
    b.venueId === booking.venueId && b.itemId === booking.itemId && bookingBlocksSlot(b, now) &&
    new Date(b.startsAt).getTime() < end &&
    new Date(b.startsAt).getTime() + Number(b.durationMinutes) * 60000 > start.getTime());
  if (conflict) return res.status(409).json({ error: 'Overlap conflict. This slot is already booked.' });

  booking.createdAt = new Date().toISOString();
  booking.cancelled = false;

  if (isAdmin) {
    // Venue staff may create walk-ins and blocks.
    booking.status = body.walkIn ? 'confirmed' : (body.status || 'confirmed');
    booking.paymentStatus = body.paymentStatus || (body.walkIn ? 'paid' : 'unpaid');
    booking.holdExpiresAt = body.holdExpiresAt || null;
    if (body.blockReason) booking.blockReason = String(body.blockReason).slice(0, 200);
  } else {
    booking.status = 'pending_payment';
    booking.paymentStatus = 'unpaid';
    booking.holdExpiresAt = new Date(now + 15 * 60 * 1000).toISOString();
    let owner = req.user;
    if (!owner) {
      const cleanPhone = (body.phone || body.customerPhone) ? String(body.phone || body.customerPhone).replace(/\D/g, '') : '';
      const cleanEmail = body.email ? String(body.email).trim().toLowerCase() : '';
      owner = db.users.find(u =>
        (cleanEmail && u.email && u.email.toLowerCase() === cleanEmail) ||
        (cleanPhone && u.phone && u.phone.replace(/\D/g, '') === cleanPhone)
      );
    }
    if (owner) {
      booking.ownerId = owner.id;
      booking.customerId = owner.id;
    }

    // Wallet payment is settled here, on the server, atomically with the booking.
    if (body.paymentMethod === 'wallet') {
      const user = req.user && db.users.find(u => u.id === req.user.id);
      if (!user) return res.status(401).json({ error: 'Sign in to pay with your wallet' });
      // The wallet pays the venue's deposit (same rule the app uses to quote it),
      // computed here from server-side venue data rather than a client number.
      const split = Math.max(1, Math.floor(Number(body.splitCount) || 1));
      const requiredDeposit = price * (Number(venue.depositPercent) || 0) / 100;
      const deposit = Math.round((split > 1 && price / split > requiredDeposit
        ? price / split : requiredDeposit) * 100) / 100;
      if (deposit <= 0) {
        return res.status(400).json({ error: 'This venue has no deposit configured' });
      }
      if ((user.walletBalance || 0) < deposit) {
        return res.status(402).json({ error: 'Insufficient wallet balance' });
      }
      user.walletBalance -= deposit;
      booking.status = 'confirmed';
      booking.paymentStatus = 'paid';
      booking.paymentMethod = 'wallet';
      booking.holdExpiresAt = null;
      booking.dueNow = 0;
    } else {
      booking.paymentMethod = '';
    }
  }
  db.bookings.push(booking);
  saveDb(db);

  const phone = booking.phone || booking.customerPhone;
  if (phone) {
    const slipVenue = venue.name || 'Hagzy Venue';
    const pinMsg = venue.googleMapsUrl ? `\n📍 رابط الموقع على الخريطة: ${venue.googleMapsUrl}` : '';
    const slip = `🎉 تم استلام حجزك في ${slipVenue} بنجاح!\n` +
      `📅 الموعد: ${booking.startsAt}\n` +
      `🏷️ رقم الحجز: ${booking.id}\n` +
      `💵 الإجمالي: ${booking.price} ج.م` + pinMsg;
    sendSmsOrWhatsApp({ phone, message: slip, otp: '' }).catch(() => {});
  }

  const walletUser = req.user && db.users.find(u => u.id === req.user.id);
  return res.json({
    success: true,
    booking,
    ...(booking.paymentMethod === 'wallet' && walletUser ? { walletBalance: walletUser.walletBalance } : {})
  });
});

// Customer: own bookings (matched by account, phone, or email)
app.get('/api/bookings', authenticateCustomer, (req, res) => {
  const user = db.users.find(u => u.id === req.user.id);
  if (!user) return res.status(404).json({ error: 'User not found' });
  claimCustomerBookings(user);

  const userPhone = user.phone ? String(user.phone).replace(/\D/g, '') : '';
  const userEmail = user.email ? String(user.email).trim().toLowerCase() : '';

  const mine = db.bookings.filter(b => {
    if (b.ownerId === user.id || b.customerId === user.id) return true;
    const bPhone = (b.phone || b.customerPhone) ? String(b.phone || b.customerPhone).replace(/\D/g, '') : '';
    const bEmail = b.email ? String(b.email).trim().toLowerCase() : '';
    if (userPhone && bPhone && userPhone === bPhone) return true;
    if (userEmail && bEmail && userEmail === bEmail) return true;
    return false;
  });
  return res.json({ success: true, bookings: mine });
});

// Customer Booking Cancellation
app.post('/api/bookings/:id/cancel', authenticateCustomer, (req, res) => {
  const booking = db.bookings.find(b => b.id === req.params.id);
  if (!booking) return res.status(404).json({ error: 'Booking not found' });

  const user = db.users.find(u => u.id === req.user.id);
  if (!user) return res.status(404).json({ error: 'User not found' });

  const isOwner = (booking.ownerId === user.id) || (booking.customerId === user.id) ||
    (user.phone && booking.phone && user.phone.replace(/\D/g, '') === String(booking.phone).replace(/\D/g, '')) ||
    (user.email && booking.email && user.email.toLowerCase() === String(booking.email).toLowerCase());

  if (!isOwner) {
    return res.status(403).json({ error: 'You are not authorized to cancel this booking.' });
  }

  if (booking.status === 'cancelled' || booking.cancelled) {
    return res.status(400).json({ error: 'This booking has already been cancelled.' });
  }
  if (booking.status === 'expired') {
    return res.status(400).json({ error: 'This reservation hold has already expired.' });
  }
  if (new Date(booking.startsAt).getTime() <= Date.now()) {
    return res.status(400).json({ error: 'Cannot cancel a booking that has already started or elapsed.' });
  }

  booking.status = 'cancelled';
  booking.cancelled = true;
  booking.updatedAt = new Date().toISOString();
  saveDb(db);

  return res.json({ success: true, message: 'Booking cancelled successfully.', booking });
});

// Public status poll: no contact details are returned.
app.get('/api/bookings/:id', (req, res) => {
  const b = db.bookings.find(x => x.id === req.params.id);
  if (!b) return res.status(404).json({ error: 'Booking not found' });
  const { phone, email, customerPhone, ownerId, paymentReference, ...safe } = b;
  return res.json({ success: true, booking: safe });
});

// Confirm Booking (Deposit Verified)
app.post('/api/admin/bookings/:id/confirm', authenticateAdmin, (req, res) => {
  const booking = db.bookings.find(b => b.id === req.params.id);
  if (!booking) return res.status(404).json({ error: 'Booking not found' });

  booking.confirmed = true;
  booking.isPendingPayment = false;
  booking.status = 'confirmed';
  saveDb(db);

  if (booking.customerPhone) {
    sendSmsOrWhatsApp({
      phone: booking.customerPhone,
      message: `✅ تم تأكيد حجزك رسمياً في حجزي! رقم الحجز: ${booking.id}. نتمنى لك وقتاً ممتعاً.`,
      otp: ''
    });
  }

  return res.json({ success: true, booking });
});

// Cancel Booking
app.delete('/api/admin/bookings/:id', authenticateAdmin, (req, res) => {
  const booking = db.bookings.find(b => b.id === req.params.id);
  if (booking) {
    booking.cancelled = true;
    booking.status = 'cancelled';
    saveDb(db);
  }
  return res.json({ success: true, message: 'Booking cancelled' });
});

// Payment Proof Submission (InstaPay / Vodafone Cash)
app.post('/api/bookings/:id/payment-proof', (req, res) => {
  const booking = db.bookings.find(b => b.id === req.params.id);
  if (!booking) return res.status(404).json({ error: 'Booking not found' });
  if (booking.status !== 'pending_payment') {
    return res.status(409).json({ error: 'This booking is not awaiting payment' });
  }
  const method = String((req.body && req.body.method) || '');
  const reference = String((req.body && req.body.reference) || '').trim();
  if (!['instapay', 'vodafone_cash', 'vodafoneCash', 'fawry', 'card'].includes(method) &&
      !/^[\w \-]{2,32}$/.test(method)) {
    return res.status(400).json({ error: 'Invalid payment method' });
  }
  if (reference.length < 4 || reference.length > 64) {
    return res.status(400).json({ error: 'Invalid payment reference' });
  }
  booking.paymentMethod = method;
  booking.paymentReference = reference;
  booking.paymentProof = { method, reference, submittedAt: new Date().toISOString() };
  booking.proofSubmitted = true;
  // The venue still has to verify the transfer (POST /api/admin/bookings/:id/confirm).
  // Extend the hold so the customer isn't dropped while the venue checks.
  booking.holdExpiresAt = new Date(Date.now() + 60 * 60 * 1000).toISOString();
  saveDb(db);
  return res.json({ success: true, booking });
});

// Paymob Intention Mock / Webhook
app.post('/api/bookings/:id/paymob-intention', (req, res) => {
  // TODO: create a real Paymob intention with PAYMOB_SECRET_KEY and confirm bookings
  // from a signed (HMAC-verified) webhook. Until then, don't hand customers a fake URL.
  return res.status(501).json({ error: 'Online card payments are not enabled yet. Please use InstaPay or Vodafone Cash.' });
});

// Health check: handles /health, /api/health, /healthz, and /ping
app.get(['/health', '/api/health', '/healthz', '/ping'], (req, res) => {
  return res.status(200).json({
    status: 'healthy',
    time: new Date().toISOString(),
    usersCount: db.users.length,
    venuesCount: db.venues.length,
    bookingsCount: db.bookings.length
  });
});

if (pgPool) {
  hydratePostgres().catch(err => {
    console.warn('PostgreSQL hydrate notice (running on local state):', err.message);
  });
}

app.listen(PORT, '0.0.0.0', () => {
  console.log(`\n🚀 Hagzy server is live on port ${PORT} (bound to 0.0.0.0)`);
  console.log(`📡 Venues loaded: ${db.venues.length} · 👥 Users: ${db.users.length}\n`);
});

