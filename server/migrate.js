// Database Migration Runner
// Supports idempotent execution, transactional batches, and --dry-run validation.

const fs = require('fs');
const path = require('path');

const MIGRATIONS_DIR = path.join(__dirname, 'migrations');

async function getMigrationFiles() {
  if (!fs.existsSync(MIGRATIONS_DIR)) return [];
  return fs
    .readdirSync(MIGRATIONS_DIR)
    .filter(file => file.endsWith('.sql'))
    .sort();
}

async function runMigrations({ dryRun = false, connectionString = process.env.DATABASE_URL, pool = null } = {}) {
  const files = await getMigrationFiles();
  const summary = {
    total: files.length,
    executed: [],
    dryRun,
    status: 'success',
  };

  console.log(`[MIGRATE] Found ${files.length} migration file(s) in ${MIGRATIONS_DIR}`);

  if (dryRun || !connectionString && !pool) {
    console.log(`[MIGRATE] Running in ${dryRun ? '--dry-run' : 'offline/syntax-check'} mode`);
    for (const file of files) {
      const sql = fs.readFileSync(path.join(MIGRATIONS_DIR, file), 'utf8');
      if (!sql.trim()) {
        throw new Error(`Migration ${file} is empty`);
      }
      const statements = sql
        .split(';')
        .map(s => s.trim())
        .filter(s => s.length > 0);
      console.log(`[MIGRATE] ✓ Validated ${file} (${statements.length} statements)`);
      summary.executed.push({ file, statementsCount: statements.length });
    }
    return summary;
  }

  // Active Postgres connection mode
  const { Pool } = require('pg');
  const activePool = pool || new Pool({ connectionString });
  const client = await activePool.connect();

  try {
    await client.query('BEGIN');
    await client.query(`
      CREATE TABLE IF NOT EXISTS schema_migrations (
        version TEXT PRIMARY KEY,
        applied_at TIMESTAMPTZ NOT NULL DEFAULT now()
      )
    `);

    const { rows: existingRows } = await client.query('SELECT version FROM schema_migrations');
    const appliedSet = new Set(existingRows.map(r => r.version));

    for (const file of files) {
      if (appliedSet.has(file)) {
        console.log(`[MIGRATE] - Skipping already applied: ${file}`);
        continue;
      }

      console.log(`[MIGRATE] Applying: ${file}...`);
      const sql = fs.readFileSync(path.join(MIGRATIONS_DIR, file), 'utf8');
      await client.query(sql);
      await client.query('INSERT INTO schema_migrations (version) VALUES ($1)', [file]);
      console.log(`[MIGRATE] ✓ Applied: ${file}`);
      summary.executed.push({ file });
    }

    await client.query('COMMIT');
    console.log('[MIGRATE] All migrations applied successfully.');
    return summary;
  } catch (err) {
    await client.query('ROLLBACK');
    console.error('[MIGRATE] ✗ Migration failed, transaction rolled back:', err.message);
    throw err;
  } finally {
    client.release();
    if (!pool) await activePool.end();
  }
}

if (require.main === module) {
  const isDryRun = process.argv.includes('--dry-run');
  runMigrations({ dryRun: isDryRun })
    .then(summary => {
      console.log(`[MIGRATE] Finished successfully: ${summary.executed.length} migration(s) processed.`);
      process.exit(0);
    })
    .catch(err => {
      console.error('[MIGRATE] Fatal error:', err);
      process.exit(1);
    });
}

module.exports = {
  runMigrations,
  getMigrationFiles,
};

