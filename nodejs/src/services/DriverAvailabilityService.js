/**
 * DriverAvailabilityService
 * =========================
 * Manages driver online/offline state changes.
 *
 * When a driver connects, they join the 'drivers' room.
 * When a driver goes online, a 'driver.availability' event is broadcast.
 * When a driver disconnects, an OFFLINE presence event is broadcast.
 *
 * This service does NOT change matching or booking rules.
 */

const db = require('../db/postgres');
const { createEventEnvelope } = require('./eventUtils');

/**
 * Handle driver coming online.
 * @param {import('socket.io').Server} io
 * @param {import('socket.io').Socket} socket
 */
async function handleDriverOnline(io, socket) {
  const { uid } = socket.data;
  if (!uid) return;

  socket.join('drivers');
  console.log(`[AvailabilityService] Driver ${uid} online`);

  try {
    await db.query(
      `UPDATE driver_locations SET is_available = true, updated_at = NOW() WHERE driver_uid = $1`,
      [uid]
    );
  } catch (err) {
    // Driver may not have a location record yet — that's fine
    if (process.env.APP_ENV === 'development') {
      console.debug(`[AvailabilityService] No location record for ${uid} yet`);
    }
  }

  const event = createEventEnvelope('driver.availability', {
    driver_uid: uid,
    state: 'AVAILABLE',
    freshness: 'LIVE',
  });
  io.to('passengers').emit('driver.availability', event);
}

/**
 * Handle driver going offline (disconnect or explicit offline event).
 * @param {import('socket.io').Server} io
 * @param {string} uid
 */
async function handleDriverOffline(io, uid) {
  if (!uid) return;
  console.log(`[AvailabilityService] Driver ${uid} offline`);

  try {
    await db.query(
      `UPDATE driver_locations SET is_available = false, updated_at = NOW() WHERE driver_uid = $1`,
      [uid]
    );
  } catch (err) {
    console.error(`[AvailabilityService] DB error for uid=${uid}:`, err.message);
  }

  const event = createEventEnvelope('driver.presence', {
    driver_uid: uid,
    state: 'OFFLINE',
    freshness: 'OFFLINE',
  });
  io.to('passengers').emit('driver.presence', event);
}

module.exports = { handleDriverOnline, handleDriverOffline };
