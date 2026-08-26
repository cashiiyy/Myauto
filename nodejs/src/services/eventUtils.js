/**
 * Shared event envelope utility.
 * Produces events in the same format as the FastAPI WebSocket backend
 * so the Flutter BackendEvent.fromJson() parser works unchanged.
 */

const { randomUUID } = require('crypto');

/**
 * Create a standard event envelope.
 * @param {string} type  Event type (e.g. 'driver.presence')
 * @param {Object} payload  Event-specific data
 * @param {string|null} rideId  Optional ride UUID
 */
function createEventEnvelope(type, payload = {}, rideId = null) {
  return {
    event_id: randomUUID(),
    type,
    server_timestamp: new Date().toISOString(),
    ride_id: rideId,
    payload,
  };
}

module.exports = { createEventEnvelope };
