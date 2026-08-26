/**
 * Health check route.
 * GET /health → { status: "ok", timestamp: "...", service: "myauto-socketio" }
 */

const express = require('express');
const router = express.Router();

router.get('/health', (_req, res) => {
  res.json({
    status: 'ok',
    service: 'myauto-socketio',
    timestamp: new Date().toISOString(),
    uptime_seconds: Math.round(process.uptime()),
  });
});

module.exports = router;
