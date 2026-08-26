/**
 * LocationRealtimeService
 * =======================
 * Handles live driver GPS location events.
 *
 * Event flow:
 *   Driver socket emits 'location.update' →
 *   Server updates PostgreSQL driver_locations →
 *   Server broadcasts 'driver.presence' to nearby passenger rooms
 *
 * This service does NOT alter any matching, booking, or ride logic.
 * It reproduces the existing FastAPI /api/location endpoint behaviour
 * via Socket.IO for the real-time path.
 */

const db = require('../db/postgres');
const { createEventEnvelope } = require('./eventUtils');

/**
 * Handle a driver location update event.
 *
 * @param {import('socket.io').Server} io   Socket.IO server
 * @param {import('socket.io').Socket} socket  Driver's socket
 * @param {Object} payload  { latitude, longitude, accuracy_meters?, heading_degrees?, speed_mps? }
 */
async function handleLocationUpdate(io, socket, payload) {
  const { uid } = socket.data;
  if (!uid) return;

  const { latitude, longitude, accuracy_meters, heading_degrees, speed_mps, captured_at } = payload;

  if (typeof latitude !== 'number' || typeof longitude !== 'number') {
    socket.emit('error', { message: 'Invalid location payload' });
    return;
  }

  try {
    // Upsert driver location into PostgreSQL (same table as FastAPI)
    await db.query(
      `INSERT INTO driver_locations (driver_uid, location, accuracy_meters, heading_degrees, speed_mps, captured_at, updated_at)
       VALUES ($1, ST_SetSRID(ST_Point($2, $3), 4326)::geography, $4, $5, $6, to_timestamp($7/1000.0), NOW())
       ON CONFLICT (driver_uid)
       DO UPDATE SET
         location = EXCLUDED.location,
         accuracy_meters = EXCLUDED.accuracy_meters,
         heading_degrees = EXCLUDED.heading_degrees,
         speed_mps = EXCLUDED.speed_mps,
         captured_at = EXCLUDED.captured_at,
         updated_at = NOW()`,
      [uid, longitude, latitude, accuracy_meters, heading_degrees, speed_mps, captured_at || Date.now()]
    );

    // Broadcast presence event to passengers in range
    // (simplified: broadcast to 'passengers' room — production should use geofence rooms)
    const presenceEvent = createEventEnvelope('driver.presence', {
      driver_uid: uid,
      latitude,
      longitude,
      accuracy_meters: accuracy_meters || null,
      heading_degrees: heading_degrees || null,
      freshness: 'LIVE',
      state: 'AVAILABLE',
    });

    io.to('passengers').emit('driver.presence', presenceEvent);

  } catch (err) {
    console.error(`[LocationService] DB error for uid=${uid}:`, err.message);
  }
}

module.exports = { handleLocationUpdate };
