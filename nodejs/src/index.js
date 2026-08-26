/**
 * MyAuto Node.js + Socket.IO Real-Time Server — Entry Point
 * ==========================================================
 *
 * Architecture:
 *   Express → HTTP server → Socket.IO server
 *
 * Socket.IO rooms:
 *   'passengers'         — all connected passenger clients
 *   'drivers'            — all connected driver clients
 *   `user:<uid>`         — private room for targeted events
 *
 * Socket.IO events (client → server):
 *   'location.update'    — driver GPS update
 *   'driver.online'      — driver came online
 *   'driver.offline'     — driver going offline
 *   'ride.create'        — passenger requesting a ride
 *   'ride.accept'        — driver accepting a request
 *   'ride.reject'        — driver rejecting a request
 *   'ride.cancel'        — passenger or driver cancelling
 *   'ride.complete'      — driver marking ride as complete
 *   'ride_share.toggle'  — passenger toggling ride-share
 *
 * Socket.IO events (server → client) — match FastAPI WebSocket event types:
 *   'driver.presence'    — driver location / state update
 *   'driver.availability'— driver online/offline change
 *   'ride.requested'     — new ride request (to driver)
 *   'ride.matched'       — driver found (to passenger)
 *   'ride.accepted'      — driver accepted (to passenger)
 *   'ride.rejected'      — driver rejected (to passenger)
 *   'ride.cancelled'     — ride cancelled (to both parties)
 *   'ride.completed'     — ride completed (to both parties)
 *   'ride_share.updated' — co-passenger share state
 *   'error'              — error response
 */

'use strict';

const http = require('http');
const express = require('express');
const { Server: SocketIOServer } = require('socket.io');
const cors = require('cors');

const config = require('./config');
const healthRouter = require('./routes/health');
const { initFirebase, socketAuthMiddleware } = require('./middleware/firebaseAuth');
const { closePool } = require('./db/postgres');

// Services
const LocationRealtimeService = require('./services/LocationRealtimeService');
const DriverAvailabilityService = require('./services/DriverAvailabilityService');
const RideRequestService = require('./services/RideRequestService');
const BookingService = require('./services/BookingService');
const RideShareService = require('./services/RideShareService');

// ── Bootstrap ─────────────────────────────────────────────────────────────────

async function bootstrap() {
  // 1. Firebase
  initFirebase();

  // 2. Express app
  const app = express();
  app.use(cors({
    origin: config.CORS_ORIGINS.length > 0 ? config.CORS_ORIGINS : '*',
    credentials: true,
  }));
  app.use(express.json());
  app.use(healthRouter);

  // 3. HTTP server
  const httpServer = http.createServer(app);

  // 4. Socket.IO server
  const io = new SocketIOServer(httpServer, {
    cors: {
      origin: config.CORS_ORIGINS.length > 0 ? config.CORS_ORIGINS : '*',
      methods: ['GET', 'POST'],
      credentials: true,
    },
    pingInterval: 20000,
    pingTimeout: 10000,
    transports: ['websocket', 'polling'],
  });

  // 5. Auth middleware
  io.use(socketAuthMiddleware);

  // 6. Connection handler
  io.on('connection', (socket) => {
    const uid = socket.data.uid;
    console.log(`[Socket.IO] Connected: uid=${uid} socketId=${socket.id}`);

    // Join personal room for targeted events
    socket.join(`user:${uid}`);

    // ── Role-based room assignment ──────────────────────────────────────────
    const role = socket.handshake.auth?.role || socket.handshake.query?.role || 'passenger';
    socket.data.role = role;

    if (role === 'driver') {
      DriverAvailabilityService.handleDriverOnline(io, socket);
    } else {
      socket.join('passengers');
    }

    // ── Location events (driver only) ───────────────────────────────────────
    socket.on('location.update', (payload) => {
      if (socket.data.role === 'driver') {
        LocationRealtimeService.handleLocationUpdate(io, socket, payload || {});
      }
    });

    // ── Driver availability ─────────────────────────────────────────────────
    socket.on('driver.online', () => {
      DriverAvailabilityService.handleDriverOnline(io, socket);
    });

    socket.on('driver.offline', () => {
      DriverAvailabilityService.handleDriverOffline(io, uid);
    });

    // ── Ride events ─────────────────────────────────────────────────────────
    socket.on('ride.create', (payload) => {
      RideRequestService.handleRideCreate(io, socket, payload || {});
    });

    socket.on('ride.accept', (payload) => {
      BookingService.handleRideAccept(io, socket, payload || {});
    });

    socket.on('ride.reject', (payload) => {
      BookingService.handleRideReject(io, socket, payload || {});
    });

    socket.on('ride.cancel', (payload) => {
      BookingService.handleRideCancel(io, socket, payload || {});
    });

    socket.on('ride.complete', (payload) => {
      BookingService.handleRideComplete(io, socket, payload || {});
    });

    // ── Ride share ──────────────────────────────────────────────────────────
    socket.on('ride_share.toggle', (payload) => {
      RideShareService.handleRideShareToggle(io, socket, payload || {});
    });

    // ── Heartbeat (keep-alive) ──────────────────────────────────────────────
    socket.on('ping', () => {
      socket.emit('pong', { timestamp: new Date().toISOString() });
    });

    // ── Disconnect ──────────────────────────────────────────────────────────
    socket.on('disconnect', (reason) => {
      console.log(`[Socket.IO] Disconnected: uid=${uid} reason=${reason}`);
      if (socket.data.role === 'driver') {
        DriverAvailabilityService.handleDriverOffline(io, uid);
      }
    });

    // ── Error handling ──────────────────────────────────────────────────────
    socket.on('error', (err) => {
      console.error(`[Socket.IO] Socket error uid=${uid}:`, err.message);
    });
  });

  // 7. Start listening
  httpServer.listen(config.PORT, '0.0.0.0', () => {
    console.log(`✅ MyAuto Socket.IO server running on port ${config.PORT}`);
    console.log(`   Environment: ${config.APP_ENV}`);
    console.log(`   Health: http://localhost:${config.PORT}/health`);
  });

  // 8. Graceful shutdown
  const shutdown = async (signal) => {
    console.log(`\n[Server] ${signal} received — shutting down…`);
    io.close();
    httpServer.close(async () => {
      await closePool();
      console.log('[Server] Shutdown complete');
      process.exit(0);
    });
    setTimeout(() => {
      console.error('[Server] Force exit after timeout');
      process.exit(1);
    }, 10_000);
  };

  process.on('SIGTERM', () => shutdown('SIGTERM'));
  process.on('SIGINT', () => shutdown('SIGINT'));
  process.on('uncaughtException', (err) => {
    console.error('[Server] Uncaught exception:', err);
    shutdown('uncaughtException');
  });
}

bootstrap().catch((err) => {
  console.error('[Server] Bootstrap failed:', err);
  process.exit(1);
});
