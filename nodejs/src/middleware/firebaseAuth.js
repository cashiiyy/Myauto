/**
 * Firebase Admin SDK — token verification middleware.
 *
 * Verifies the Firebase ID token sent by the Flutter app via the
 * Socket.IO `auth.token` field or HTTP Authorization header.
 */

const path = require('path');
const config = require('../config');

let admin;
let app;

function initFirebase() {
  if (app) return; // Already initialised
  try {
    admin = require('firebase-admin');

    // Service account path resolution:
    // In Docker: mounted at /app/secrets/serviceAccountKey.json  (docker-compose volume)
    // In local dev: path from FIREBASE_SERVICE_ACCOUNT_PATH env var
    const serviceAccountPath = config.FIREBASE_SERVICE_ACCOUNT_PATH
      ? path.resolve(config.FIREBASE_SERVICE_ACCOUNT_PATH)  // Docker container path (absolute)
      : path.resolve(__dirname, '../../../backend/secrets/serviceAccountKey.json'); // local fallback

    try {
      const serviceAccount = require(serviceAccountPath);
      app = admin.initializeApp({
        credential: admin.credential.cert(serviceAccount),
        projectId: config.FIREBASE_PROJECT_ID,
      });
      console.log('[Firebase] Initialised with service account:', serviceAccountPath);
      return;
    } catch (e) {
      console.warn(`[Firebase] Service account not found at ${serviceAccountPath}: ${e.message}`);
      console.warn('[Firebase] Trying application default credentials...');
    }

    // Fallback: application default credentials (GKE/Cloud Run)
    app = admin.initializeApp({
      projectId: config.FIREBASE_PROJECT_ID,
    });
    console.log('[Firebase] Initialised with application default credentials');
  } catch (e) {
    console.error('[Firebase] Init failed:', e.message);
    if (config.isDev) {
      console.warn('[Firebase] Running WITHOUT authentication — DEV ONLY mode active.');
      app = null;
    } else {
      console.error('[Firebase] FATAL: Firebase is required in production.');
      process.exit(1);
    }
  }
}

/**
 * Verify a Firebase ID token.
 * @param {string} token Firebase ID token from client
 * @returns {Promise<{uid: string, email?: string}|null>} Decoded token or null
 */
async function verifyToken(token) {
  if (!app || !admin) {
    // In dev mode without Firebase, allow all connections with a mock uid
    console.warn('[Firebase] No auth — returning mock uid for dev');
    return { uid: token || 'dev_uid', email: 'dev@example.com' };
  }
  try {
    const decoded = await admin.auth().verifyIdToken(token);
    return { uid: decoded.uid, email: decoded.email };
  } catch (e) {
    console.error('[Firebase] Token verification failed:', e.message);
    return null;
  }
}

/**
 * Socket.IO middleware — verifies the Firebase token from handshake auth.
 */
async function socketAuthMiddleware(socket, next) {
  const token = socket.handshake.auth?.token
    || socket.handshake.query?.token;

  if (!token) {
    return next(new Error('Authentication token missing'));
  }

  const decoded = await verifyToken(token);
  if (!decoded) {
    return next(new Error('Invalid or expired token'));
  }

  // Attach uid to the socket for downstream use
  socket.data.uid = decoded.uid;
  socket.data.email = decoded.email;
  next();
}

module.exports = { initFirebase, verifyToken, socketAuthMiddleware };
