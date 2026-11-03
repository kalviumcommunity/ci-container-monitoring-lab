'use strict';

const assert = require('node:assert/strict');
const { after, before, test } = require('node:test');
const { once } = require('node:events');

// The health endpoint intentionally fails closed when maintenance mode is on.
process.env.MAINTENANCE_MODE = 'off';

const app = require('./server');
let server;
let baseUrl;

before(async () => {
  server = app.listen(0, '127.0.0.1');
  await once(server, 'listening');
  baseUrl = `http://127.0.0.1:${server.address().port}`;
});

after(async () => {
  if (server) {
    await new Promise((resolve, reject) => {
      server.close((error) => (error ? reject(error) : resolve()));
    });
  }
});

test('GET / returns service metadata', async () => {
  const response = await fetch(baseUrl);
  assert.equal(response.status, 200);
  const body = await response.json();
  assert.equal(body.service, 'ci-container-monitoring-lab');
  assert.ok(body.version);
});

test('GET /health reports a healthy service when maintenance is off', async () => {
  const response = await fetch(`${baseUrl}/health`);
  assert.equal(response.status, 200);
  assert.deepEqual(await response.json(), { status: 'ok' });
});

test('GET /metrics exposes Prometheus request metrics', async () => {
  const response = await fetch(`${baseUrl}/metrics`);
  assert.equal(response.status, 200);
  assert.ok(response.headers.get('content-type').includes('text/plain'));

  const metrics = await response.text();
  assert.match(metrics, /http_requests_total/);
  assert.match(metrics, /http_request_duration_seconds/);
});
