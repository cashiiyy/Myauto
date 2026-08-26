/**
 * PostgreSQL connection pool.
 *
 * Shares the same database as the FastAPI backend — no separate schema.
 * All table names match what FastAPI's SQLAlchemy models create.
 */

const { Pool } = require('pg');
const config = require('../config');

let pool;

function getPool() {
  if (!pool) {
    pool = new Pool({
      connectionString: config.DATABASE_URL,
      max: 10,
      idleTimeoutMillis: 30000,
      connectionTimeoutMillis: 5000,
    });

    pool.on('error', (err) => {
      console.error('[DB] Unexpected pool error:', err.message);
    });

    console.log('[DB] PostgreSQL pool initialized');
  }
  return pool;
}

/**
 * Execute a parameterised SQL query.
 * @param {string} text  SQL statement
 * @param {Array}  params Query parameters
 */
async function query(text, params) {
  const start = Date.now();
  const client = await getPool().connect();
  try {
    const result = await client.query(text, params);
    if (config.isDev) {
      console.debug(`[DB] query (${Date.now() - start}ms): ${text.substring(0, 80)}`);
    }
    return result;
  } finally {
    client.release();
  }
}

async function closePool() {
  if (pool) {
    await pool.end();
    pool = null;
    console.log('[DB] Pool closed');
  }
}

module.exports = { query, closePool };
