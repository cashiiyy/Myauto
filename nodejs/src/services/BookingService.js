/**
 * BookingService
 * ==============
 * Handles driver accept/reject events and ride lifecycle transitions.
 *
 * Event flow:
 *   Driver emits 'ride.accept' or 'ride.reject' →
 *   Server updates ride status in PostgreSQL →
 *   Server notifies passenger of result
 *
 * Status transitions:
 *   matching → accepted → in_progress → completed
 *   matching → rejected
 *   any      → cancelled
 */

const db = require('../db/postgres');
const { createEventEnvelope } = require('./eventUtils');

/**
 * Handle driver accepting a ride.
 * @param {import('socket.io').Server} io
 * @param {import('socket.io').Socket} socket  Driver's socket
 * @param {Object} payload  { match_id, request_id, passenger_uid }
 */
async function handleRideAccept(io, socket, payload) {
  const driverUid = socket.data.uid;
  const { match_id, request_id, passenger_uid } = payload;

  if (!request_id || !passenger_uid) {
    socket.emit('error', createEventEnvelope('error', { message: 'Missing request_id or passenger_uid' }));
    return;
  }

  try {
    await db.query(
      `UPDATE ride_requests SET status = 'accepted', driver_uid = $1, updated_at = NOW() WHERE id = $2`,
      [driverUid, request_id]
    );

    const acceptEvent = createEventEnvelope('ride.accepted', {
      match_id,
      request_id,
      driver_uid: driverUid,
      message: 'Driver is on the way!',
    }, request_id);

    // Notify passenger
    io.to(`user:${passenger_uid}`).emit('ride.accepted', acceptEvent);
    // Confirm to driver
    socket.emit('ride.accepted', acceptEvent);

    console.log(`[BookingService] Accepted: driver=${driverUid} request=${request_id}`);
  } catch (err) {
    console.error('[BookingService] Accept error:', err.message);
  }
}

/**
 * Handle driver rejecting a ride.
 * @param {import('socket.io').Server} io
 * @param {import('socket.io').Socket} socket  Driver's socket
 * @param {Object} payload  { match_id, request_id, passenger_uid }
 */
async function handleRideReject(io, socket, payload) {
  const driverUid = socket.data.uid;
  const { request_id, passenger_uid } = payload;

  if (!request_id) {
    socket.emit('error', createEventEnvelope('error', { message: 'Missing request_id' }));
    return;
  }

  try {
    await db.query(
      `UPDATE ride_requests SET status = 'rejected', updated_at = NOW() WHERE id = $1`,
      [request_id]
    );

    // Re-enable driver availability
    await db.query(
      `UPDATE driver_locations SET is_available = true, updated_at = NOW() WHERE driver_uid = $1`,
      [driverUid]
    );

    const rejectEvent = createEventEnvelope('ride.rejected', {
      request_id,
      driver_uid: driverUid,
      message: 'Driver is unavailable.',
    }, request_id);

    if (passenger_uid) {
      io.to(`user:${passenger_uid}`).emit('ride.rejected', rejectEvent);
    }
    socket.emit('ride.rejected', rejectEvent);

    console.log(`[BookingService] Rejected: driver=${driverUid} request=${request_id}`);
  } catch (err) {
    console.error('[BookingService] Reject error:', err.message);
  }
}

/**
 * Handle ride cancellation (from passenger or driver).
 * @param {import('socket.io').Server} io
 * @param {import('socket.io').Socket} socket
 * @param {Object} payload  { request_id, other_party_uid }
 */
async function handleRideCancel(io, socket, payload) {
  const uid = socket.data.uid;
  const { request_id, other_party_uid, driver_uid } = payload;

  if (!request_id) return;

  try {
    await db.query(
      `UPDATE ride_requests SET status = 'cancelled', updated_at = NOW() WHERE id = $1`,
      [request_id]
    );

    // Re-enable driver
    if (driver_uid) {
      await db.query(
        `UPDATE driver_locations SET is_available = true WHERE driver_uid = $1`,
        [driver_uid]
      );
    }

    const cancelEvent = createEventEnvelope('ride.cancelled', {
      request_id,
      cancelled_by: uid,
    }, request_id);

    if (other_party_uid) {
      io.to(`user:${other_party_uid}`).emit('ride.cancelled', cancelEvent);
    }

    console.log(`[BookingService] Cancelled: by=${uid} request=${request_id}`);
  } catch (err) {
    console.error('[BookingService] Cancel error:', err.message);
  }
}

/**
 * Handle ride completion.
 * @param {import('socket.io').Server} io
 * @param {import('socket.io').Socket} socket  Driver's socket
 * @param {Object} payload  { request_id, passenger_uid }
 */
async function handleRideComplete(io, socket, payload) {
  const driverUid = socket.data.uid;
  const { request_id, passenger_uid } = payload;

  if (!request_id) return;

  try {
    await db.query(
      `UPDATE ride_requests SET status = 'completed', updated_at = NOW() WHERE id = $1`,
      [request_id]
    );

    // Re-enable driver
    await db.query(
      `UPDATE driver_locations SET is_available = true WHERE driver_uid = $1`,
      [driverUid]
    );

    const completeEvent = createEventEnvelope('ride.completed', {
      request_id,
      driver_uid: driverUid,
    }, request_id);

    if (passenger_uid) {
      io.to(`user:${passenger_uid}`).emit('ride.completed', completeEvent);
    }
    socket.emit('ride.completed', completeEvent);

    console.log(`[BookingService] Completed: driver=${driverUid} request=${request_id}`);
  } catch (err) {
    console.error('[BookingService] Complete error:', err.message);
  }
}

module.exports = {
  handleRideAccept,
  handleRideReject,
  handleRideCancel,
  handleRideComplete,
};
