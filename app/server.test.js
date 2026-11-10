'use strict';

const test = require('node:test');
const assert = require('node:assert');
const http = require('http');
const { createServer } = require('./server');

function get(port, path) {
  return new Promise((resolve, reject) => {
    http.get({ port, path, host: '127.0.0.1' }, (res) => {
      let data = '';
      res.on('data', (c) => (data += c));
      res.on('end', () => resolve({ status: res.statusCode, body: JSON.parse(data) }));
    }).on('error', reject);
  });
}

test('/health returns 200 by default and 500 when FAIL_HEALTH=true', async () => {
  const server = createServer();
  await new Promise((r) => server.listen(0, '127.0.0.1', r));
  const { port } = server.address();

  delete process.env.FAIL_HEALTH;
  let res = await get(port, '/health');
  assert.strictEqual(res.status, 200);
  assert.strictEqual(res.body.status, 'ok');

  process.env.FAIL_HEALTH = 'true';
  res = await get(port, '/health');
  assert.strictEqual(res.status, 500);

  delete process.env.FAIL_HEALTH;
  server.close();
});

test('unknown route returns 404', async () => {
  const server = createServer();
  await new Promise((r) => server.listen(0, '127.0.0.1', r));
  const res = await get(server.address().port, '/nope');
  assert.strictEqual(res.status, 404);
  server.close();
});
