"use strict";

/**
 * API Gateway Service
 *
 * Central entry point for the e-commerce platform. Provides:
 * - Reverse proxy routing to downstream microservices
 * - Rate limiting per IP
 * - Request logging with structured JSON output
 * - Health check endpoints for Kubernetes probes
 * - Graceful shutdown handling
 */

const express = require("express");
const { createProxyMiddleware } = require("http-proxy-middleware");
const rateLimit = require("express-rate-limit");
const helmet = require("helmet");
const cors = require("cors");

// ---------------------------------------------------------------------------
// Configuration
// ---------------------------------------------------------------------------

const PORT = parseInt(process.env.PORT, 10) || 3000;
const USER_SERVICE_URL =
  process.env.USER_SERVICE_URL || "http://localhost:3001";
const PRODUCT_SERVICE_URL =
  process.env.PRODUCT_SERVICE_URL || "http://localhost:8000";
const ORDER_SERVICE_URL =
  process.env.ORDER_SERVICE_URL || "http://localhost:3003";

// ---------------------------------------------------------------------------
// Structured logger (writes JSON to stdout)
// ---------------------------------------------------------------------------

const logger = {
  info: (msg, meta = {}) =>
    console.log(
      JSON.stringify({ level: "info", service: "api-gateway", msg, ...meta, ts: new Date().toISOString() })
    ),
  warn: (msg, meta = {}) =>
    console.log(
      JSON.stringify({ level: "warn", service: "api-gateway", msg, ...meta, ts: new Date().toISOString() })
    ),
  error: (msg, meta = {}) =>
    console.error(
      JSON.stringify({ level: "error", service: "api-gateway", msg, ...meta, ts: new Date().toISOString() })
    ),
};

// ---------------------------------------------------------------------------
// Express application
// ---------------------------------------------------------------------------

const app = express();

// Security headers
app.use(helmet());

// CORS — allow all origins in dev; tighten in production
app.use(cors());

// Parse JSON bodies (needed for some non-proxy routes)
app.use(express.json());

// ---------------------------------------------------------------------------
// Request logging middleware (structured JSON)
// ---------------------------------------------------------------------------

app.use((req, res, next) => {
  const start = Date.now();
  res.on("finish", () => {
    logger.info("request", {
      method: req.method,
      path: req.originalUrl,
      status: res.statusCode,
      duration_ms: Date.now() - start,
      ip: req.ip,
    });
  });
  next();
});

// ---------------------------------------------------------------------------
// Rate limiting — 100 requests per 15-minute window per IP
// ---------------------------------------------------------------------------

const limiter = rateLimit({
  windowMs: 15 * 60 * 1000,
  max: 100,
  standardHeaders: true,
  legacyHeaders: false,
  message: { error: "Too many requests, please try again later." },
});

app.use("/api/", limiter);

// ---------------------------------------------------------------------------
// Health check endpoints (Kubernetes liveness / readiness probes)
// ---------------------------------------------------------------------------

app.get("/health", (_req, res) => {
  res.json({ status: "ok", service: "api-gateway" });
});

app.get("/health/live", (_req, res) => {
  res.json({ status: "alive" });
});

app.get("/health/ready", (_req, res) => {
  // The gateway itself is stateless — it is ready once it can accept TCP.
  res.json({ status: "ready" });
});

// ---------------------------------------------------------------------------
// Proxy routes — forward to downstream microservices
// ---------------------------------------------------------------------------

// Helper: create a proxy middleware for a given target
const proxy = (target) =>
  createProxyMiddleware({
    target,
    changeOrigin: true,
    // Timeout for proxy connections (10 s connect, 30 s response)
    proxyTimeout: 30_000,
    timeout: 10_000,
    onError: (err, _req, res) => {
      logger.error("proxy_error", { target, message: err.message });
      if (!res.headersSent) {
        res.status(502).json({ error: "Bad gateway — downstream service unavailable" });
      }
    },
  });

// Route traffic by URL prefix
app.use("/api/users", proxy(USER_SERVICE_URL));
app.use("/api/auth", proxy(USER_SERVICE_URL));
app.use("/api/products", proxy(PRODUCT_SERVICE_URL));
app.use("/api/orders", proxy(ORDER_SERVICE_URL));

// ---------------------------------------------------------------------------
// 404 handler
// ---------------------------------------------------------------------------

app.use((_req, res) => {
  res.status(404).json({ error: "Route not found" });
});

// ---------------------------------------------------------------------------
// Global error handler
// ---------------------------------------------------------------------------

app.use((err, _req, res, _next) => {
  logger.error("unhandled_error", { message: err.message, stack: err.stack });
  if (!res.headersSent) {
    res.status(500).json({ error: "Internal server error" });
  }
});

// ---------------------------------------------------------------------------
// Start server with graceful shutdown
// ---------------------------------------------------------------------------

const server = app.listen(PORT, () => {
  logger.info(`API Gateway listening on port ${PORT}`);
});

// Graceful shutdown: stop accepting connections, then exit
const shutdown = (signal) => {
  logger.info(`Received ${signal} — shutting down gracefully`);
  server.close(() => {
    logger.info("HTTP server closed");
    process.exit(0);
  });
  // Force exit after 10 seconds if connections linger
  setTimeout(() => {
    logger.warn("Forcing shutdown after timeout");
    process.exit(1);
  }, 10_000);
};

process.on("SIGTERM", () => shutdown("SIGTERM"));
process.on("SIGINT", () => shutdown("SIGINT"));
