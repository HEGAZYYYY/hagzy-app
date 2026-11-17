import { Hono } from '@hono/hono';
import { cors } from '@hono/hono/cors';
import { getEnv, getSupabaseAdmin } from './_shared/db.ts';
import { registerAdminAndPartnerRoutes } from './routes_admin_partner.ts';
import { registerAuthRoutes } from './routes_auth.ts';
import { registerCustomerAndBookingRoutes } from './routes_customer_bookings.ts';
import { registerPaymentAndWebhookRoutes } from './routes_payments_webhooks.ts';

function buildAllowedOrigins(): string[] {
  const configured = getEnv('CORS_ORIGINS')
    .split(',')
    .map(s => s.trim())
    .filter(Boolean);
  return [
    ...configured,
    'https://hagzy-booking.web.app',
    'https://hagzy-acea1.web.app',
    'https://hagzy-web.onrender.com',
    'https://hagzy.app',
  ];
}

function createRoutes(): Hono {
  const router = new Hono();

  registerAuthRoutes(router);
  registerCustomerAndBookingRoutes(router);
  registerAdminAndPartnerRoutes(router);
  registerPaymentAndWebhookRoutes(router);

  const handleHealth = async (c: any) => {
    const supabase = getSupabaseAdmin();
    const [{ count: usersCount }, { count: venuesCount }, { count: bookingsCount }] = await Promise.all([
      supabase.from('users').select('id', { count: 'exact', head: true }),
      supabase.from('venues').select('id', { count: 'exact', head: true }).eq('is_deleted', false),
      supabase.from('bookings').select('id', { count: 'exact', head: true }),
    ]);

    return c.json({
      status: 'healthy',
      runtime: 'supabase-edge-functions',
      storageMode: 'supabase-postgres',
      postgresHydrated: true,
      firebaseRemoved: true,
      time: new Date().toISOString(),
      usersCount: usersCount ?? 0,
      venuesCount: venuesCount ?? 0,
      bookingsCount: bookingsCount ?? 0,
      configured: {
        database: true,
        jwt: Boolean(getEnv('JWT_SECRET') || getEnv('SUPABASE_SERVICE_ROLE_KEY')),
        adminEmail: Boolean(getEnv('ADMIN_EMAIL')),
        payments: Boolean(getEnv('PAYMENT_WEBHOOK_SECRET') || getEnv('PAYMENT_LISTENER_KEY')),
      },
    });
  };

  router.get('/health', handleHealth);
  router.get('/api/health', handleHealth);
  router.get('/healthz', handleHealth);
  router.get('/ping', handleHealth);

  return router;
}

const app = new Hono();
const allowedOrigins = buildAllowedOrigins();

app.use(
  '*',
  cors({
    origin: origin => {
      if (!origin) return '*';
      if (allowedOrigins.includes(origin)) return origin;
      if (/^https?:\/\/(localhost|127\.0\.0\.1)(:\d+)?$/i.test(origin)) return origin;
      if (origin.endsWith('.onrender.com') || origin.endsWith('.pages.dev') || origin.endsWith('.vercel.app')) {
        return origin;
      }
      return '';
    },
    allowHeaders: [
      'Authorization',
      'Content-Type',
      'Accept',
      'X-Signature',
      'X-Hagzy-Signature',
      'X-Webhook-Signature',
      'X-Timestamp',
      'X-Listener-Key',
      'apikey',
      'x-client-info',
    ],
    allowMethods: ['GET', 'POST', 'PUT', 'PATCH', 'DELETE', 'OPTIONS'],
    maxAge: 86400,
  }),
);

const apiRoutes = createRoutes();
app.route('/', apiRoutes);
app.route('/hagzy-api', apiRoutes);

app.onError((err, c) => {
  console.error('Edge function error:', err);
  return c.json({ error: err.message || 'Internal server error' }, 500);
});

Deno.serve(app.fetch);
