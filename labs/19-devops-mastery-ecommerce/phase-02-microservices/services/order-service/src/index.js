"use strict";

/**
 * Order Service
 *
 * Manages order lifecycle with a simplified saga pattern:
 *   1. Client creates an order (status: PENDING)
 *   2. Service publishes "order.created" event to RabbitMQ
 *   3. Payment service processes payment and publishes result
 *   4. Order service consumes "payment.completed" / "payment.failed"
 *      and transitions the order accordingly.
 *
 * Persistence: PostgreSQL
 * Messaging:   RabbitMQ (topic exchange)
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

const PORT = parseInt(process.env.PORT, 10) || 3003;
const DATABASE_URL = process.env.DATABASE_URL || "postgresql://app:password@localhost:5432/orders";
const RABBITMQ_URL = process.env.RABBITMQ_URL || "amqp://localhost:5672";
const EXCHANGE_NAME = "ecommerce.events";

// ---------------------------------------------------------------------------
// Structured logger
// ---------------------------------------------------------------------------

const logger = {
  info: (msg, meta = {}) =>
    console.log(JSON.stringify({ level: "info", service: "order-service", msg, ...meta, ts: new Date().toISOString() })),
  warn: (msg, meta = {}) =>
    console.log(JSON.stringify({ level: "warn", service: "order-service", msg, ...meta, ts: new Date().toISOString() })),
  error: (msg, meta = {}) =>
    console.error(JSON.stringify({ level: "error", service: "order-service", msg, ...meta, ts: new Date().toISOString() })),
};

// ---------------------------------------------------------------------------
// Database client
// ---------------------------------------------------------------------------

const pool = new Pool({ connectionString: DATABASE_URL });

async function initDatabase() {
  const client = await pool.connect();
  try {
    await client.query(`
      CREATE TABLE IF NOT EXISTS orders (
        id         UUID PRIMARY KEY,
        user_id    INTEGER NOT NULL,
        items      JSONB NOT NULL DEFAULT '[]',
        total      NUMERIC(10, 2) NOT NULL DEFAULT 0,
        status     VARCHAR(20) NOT NULL DEFAULT 'PENDING',
        created_at TIMESTAMP DEFAULT NOW(),
        updated_at TIMESTAMP DEFAULT NOW()
      );
    `);
    logger.info("Database tables initialized");
  } finally {
    client.release();
  }
}

// ---------------------------------------------------------------------------
// RabbitMQ setup
// ---------------------------------------------------------------------------

let amqpChannel = null;

async function connectRabbitMQ() {
  const connection = await amqplib.connect(RABBITMQ_URL);
  amqpChannel = await connection.createChannel();

  // Declare a topic exchange shared across services
  await amqpChannel.assertExchange(EXCHANGE_NAME, "topic", { durable: true });

  // Queue for consuming payment results
  const { queue } = await amqpChannel.assertQueue("order-service.payment-results", { durable: true });
  await amqpChannel.bindQueue(queue, EXCHANGE_NAME, "payment.completed");
  await amqpChannel.bindQueue(queue, EXCHANGE_NAME, "payment.failed");

  // Consume payment events to complete the saga
  amqpChannel.consume(queue, async (msg) => {
    if (!msg) return;
    try {
      const event = JSON.parse(msg.content.toString());
      await handlePaymentEvent(event, msg.fields.routingKey);
      amqpChannel.ack(msg);
    } catch (err) {
      logger.error("Failed to process payment event", { message: err.message });
      // Negative-acknowledge so the message is requeued
      amqpChannel.nack(msg, false, true);
    }
  });

  logger.info("Connected to RabbitMQ and consuming payment events");
  return connection;
}

/**
 * Saga handler: transition order status based on payment outcome.
 */
async function handlePaymentEvent(event, routingKey) {
  const { orderId } = event;
  if (!orderId) return;

  const newStatus = routingKey === "payment.completed" ? "PAID" : "PAYMENT_FAILED";

  const result = await pool.query(
    "UPDATE orders SET status = $1, updated_at = NOW() WHERE id = $2 RETURNING id, status",
    [newStatus, orderId]
  );

  if (result.rows.length > 0) {
    logger.info("order_status_updated", { orderId, status: newStatus });

    // Publish order status change event
    const statusEvent = { orderId, status: newStatus, updatedAt: new Date().toISOString() };
    amqpChannel.publish(
      EXCHANGE_NAME,
      `order.${newStatus.toLowerCase()}`,
      Buffer.from(JSON.stringify(statusEvent)),
      { persistent: true }
    );
  }
}

/**
 * Publish an event to the exchange.
 */
function publishEvent(routingKey, payload) {
  if (!amqpChannel) {
    logger.warn("RabbitMQ channel not available — event dropped", { routingKey });
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

app.get("/health", (_req, res) => res.json({ status: "ok", service: "order-service" }));
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
// Order routes
// ---------------------------------------------------------------------------

// POST /api/orders — create a new order
app.post("/api/orders", async (req, res, next) => {
  try {
    const { userId, items } = req.body;
    if (!userId || !Array.isArray(items) || items.length === 0) {
      return res.status(400).json({ error: "userId and a non-empty items array are required" });
    }

    // Calculate total from items (each item: { productId, name, price, quantity })
    const total = items.reduce((sum, item) => sum + (item.price || 0) * (item.quantity || 1), 0);
    const orderId = uuidv4();

    const result = await pool.query(
      `INSERT INTO orders (id, user_id, items, total, status)
       VALUES ($1, $2, $3, $4, 'PENDING')
       RETURNING id, user_id, items, total, status, created_at`,
      [orderId, userId, JSON.stringify(items), total]
    );

    const order = result.rows[0];

    // Publish order.created event for downstream services (payment, inventory, etc.)
    publishEvent("order.created", {
      orderId: order.id,
      userId: order.user_id,
      items,
      total: parseFloat(order.total),
      createdAt: order.created_at,
    });

    logger.info("order_created", { orderId: order.id, userId, total });
    res.status(201).json({ order });
  } catch (err) {
    next(err);
  }
});

// GET /api/orders/:id — retrieve a single order
app.get("/api/orders/:id", async (req, res, next) => {
  try {
    const result = await pool.query(
      "SELECT id, user_id, items, total, status, created_at, updated_at FROM orders WHERE id = $1",
      [req.params.id]
    );
    if (result.rows.length === 0) {
      return res.status(404).json({ error: "Order not found" });
    }
    res.json({ order: result.rows[0] });
  } catch (err) {
    next(err);
  }
});

// GET /api/orders?userId=123 — list orders for a user
app.get("/api/orders", async (req, res, next) => {
  try {
    const { userId, status, limit = 20, offset = 0 } = req.query;

    const conditions = [];
    const params = [];
    let idx = 1;

    if (userId) {
      conditions.push(`user_id = $${idx++}`);
      params.push(parseInt(userId, 10));
    }
    if (status) {
      conditions.push(`status = $${idx++}`);
      params.push(status.toUpperCase());
    }

    const where = conditions.length ? `WHERE ${conditions.join(" AND ")}` : "";
    params.push(parseInt(limit, 10), parseInt(offset, 10));

    const query = `
      SELECT id, user_id, items, total, status, created_at, updated_at
      FROM orders ${where}
      ORDER BY created_at DESC
      LIMIT $${idx++} OFFSET $${idx}
    `;

    const result = await pool.query(query, params);
    res.json({ orders: result.rows });
  } catch (err) {
    next(err);
  }
});

// PATCH /api/orders/:id/cancel — cancel an order (only if still PENDING)
app.patch("/api/orders/:id/cancel", async (req, res, next) => {
  try {
    const result = await pool.query(
      `UPDATE orders SET status = 'CANCELLED', updated_at = NOW()
       WHERE id = $1 AND status = 'PENDING'
       RETURNING id, status, updated_at`,
      [req.params.id]
    );

    if (result.rows.length === 0) {
      return res.status(409).json({ error: "Order cannot be cancelled (not found or not in PENDING status)" });
    }

    publishEvent("order.cancelled", { orderId: req.params.id });

    logger.info("order_cancelled", { orderId: req.params.id });
    res.json({ order: result.rows[0] });
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

    // Retry RabbitMQ connection (it may take a few seconds to start)
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

    if (!amqpConnection) {
      throw new Error("Could not connect to RabbitMQ after retries");
    }

    const server = app.listen(PORT, () => {
      logger.info(`Order service listening on port ${PORT}`);
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
