/**
 * RideShareService
 * ================
 * Handles co-passenger ride-share state.
 *
 * Mirrors the existing Firebase RTDB ride_shares logic —
 * this is a Socket.IO wrapper that emits the same events
 * so the Flutter app receives them via the unified transport.
 *
 * NOTE: The authoritative state for ride-shares still lives in Firebase RTDB
 * (as noted in the existing rtdb_provider.dart). This service broadcasts
 * share events via Socket.IO as a supplemental channel.
 */

const { createEventEnvelope } = require('./eventUtils');

/**
 * Broadcast a ride-share toggle event.
 * @param {import('socket.io').Server} io
 * @param {import('socket.io').Socket} socket  Passenger's socket
 * @param {Object} payload  { sharing: boolean, name: string, lat: number, lng: number }
 */
function handleRideShareToggle(io, socket, payload) {
  const passengerUid = socket.data.uid;
  const { sharing, name, lat, lng } = payload;

  const event = createEventEnvelope('ride_share.updated', {
    passenger_uid: passengerUid,
    sharing: !!sharing,
    name: name || 'Unknown',
    latitude: lat || 0,
    longitude: lng || 0,
  });

  // Broadcast to all connected passengers in the area
  io.to('passengers').emit('ride_share.updated', event);
  console.log(`[RideShareService] Share toggle: uid=${passengerUid} sharing=${sharing}`);
}

module.exports = { handleRideShareToggle };
