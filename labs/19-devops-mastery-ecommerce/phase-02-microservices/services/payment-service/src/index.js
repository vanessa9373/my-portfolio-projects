"use strict";

/**
 * Payment Service
 *
 * Processes payments for orders with:
 * - Idempotency key support (prevents duplicate charges)
 * - RabbitMQ event consumption (order.created) and publishing (payment.completed / payment.failed)
 * - PostgreSQL persistence for payment records
 * - Simulated payment processing (no real payment gateway)
 */

const express = require("express");
const { Pool } = require("pg");
const amqplib = require("amqplib");
const { v4: uuidv4 } = require("uuid");
const helmet = require("helmet");
const cors = require("cors");

// ---------------------------------------------------------------------------
// Configuration
// ---------------------------------------------------------------------------

const PORT = parseInt(process.env.PORT, 10) || 3004;
const DATABASE_URL = process.env.DATABASE_URL || "postgresql://app:password@localhost:5432/payments";
const RABBITMQ_URL = process.env.RABBITMQ_URL || "amqp://localhost:5672";
const EXCHANGE_NAME = "ecommerce.events";

// ---------------------------------------------------------------------------
// Structured logger
// ---------------------------------------------------------------------------

const logger = {
  info: (msg, meta = {}) =>
    console.log(JSON.stringify({ level: "info", service: "payment-service", msg, ...meta, ts: new Date().toISOString() })),
  warn: (msg, meta = {}) =>
    console.log(JSON.stringify({ level: "warn", service: "payment-service", msg, ...meta, ts: new Date().toISOString() })),
  error: (msg, meta = {}) =>
    console.error(JSON.stringify({ level: "error", service: "payment-service", msg, ...meta, ts: new Date().toISOString() })),
};

// ---------------------------------------------------------------------------
// Database
// ---------------------------------------------------------------------------

const pool = new Pool({ connectionString: DATABASE_URL });

async function initDatabase() {
  const client = await pool.connect();
  try {
    await client.query(`
      CREATE TABLE IF NOT EXISTS payments (
        id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
        order_id        UUID NOT NULL,
        idempotency_key UUID UNIQUE NOT NULL,
        amount          NUMERIC(10, 2) NOT NULL,
        currency        VARCHAR(3) NOT NULL DEFAULT 'USD',
        status          VARCHAR(20) NOT NULL DEFAULT 'PENDING',
        method          VARCHAR(50) DEFAULT 'credit_card',
        created_at      TIMESTAMP DEFAULT NOW(),
        updated_at      TIMESTAMP DEFAULT NOW()
      );

      CREATE INDEX IF NOT EXISTS idx_payments_order_id ON payments (order_id);
      CREATE INDEX IF NOT EXISTS idx_payments_idempotency ON payments (idempotency_key);
    `);
    logger.info("Database tables initialized");
  } finally {
    client.release();
  }
}

// ---------------------------------------------------------------------------
// RabbitMQ
// ---------------------------------------------------------------------------

let amqpChannel = null;

async function connectRabbitMQ() {
  const connection = await amqplib.connect(RABBITMQ_URL);
  amqpChannel = await connection.createChannel();

  // Declare shared exchange
  await amqpChannel.assertExchange(EXCHANGE_NAME, "topic", { durable: true });

  // Queue for consuming order events
  const { queue } = await amqpChannel.assertQueue("payment-service.orders", { durable: true });
  await amqpChannel.bindQueue(queue, EXCHANGE_NAME, "order.created");

  // Process one message at a time to avoid overloading
  amqpChannel.prefetch(1);

  amqpChannel.consume(queue, async (msg) => {
    if (!msg) return;
    try {
      const event = JSON.parse(msg.content.toString());
      await processOrderEvent(event);
      amqpChannel.ack(msg);
    } catch (err) {
      logger.error("Failed to process order event", { message: err.message });
      amqpChannel.nack(msg, false, true);
    }
  });

  logger.info("Connected to RabbitMQ and consuming order events");
  return connection;
}

/**
 * Handle an incoming order.created event:
 * - Simulate payment processing
 * - Persist payment record
 * - Publish payment result
 */
async function processOrderEvent(event) {
  const { orderId, userId, total } = event;
  if (!orderId || total == null) {
    logger.warn("Malformed order event — skipping", { event });
    return;
  }

  // Use orderId as the idempotency key for auto-triggered payments
  const idempotencyKey = orderId;

  // Check if we already processed this payment (idempotency)
  const existing = await pool.query("SELECT id, status FROM payments WHERE idempotency_key = $1", [idempotencyKey]);
  if (existing.rows.length > 0) {
    logger.info("Duplicate payment detected — skipping", { orderId, paymentId: existing.rows[0].id });
    return;
  }

  // Simulate payment processing (succeed for amounts under 10000, fail above)
  const paymentSucceeded = total < 10000;
  const status = paymentSucceeded ? "COMPLETED" : "FAILED";

  const result = await pool.query(
    `INSERT INTO payments (order_id, idempotency_key, amount, status)
     VALUES ($1, $2, $3, $4)
     RETURNING id, order_id, amount, status, created_at`,
    [orderId, idempotencyKey, total, status]
  );

  const payment = result.rows[0];
  logger.info("payment_processed", { paymentId: payment.id, orderId, status, amount: total });

  // Publish payment result for the order service (saga completion)
  const routingKey = paymentSucceeded ? "payment.completed" : "payment.failed";
  publishEvent(routingKey, {
    paymentId: payment.id,
    orderId,
    userId,
    amount: total,
    status,
    processedAt: new Date().toISOString(),
  });
}

function publishEvent(routingKey, payload) {
  if (!amqpChannel) {
    logger.warn("RabbitMQ channel not available", { routingKey });
    return;
  }
  amqpChannel.publish(EXCHANGE_NAME, routingKey, Buffer.from(JSON.stringify(payload)), {
    persistent: true,
    contentType: "application/json",
  });
  logger.info("event_published", { routingKey });
}

// ---------------------------------------------------------------------------
// Express application
// ---------------------------------------------------------------------------

const app = express();
app.use(helmet());
app.use(cors());
app.use(express.json());

// Request logging
app.use((req, res, next) => {
  const start = Date.now();
  res.on("finish", () => {
    logger.info("request", {
      method: req.method,
      path: req.originalUrl,
      status: res.statusCode,
      duration_ms: Date.now() - start,
    });
  });
  next();
});

// ---------------------------------------------------------------------------
// Health endpoints
// ---------------------------------------------------------------------------

app.get("/health", (_req, res) => res.json({ status: "ok", service: "payment-service" }));
app.get("/health/live", (_req, res) => res.json({ status: "alive" }));

app.get("/health/ready", async (_req, res) => {
  try {
    await pool.query("SELECT 1");
    if (!amqpChannel) throw new Error("RabbitMQ channel not ready");
    res.json({ status: "ready" });
  } catch (err) {
    logger.error("readiness_check_failed", { message: err.message });
    res.status(503).json({ status: "not ready", error: err.message });
  }
});

// ---------------------------------------------------------------------------
// Payment routes
// ---------------------------------------------------------------------------

// POST /api/payments — manually trigger a payment (with idempotency key)
app.post("/api/payments", async (req, res, next) => {
  try {
    const { orderId, amount, currency = "USD", method = "credit_card", idempotencyKey } = req.body;

    if (!orderId || amount == null || !idempotencyKey) {
      return res.status(400).json({ error: "orderId, amount, and idempotencyKey are required" });
    }

    // Idempotency check — return existing payment if key already used
    const existing = await pool.query(
      "SELECT id, order_id, amount, currency, status, method, created_at FROM payments WHERE idempotency_key = $1",
      [idempotencyKey]
    );
    if (existing.rows.length > 0) {
      logger.info("idempotent_hit", { idempotencyKey });
      return res.status(200).json({ payment: existing.rows[0], idempotent: true });
    }

    // Simulate processing
    const paymentSucceeded = amount < 10000;
    const status = paymentSucceeded ? "COMPLETED" : "FAILED";

    const result = await pool.query(
      `INSERT INTO payments (order_id, idempotency_key, amount, currency, status, method)
       VALUES ($1, $2, $3, $4, $5, $6)
       RETURNING id, order_id, amount, currency, status, method, created_at`,
      [orderId, idempotencyKey, amount, currency, status, method]
    );

    const payment = result.rows[0];

    // Publish event
    const routingKey = paymentSucceeded ? "payment.completed" : "payment.failed";
    publishEvent(routingKey, {
      paymentId: payment.id,
      orderId,
      amount,
      status,
      processedAt: new Date().toISOString(),
    });

    logger.info("payment_created", { paymentId: payment.id, orderId, status });
    res.status(201).json({ payment });
  } catch (err) {
    if (err.code === "23505") {
      return res.status(409).json({ error: "Duplicate idempotency key" });
    }
    next(err);
  }
});

// GET /api/payments/:id — retrieve a payment by ID
app.get("/api/payments/:id", async (req, res, next) => {
  try {
    const result = await pool.query(
      "SELECT id, order_id, amount, currency, status, method, created_at, updated_at FROM payments WHERE id = $1",
      [req.params.id]
    );
    if (result.rows.length === 0) {
      return res.status(404).json({ error: "Payment not found" });
    }
    res.json({ payment: result.rows[0] });
  } catch (err) {
    next(err);
  }
});

// GET /api/payments?orderId=xxx — list payments for an order
app.get("/api/payments", async (req, res, next) => {
  try {
    const { orderId, limit = 20, offset = 0 } = req.query;

    let query, params;
    if (orderId) {
      query = `SELECT id, order_id, amount, currency, status, method, created_at
               FROM payments WHERE order_id = $1
               ORDER BY created_at DESC LIMIT $2 OFFSET $3`;
      params = [orderId, parseInt(limit, 10), parseInt(offset, 10)];
    } else {
      query = `SELECT id, order_id, amount, currency, status, method, created_at
               FROM payments ORDER BY created_at DESC LIMIT $1 OFFSET $2`;
      params = [parseInt(limit, 10), parseInt(offset, 10)];
    }

    const result = await pool.query(query, params);
    res.json({ payments: result.rows });
  } catch (err) {
    next(err);
  }
});

// ---------------------------------------------------------------------------
// Error handling middleware
// ---------------------------------------------------------------------------

app.use((err, _req, res, _next) => {
  logger.error("unhandled_error", { message: err.message, stack: err.stack });
  if (!res.headersSent) {
    res.status(500).json({ error: "Internal server error" });
  }
});

// ---------------------------------------------------------------------------
// Startup
// ---------------------------------------------------------------------------

let amqpConnection = null;

async function start() {
  try {
    await initDatabase();

    // Retry RabbitMQ connection
    let retries = 10;
    while (retries > 0) {
      try {
        amqpConnection = await connectRabbitMQ();
        break;
      } catch (err) {
        retries--;
        logger.warn(`RabbitMQ not ready, retrying (${retries} left)...`);
        await new Promise((r) => setTimeout(r, 3000));
      }
    }
    if (!amqpConnection) throw new Error("Could not connect to RabbitMQ after retries");

    const server = app.listen(PORT, () => {
      logger.info(`Payment service listening on port ${PORT}`);
    });

    // Graceful shutdown
    const shutdown = async (signal) => {
      logger.info(`Received ${signal} — shutting down`);
      server.close(async () => {
        if (amqpChannel) await amqpChannel.close();
        if (amqpConnection) await amqpConnection.close();
        await pool.end();
        logger.info("Connections closed");
        process.exit(0);
      });
      setTimeout(() => process.exit(1), 10_000);
    };

    process.on("SIGTERM", () => shutdown("SIGTERM"));
    process.on("SIGINT", () => shutdown("SIGINT"));
  } catch (err) {
    logger.error("startup_failed", { message: err.message });
    process.exit(1);
  }
}

start();
