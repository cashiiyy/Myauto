/**
 * MyAuto Node.js + Socket.IO Real-Time Server
 * ============================================
 * All configuration is loaded from environment variables.
 * No credentials or URLs are hardcoded.
 */

const path = require('path');
require('dotenv').config({ path: path.resolve(__dirname, '..', '.env') });

// ── Env vars ─────────────────────────────────────────────────────────────────

const PORT = parseInt(process.env.PORT || process.env.SOCKETIO_PORT || '3001', 10);
const DATABASE_URL = process.env.DATABASE_URL;
const REDIS_URL = process.env.REDIS_URL;
const FIREBASE_SERVICE_ACCOUNT_PATH = process.env.FIREBASE_SERVICE_ACCOUNT_PATH;
const FIREBASE_PROJECT_ID = process.env.FIREBASE_PROJECT_ID || 'myauto-493fc';
const CORS_ORIGINS = (process.env.CORS_ORIGINS || '').split(',').filter(Boolean);
const APP_ENV = process.env.APP_ENV || 'development';

// ── Redis usage clarification ─────────────────────────────────────────────────
// Redis is currently RESERVED for future use, NOT actively consumed by v1.
//
// Current v1: Node.js reads/writes PostgreSQL only.
// Future v2 (horizontal scaling):
//   - Redis pub/sub for broadcasting driver.presence events across multiple
//     Node.js instances (when running behind a load balancer)
//   - Redis for Socket.IO adapter (socket.io-redis) to share room state
//
// REDIS_URL is kept in the env and config to avoid a breaking change when
// Redis pub/sub is activated. No redis client is imported in v1.

// Validation
if (!DATABASE_URL) {
  console.error('[Config] FATAL: DATABASE_URL is required.');
  process.exit(1);
}

module.exports = {
  PORT,
  DATABASE_URL,
  REDIS_URL,        // Reserved: see comment above
  FIREBASE_SERVICE_ACCOUNT_PATH,
  FIREBASE_PROJECT_ID,
  CORS_ORIGINS,
  APP_ENV,
  isDev: APP_ENV === 'development',
};
