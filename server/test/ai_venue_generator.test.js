const { test, before, after } = require('node:test');
const assert = require('node:assert/strict');
const { spawn } = require('node:child_process');
const { buildFallbackVenueFromTemplateNode } = require('../index.js');

const PORT = 5800 + Math.floor(Math.random() * 300);
const BASE = `http://localhost:${PORT}`;

let proc;
const call = (method, url, { token, body, headers } = {}) =>
  fetch(BASE + url, {
    method,
    headers: {
      'Content-Type': 'application/json',
      ...(token ? { Authorization: `Bearer ${token}` } : {}),
      ...headers,
    },
    body: body ? JSON.stringify(body) : undefined,
  }).then(async r => ({ status: r.status, json: await r.json().catch(() => ({})) }));

before(async () => {
  proc = spawn('node', ['index.js'], {
    cwd: __dirname + '/..',
    env: {
      ...process.env,
      PORT: String(PORT),
      IS_TEST: 'true',
      STORAGE_MODE: 'file',
      DATA_DIR: require('os').tmpdir() + '/hagzy-ai-venue-test-' + Date.now(),
    },
    stdio: 'ignore',
  });

  for (let i = 0; i < 40; i++) {
    await new Promise(r => setTimeout(r, 200));
    try {
      const res = await fetch(BASE + '/health');
      if (res.ok) return;
    } catch (_) {}
  }
  throw new Error(`Server failed to start on port ${PORT}`);
});

after(() => {
  if (proc) proc.kill();
});

test('Egyptian Heuristic Fallback - Arabic Padel extraction', () => {
  const prompt = 'ملعب بادل في التجمع الخامس اسمه نيل بادل، الساعة بـ 400 جنيه وعربون 25% ورقم الكاش 01015325250';
  const venue = buildFallbackVenueFromTemplateNode(prompt, 'padel', true);

  assert.equal(venue.type, 'sports');
  assert.equal(venue.name, 'نيل بادل');
  assert.ok(venue.location.includes('التجمع الخامس'));
  assert.equal(venue.depositPercent, 25);
  assert.equal(venue.vodafoneCashNumber, '01015325250');
  assert.ok(venue.items.length >= 1);
  assert.equal(venue.items[0].hourlyRate, 400);
  assert.ok(venue.services.some(s => s.name.includes('مضرب') || s.name.includes('Racket')));
});

test('Egyptian Heuristic Fallback - Football 5v5 extraction', () => {
  const prompt = 'ملعب كرة قدم خماسي في الشيخ زايد، الساعة بـ 350 جنيه وعربون 30% ورقم المحفظة 01041570557';
  const venue = buildFallbackVenueFromTemplateNode(prompt, 'football', true);

  assert.equal(venue.type, 'sports');
  assert.ok(venue.location.includes('الشيخ زايد'));
  assert.equal(venue.depositPercent, 30);
  assert.equal(venue.vodafoneCashNumber, '01041570557');
  assert.equal(venue.items[0].hourlyRate, 350);
});

test('Egyptian Heuristic Fallback - Barber / Grooming VIP Salon', () => {
  const prompt = 'صالون حلاقة ورعاية رجالية في المعادي، كرسي VIP الساعة بـ 150 وعربون 20% وإنستاباي salon@instapay';
  const venue = buildFallbackVenueFromTemplateNode(prompt, 'salon', true);

  assert.equal(venue.type, 'salon');
  assert.ok(venue.location.includes('المعادي'));
  assert.equal(venue.depositPercent, 20);
  assert.equal(venue.instaPayAddress, 'salon@instapay');
  assert.equal(venue.items[0].hourlyRate, 150);
});

test('Egyptian Heuristic Fallback - Gaming / Playstation Lounge', () => {
  const prompt = 'صالة ألعاب وبلايستيشن في مدينة نصر، غرفة VIP شاشة 65 بوصة الساعة بـ 70 جنيه';
  const venue = buildFallbackVenueFromTemplateNode(prompt, 'playstation', true);

  assert.equal(venue.type, 'lounge');
  assert.ok(venue.location.includes('مدينة نصر'));
  assert.equal(venue.items[0].hourlyRate, 70);
  assert.ok(venue.amenities.includes('High-Speed Wi-Fi') || venue.amenities.includes('AC'));
});

test('Egyptian Heuristic Fallback - Minimum 5 EGP deposit floor rule', () => {
  // If price is 10 EGP and deposit is 10% (1 EGP), Egyptian wallet networks reject transfers < 5 EGP
  const prompt = 'ترابيزة بينج بونج الساعة بـ 10 جنيه وعربون 5%';
  const venue = buildFallbackVenueFromTemplateNode(prompt, 'sports', true);
  assert.ok(venue.depositPercent >= 5);
});

test('HTTP POST /api/ai/venue-generator endpoint parity', async () => {
  const res = await call('POST', '/api/ai/venue-generator', {
    body: {
      prompt: 'ملعب بادل في التجمع الخامس اسمه نيل بادل، الساعة بـ 400 جنيه وعربون 25% ورقم الكاش 01015325250',
      categoryHint: 'padel',
      isArabic: true,
    },
  });

  assert.equal(res.status, 200);
  assert.equal(res.json.success, true);
  assert.ok(res.json.venue);
  assert.ok(res.json.venue.name.includes('نيل بادل'), `Expected name to contain 'نيل بادل', got '${res.json.venue.name}'`);
  assert.equal(res.json.venue.type, 'sports');
  assert.equal(res.json.venue.depositPercent, 25);
  assert.equal(res.json.venue.vodafoneCashNumber, '01015325250');
  assert.ok(res.json.venue.items.length >= 1);
});
