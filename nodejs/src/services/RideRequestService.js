/**
 * RideRequestService
 * ==================
 * Handles passenger ride request events via Socket.IO.
 *
 * Event flow:
 *   Passenger socket emits 'ride.create' →
 *   Server finds nearest available driver via PostGIS →
 *   Server emits 'ride.requested' to matched driver →
 *   Server emits 'ride.matched' to passenger
 *
 * Matching rules are preserved from the existing FastAPI backend:
 * - Initial radius: 2 km
 * - Fallback radius: 5 km
 * - Only AVAILABLE drivers with a LIVE or DELAYED freshness are matched
 *
 * This service does NOT change fare, payment, or UI logic.
 */

const { randomUUID } = require('crypto');
const db = require('../db/postgres');
const { createEventEnvelope } = require('./eventUtils');

const INITIAL_RADIUS_KM = parseFloat(process.env.INITIAL_RADIUS_KM || '2.0');
const FALLBACK_RADIUS_KM = parseFloat(process.env.FALLBACK_RADIUS_KM || '5.0');
const STALE_SECONDS = parseInt(process.env.FRESHNESS_STALE_SECONDS || '30', 10);

/**
 * Find the nearest available driver within radius.
 * @param {number} lat  Passenger latitude
 * @param {number} lng  Passenger longitude
 * @param {number} radiusKm  Search radius in km
 */
async function findNearestDriver(lat, lng, radiusKm) {
  const result = await db.query(
    `SELECT driver_uid,
            ST_Distance(location, ST_SetSRID(ST_Point($1, $2), 4326)::geography) / 1000.0 AS distance_km,
            ST_X(location::geometry) AS longitude,
            ST_Y(location::geometry) AS latitude
     FROM driver_locations
     WHERE is_available = true
       AND updated_at > NOW() - INTERVAL '${STALE_SECONDS} seconds'
       AND ST_DWithin(location, ST_SetSRID(ST_Point($1, $2), 4326)::geography, $3 * 1000)
     ORDER BY distance_km ASC
     LIMIT 1`,
    [lng, lat, radiusKm]
  );
  return result.rows[0] || null;
}

/**
 * Handle a passenger's ride request.
 * @param {import('socket.io').Server} io
 * @param {import('socket.io').Socket} socket  Passenger's socket
 * @param {Object} payload  { pickup_lat, pickup_lng, notes? }
 */
async function handleRideCreate(io, socket, payload) {
  const passengerUid = socket.data.uid;
  if (!passengerUid) return;

  const { pickup_lat, pickup_lng, notes } = payload;
  if (typeof pickup_lat !== 'number' || typeof pickup_lng !== 'number') {
    socket.emit('error', createEventEnvelope('error', { message: 'Invalid pickup coordinates' }));
    return;
  }

  const requestId = randomUUID();

  try {
    // 1. Write ride request to PostgreSQL
    await db.query(
      `INSERT INTO ride_requests (id, passenger_uid, pickup_location, status, notes, created_at)
       VALUES ($1, $2, ST_SetSRID(ST_Point($3, $4), 4326)::geography, 'matching', $5, NOW())
       ON CONFLICT DO NOTHING`,
      [requestId, passengerUid, pickup_lng, pickup_lat, notes || null]
    );

    // 2. Find nearest driver (initial radius, then fallback)
    let driver = await findNearestDriver(pickup_lat, pickup_lng, INITIAL_RADIUS_KM);
    if (!driver) {
      driver = await findNearestDriver(pickup_lat, pickup_lng, FALLBACK_RADIUS_KM);
    }

    if (!driver) {
      socket.emit('ride.expired', createEventEnvelope('error', {
        message: 'No drivers available nearby.',
        request_id: requestId,
      }, requestId));
      return;
    }

    const matchId = randomUUID();

    // 3. Lock the driver (mark as busy)
    await db.query(
      `UPDATE driver_locations SET is_available = false WHERE driver_uid = $1`,
      [driver.driver_uid]
    );

    // 4. Notify the driver
    const requestEvent = createEventEnvelope('ride.requested', {
      match_id: matchId,
      request_id: requestId,
      passenger_uid: passengerUid,
      pickup_lat: parseFloat(pickup_lat),
      pickup_lng: parseFloat(pickup_lng),
      notes: notes || null,
    }, requestId);

    io.to(`user:${driver.driver_uid}`).emit('ride.requested', requestEvent);

    // 5. Notify the passenger
    const matchedEvent = createEventEnvelope('ride.matched', {
      match_id: matchId,
      request_id: requestId,
      driver_uid: driver.driver_uid,
      distance_km: driver.distance_km,
      message: 'Driver found!',
    }, requestId);

    socket.emit('ride.matched', matchedEvent);

    console.log(`[RideRequest] Match: passenger=${passengerUid} driver=${driver.driver_uid} matchId=${matchId}`);

  } catch (err) {
    console.error('[RideRequest] Error:', err.message);
    socket.emit('error', createEventEnvelope('error', { message: 'Failed to create ride request' }));
  }
}

module.exports = { handleRideCreate };
