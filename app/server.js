'use strict';

const express = require('express');
const client = require('prom-client');

const app = express();

// Configuration is read from the environment so the same image can run
// unchanged in local, CI and cloud environments.
const PORT = parseInt(process.env.PORT || '3000', 10);
const SERVICE_NAME = process.env.SERVICE_NAME || 'ci-container-monitoring-lab';

// ---------------------------------------------------------------------------
// Prometheus metrics
// ---------------------------------------------------------------------------
const register = new client.Registry();
register.setDefaultLabels({ service: SERVICE_NAME });
client.collectDefaultMetrics({ register });

const httpRequestsTotal = new client.Counter({
  name: 'http_requests_total',
  help: 'Total number of HTTP requests',
  labelNames: ['method', 'route', 'status'],
  registers: [register],
});

const httpRequestDuration = new client.Histogram({
  name: 'http_request_duration_seconds',
  help: 'HTTP request duration in seconds',
  labelNames: ['method', 'route', 'status'],
  buckets: [0.01, 0.05, 0.1, 0.3, 0.5, 1, 2, 5],
  registers: [register],
});

// Middleware that records metrics for every request.
app.use((req, res, next) => {
  const end = httpRequestDuration.startTimer();
  res.on('finish', () => {
    const labels = {
      method: req.method,
      route: req.path,
      status: res.statusCode,
    };
    httpRequestsTotal.inc(labels);
    end(labels);
  });
  next();
});

// ---------------------------------------------------------------------------
// Application routes
// ---------------------------------------------------------------------------
app.get('/', (req, res) => {
  res.json({
    service: SERVICE_NAME,
    version: process.env.APP_VERSION || '1.0.0',
    message: 'Hello from the DevOps Foundations lab service',
  });
});

// Liveness / readiness probe used by Docker Compose and by cloud platforms.
app.get('/health', (req, res) => {
  res.status(200).json({ status: 'ok' });
});

// Prometheus scrape endpoint.
app.get('/metrics', async (req, res) => {
  res.set('Content-Type', register.contentType);
  res.end(await register.metrics());
});

// A small amount of work so dashboards have something to show.
app.get('/work', (req, res) => {
  const iterations = Math.floor(Math.random() * 1e6);
  let acc = 0;
  for (let i = 0; i < iterations; i++) acc += i;
  res.json({ iterations, acc });
});

// Only start listening when run directly (tests import the app instead).
if (require.main === module) {
  app.listen(PORT, () => {
    console.log(`${SERVICE_NAME} listening on port ${PORT}`);
  });
}

module.exports = app;
