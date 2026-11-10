'use strict';

const http = require('http');

const PORT = parseInt(process.env.PORT || '8080', 10);
const VERSION = process.env.APP_VERSION || 'dev';
// Demo switches used in Week 3 to break a deploy on purpose.
const FAIL_HEALTH = () => process.env.FAIL_HEALTH === 'true';
const CRASH_ON_START = process.env.CRASH_ON_START === 'true';
const STARTUP_DELAY_MS = parseInt(process.env.STARTUP_DELAY_MS || '0', 10);

function send(res, status, body) {
  res.writeHead(status, { 'Content-Type': 'application/json' });
  res.end(JSON.stringify(body));
}

function createServer() {
  return http.createServer((req, res) => {
    if (req.method === 'GET' && req.url === '/health') {
      if (FAIL_HEALTH()) {
        return send(res, 500, { status: 'unhealthy', version: VERSION });
      }
      return send(res, 200, { status: 'ok', version: VERSION });
    }
    if (req.method === 'GET' && req.url === '/') {
      return send(res, 200, { service: 'canary-demo', version: VERSION });
    }
    return send(res, 404, { error: 'not found' });
  });
}

if (require.main === module) {
  if (CRASH_ON_START) {
    console.error('CRASH_ON_START=true, exiting');
    process.exit(1);
  }
  setTimeout(() => {
    const server = createServer();
    server.listen(PORT, '0.0.0.0', () => {
      console.log(`canary-demo ${VERSION} listening on :${PORT}`);
    });
    // Nomad sends SIGINT/SIGTERM on stop; exit cleanly and quickly.
    for (const sig of ['SIGINT', 'SIGTERM']) {
      process.on(sig, () => server.close(() => process.exit(0)));
    }
  }, STARTUP_DELAY_MS);
}

module.exports = { createServer };
