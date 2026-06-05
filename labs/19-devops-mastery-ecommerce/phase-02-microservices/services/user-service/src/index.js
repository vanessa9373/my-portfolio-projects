"use strict";

/**
 * User Service
 *
 * Handles user registration, authentication, and profile management.
 * - Passwords hashed with bcrypt
 * - JWT-based authentication
 * - Redis caching for user profiles
 * - PostgreSQL for persistent storage
 * - Health check endpoints for orchestrator probes
 */

const express = require("express");
const { Pool } = require("pg");
const { createClient } = require("redis");
const bcrypt = require("bcrypt");
const jwt = require("jsonwebtoken");
const helmet = require("helmet");
const cors = require("cors");

// ---------------------------------------------------------------------------
// Configuration
// ---------------------------------------------------------------------------

const PORT = parseInt(process.env.PORT, 10) || 3001;
const DATABASE_URL = process.env.DATABASE_URL || "postgresql://app:password@localhost:5432/users";
const REDIS_URL = process.env.REDIS_URL || "redis://localhost:6379";
const JWT_SECRET = process.env.JWT_SECRET || "dev-secret-change-in-production";
const BCRYPT_ROUNDS = 10;
const CACHE_TTL = 300; // 5 minutes

// ---------------------------------------------------------------------------
// Structured logger
// ---------------------------------------------------------------------------

const logger = {
  info: (msg, meta = {}) =>
    console.log(JSON.stringify({ level: "info", service: "user-service", msg, ...meta, ts: new Date().toISOString() })),
  warn: (msg, meta = {}) =>
    console.log(JSON.stringify({ level: "warn", service: "user-service", msg, ...meta, ts: new Date().toISOString() })),
  error: (msg, meta = {}) =>
    console.error(JSON.stringify({ level: "error", service: "user-service", msg, ...meta, ts: new Date().toISOString() })),
};

// ---------------------------------------------------------------------------
// Database and cache clients
// ---------------------------------------------------------------------------

const pool = new Pool({ connectionString: DATABASE_URL });

const redis = createClient({ url: REDIS_URL });
redis.on("error", (err) => logger.error("redis_error", { message: err.message }));

// ---------------------------------------------------------------------------
// Database initialization — create tables if they do not exist
// ---------------------------------------------------------------------------

async function initDatabase() {
  const client = await pool.connect();
  try {
    await client.query(`
      CREATE TABLE IF NOT EXISTS users (
        id            SERIAL PRIMARY KEY,
        email         VARCHAR(255) UNIQUE NOT NULL,
        password_hash VARCHAR(255) NOT NULL,
        name          VARCHAR(255) NOT NULL,
        created_at    TIMESTAMP DEFAULT NOW(),
        updated_at    TIMESTAMP DEFAULT NOW()
      );
    `);
    logger.info("Database tables initialized");
  } finally {
    client.release();
  }
}

// ---------------------------------------------------------------------------
// JWT helpers
// ---------------------------------------------------------------------------

function generateToken(user) {
  return jwt.sign({ id: user.id, email: user.email }, JWT_SECRET, { expiresIn: "24h" });
}

// Middleware: verify JWT and attach user payload to req.user
function authenticate(req, res, next) {
  const header = req.headers.authorization;
  if (!header || !header.startsWith("Bearer ")) {
    return res.status(401).json({ error: "Authentication required" });
  }
  try {
    req.user = jwt.verify(header.split(" ")[1], JWT_SECRET);
    next();
  } catch {
    return res.status(401).json({ error: "Invalid or expired token" });
  }
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

app.get("/health", (_req, res) => res.json({ status: "ok", service: "user-service" }));

app.get("/health/live", (_req, res) => res.json({ status: "alive" }));

app.get("/health/ready", async (_req, res) => {
  try {
    await pool.query("SELECT 1");
    await redis.ping();
    res.json({ status: "ready" });
  } catch (err) {
    logger.error("readiness_check_failed", { message: err.message });
    res.status(503).json({ status: "not ready", error: err.message });
  }
});

// ---------------------------------------------------------------------------
// Auth routes
// ---------------------------------------------------------------------------

// POST /api/auth/register — create a new user account
app.post("/api/auth/register", async (req, res, next) => {
  try {
    const { email, password, name } = req.body;
    if (!email || !password || !name) {
      return res.status(400).json({ error: "email, password, and name are required" });
    }

    const passwordHash = await bcrypt.hash(password, BCRYPT_ROUNDS);

    const result = await pool.query(
      "INSERT INTO users (email, password_hash, name) VALUES ($1, $2, $3) RETURNING id, email, name, created_at",
      [email, passwordHash, name]
    );

    const user = result.rows[0];
    const token = generateToken(user);

    logger.info("user_registered", { userId: user.id });
    res.status(201).json({ user, token });
  } catch (err) {
    // Handle unique constraint violation
    if (err.code === "23505") {
      return res.status(409).json({ error: "Email already registered" });
    }
    next(err);
  }
});

// POST /api/auth/login — authenticate and return JWT
app.post("/api/auth/login", async (req, res, next) => {
  try {
    const { email, password } = req.body;
    if (!email || !password) {
      return res.status(400).json({ error: "email and password are required" });
    }

    const result = await pool.query("SELECT * FROM users WHERE email = $1", [email]);
    const user = result.rows[0];

    if (!user || !(await bcrypt.compare(password, user.password_hash))) {
      return res.status(401).json({ error: "Invalid credentials" });
    }

    const token = generateToken(user);

    // Cache user profile
    await redis.set(`user:${user.id}`, JSON.stringify({ id: user.id, email: user.email, name: user.name }), { EX: CACHE_TTL });

    logger.info("user_logged_in", { userId: user.id });
    res.json({ user: { id: user.id, email: user.email, name: user.name }, token });
  } catch (err) {
    next(err);
  }
});

// ---------------------------------------------------------------------------
// User profile routes (protected)
// ---------------------------------------------------------------------------

// GET /api/users/me — get current user profile
app.get("/api/users/me", authenticate, async (req, res, next) => {
  try {
    // Check Redis cache first
    const cached = await redis.get(`user:${req.user.id}`);
    if (cached) {
      return res.json({ user: JSON.parse(cached), source: "cache" });
    }

    const result = await pool.query(
      "SELECT id, email, name, created_at, updated_at FROM users WHERE id = $1",
      [req.user.id]
    );
    if (result.rows.length === 0) {
      return res.status(404).json({ error: "User not found" });
    }

    const user = result.rows[0];

    // Populate cache
    await redis.set(`user:${user.id}`, JSON.stringify(user), { EX: CACHE_TTL });

    res.json({ user, source: "db" });
  } catch (err) {
    next(err);
  }
});

// PUT /api/users/me — update current user profile
app.put("/api/users/me", authenticate, async (req, res, next) => {
  try {
    const { name, email } = req.body;
    if (!name && !email) {
      return res.status(400).json({ error: "Provide at least name or email to update" });
    }

    const fields = [];
    const values = [];
    let idx = 1;

    if (name) {
      fields.push(`name = $${idx++}`);
      values.push(name);
    }
    if (email) {
      fields.push(`email = $${idx++}`);
      values.push(email);
    }
    fields.push(`updated_at = NOW()`);
    values.push(req.user.id);

    const query = `UPDATE users SET ${fields.join(", ")} WHERE id = $${idx} RETURNING id, email, name, updated_at`;
    const result = await pool.query(query, values);

    if (result.rows.length === 0) {
      return res.status(404).json({ error: "User not found" });
    }

    const user = result.rows[0];

    // Invalidate cache
    await redis.del(`user:${user.id}`);

    logger.info("user_updated", { userId: user.id });
    res.json({ user });
  } catch (err) {
    if (err.code === "23505") {
      return res.status(409).json({ error: "Email already in use" });
    }
    next(err);
  }
});

// DELETE /api/users/me — delete current user account
app.delete("/api/users/me", authenticate, async (req, res, next) => {
  try {
    await pool.query("DELETE FROM users WHERE id = $1", [req.user.id]);
    await redis.del(`user:${req.user.id}`);

    logger.info("user_deleted", { userId: req.user.id });
    res.status(204).end();
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
// Start server
// ---------------------------------------------------------------------------

async function start() {
  try {
    await redis.connect();
    logger.info("Connected to Redis");

    await initDatabase();
    logger.info("Connected to PostgreSQL");

    const server = app.listen(PORT, () => {
      logger.info(`User service listening on port ${PORT}`);
    });

    // Graceful shutdown
    const shutdown = async (signal) => {
      logger.info(`Received ${signal} — shutting down`);
      server.close(async () => {
        await redis.quit();
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
