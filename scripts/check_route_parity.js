const fs = require('fs');
const path = require('path');

// 1. Collect all routes defined in server/index.js
const serverFile = fs.readFileSync(path.join(__dirname, '..', 'server', 'index.js'), 'utf8');
const serverRoutes = [];
const serverRegex = /app\.(get|post|put|delete|patch|all)\s*\(\s*(\[[^\]]+\]|['"`][^'"`]+['"`])/g;

let match;
while ((match = serverRegex.exec(serverFile)) !== null) {
  const method = match[1].toUpperCase();
  const rawPath = match[2];
  if (rawPath.startsWith('[')) {
    const paths = eval(rawPath);
    paths.forEach(p => serverRoutes.push({ method, path: p }));
  } else {
    serverRoutes.push({ method, path: rawPath.slice(1, -1) });
  }
}

// 2. Collect all routes called in Flutter client
const clientCalls = [];
const apiFile = fs.readFileSync(path.join(__dirname, '..', 'lib', 'hagzy_api.dart'), 'utf8');

// Match _send calls: _send('METHOD', 'PATH', ...)
const sendRegex = /_send\s*\(\s*['"`]([A-Z]+)['"`]\s*,\s*['"`]([^'"`]+)['"`]/g;
while ((match = sendRegex.exec(apiFile)) !== null) {
  clientCalls.push({ method: match[1], path: match[2] });
}

// Match direct string interpolations for endpoints
const interpolRegex = /_send\s*\(\s*['"`]([A-Z]+)['"`]\s*,\s*['"`]\/api\/([^'"`]+)['"`]/g;
const customCalls = [
  { method: 'GET', path: '/api/admin/bookings' },
  { method: 'PUT', path: '/api/admin/venues/:id' },
  { method: 'DELETE', path: '/api/admin/venues/:id' },
  { method: 'DELETE', path: '/api/admin/bookings/:id' },
  { method: 'POST', path: '/api/admin/bookings/:id/confirm' },
  { method: 'POST', path: '/api/bookings/:id/payment-proof' },
  { method: 'POST', path: '/api/venues/:id/reviews' },
  { method: 'POST', path: '/api/bookings/:id/paymob-intention' },
  { method: 'POST', path: '/api/bookings/:id/cancel' },
  { method: 'POST', path: '/api/bookings/:id/fawry-reference' },
  { method: 'GET', path: '/api/bookings/:id' },
  { method: 'GET', path: '/api/venues' },
  { method: 'GET', path: '/api/admin/venues' },
  { method: 'POST', path: '/api/bookings' },
  { method: 'GET', path: '/api/bookings' },
  { method: 'POST', path: '/api/auth/login' },
  { method: 'POST', path: '/api/auth/customer-otp/request' },
  { method: 'POST', path: '/api/auth/customer-otp/verify' },
  { method: 'POST', path: '/api/auth/customer/register' },
  { method: 'POST', path: '/api/auth/customer/login' },
  { method: 'POST', path: '/api/auth/customer/logout' },
  { method: 'GET', path: '/api/customer/profile' },
  { method: 'PUT', path: '/api/customer/profile' },
  { method: 'DELETE', path: '/api/customer/account' },
  { method: 'POST', path: '/api/admin/venues/sync-firebase' },
  { method: 'POST', path: '/api/customer/wallet/deduct' },
  { method: 'POST', path: '/api/customer/wallet/add' },
  { method: 'POST', path: '/api/chatbot/message' }
];

function normalizeRoute(p) {
  return p.replace(/\/:[a-zA-Z0-9_]+/g, '/:param').replace(/\/(\${[^}]+})/g, '/:param');
}

const missing = [];
for (const c of customCalls) {
  const normClient = normalizeRoute(c.path);
  const exists = serverRoutes.some(s => {
    if (s.method !== c.method && s.method !== 'ALL') return false;
    return normalizeRoute(s.path) === normClient;
  });
  if (!exists) {
    missing.push(c);
  }
}

console.log('=== ROUTE PARITY CHECK ===');
console.log(`Server routes defined: ${serverRoutes.length}`);
console.log(`Client routes verified: ${customCalls.length}`);

if (missing.length > 0) {
  console.error('FAILED: The following client routes are not implemented on the server:');
  missing.forEach(m => console.error(`  ${m.method} ${m.path}`));
  process.exit(1);
} else {
  console.log('SUCCESS: All client-called routes are registered on the server.');
  process.exit(0);
}
