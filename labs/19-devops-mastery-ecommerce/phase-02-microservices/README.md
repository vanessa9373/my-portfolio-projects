# Phase 2: Application Development (Microservices)

**Difficulty:** Beginner | **Time:** 6-8 hours | **Prerequisites:** Phase 1

---

## Table of Contents

1. [Overview](#1-overview)
2. [Prerequisites](#2-prerequisites)
3. [Step-by-Step Implementation](#3-step-by-step-implementation)
4. [Configuration Walkthrough](#4-configuration-walkthrough)
5. [Verification Checklist](#5-verification-checklist)
6. [Troubleshooting](#6-troubleshooting)
7. [Key Decisions & Trade-offs](#7-key-decisions--trade-offs)
8. [Production Considerations](#8-production-considerations)
9. [Next Phase](#9-next-phase)

---

## 1. Overview

This phase builds the 6 microservices that form the e-commerce platform. Each service owns a specific business domain, uses its own database (database-per-service pattern), and communicates via REST APIs and RabbitMQ events.

### Service Architecture

```
                         ┌──────────────┐
                         │  API Gateway │ :3000
                         │  (Node.js)   │
                         └──────┬───────┘
                    ┌───────────┼───────────┐
                    ▼           ▼           ▼
            ┌──────────┐ ┌──────────┐ ┌──────────┐
            │  User    │ │ Product  │ │  Order   │
            │ Service  │ │ Service  │ │ Service  │
            │ :3001    │ │ :8000    │ │ :3003    │
            └────┬─────┘ └────┬─────┘ └────┬─────┘
                 │            │            │
            ┌────┴─────┐ ┌───┴──────┐ ┌───┴──────┐
            │PostgreSQL│ │PostgreSQL│ │PostgreSQL│
            │  + Redis │ │  + Redis │ │          │
            └──────────┘ └──────────┘ └──────────┘
                                           │
                              ┌────────────┤ (RabbitMQ)
                              ▼            ▼
                       ┌──────────┐ ┌──────────────┐
                       │ Payment  │ │ Notification │
                       │ Service  │ │ Service      │
                       │ :3004    │ │ (consumer)   │
                       └────┬─────┘ └──────────────┘
                       ┌────┴─────┐
                       │PostgreSQL│
                       └──────────┘
```

### Service Responsibilities

| Service | Language | Port | Database | Purpose |
|---------|----------|------|----------|---------|
| API Gateway | Node.js/Express | 3000 | — | Routing, rate limiting, JWT validation |
| User Service | Node.js | 3001 | PostgreSQL + Redis | Authentication, user profiles |
| Product Service | Python/FastAPI | 8000 | PostgreSQL + Redis | Catalog, search, inventory |
| Order Service | Node.js | 3003 | PostgreSQL | Order lifecycle, saga pattern |
| Payment Service | Node.js | 3004 | PostgreSQL | Payment processing, idempotency |
| Notification Service | Python | — | — | Event-driven email/SMS |

---

## 2. Prerequisites

### Tools

| Tool | Version | Install |
|------|---------|---------|
| Node.js | 20 LTS | `brew install node@20` |
| Python | 3.11+ | `brew install python@3.11` |
| Docker & Docker Compose | 24+ | `brew install --cask docker` |
| Git | 2.40+ | Installed in Phase 1 |

### Verify Installation

```bash
node --version      # v20.x.x
python3 --version   # 3.11.x
docker --version    # Docker version 24+
docker compose version  # Docker Compose v2.x
```

---

## 3. Step-by-Step Implementation

### Step 1: Set Up the API Gateway (Node.js/Express)

```bash
cd services/api-gateway
npm init -y
npm install express cors helmet morgan http-proxy-middleware express-rate-limit jsonwebtoken
```

The API Gateway routes all incoming requests to the appropriate downstream service. It handles:
- **Rate limiting** — Prevents abuse with configurable request limits
- **JWT validation** — Verifies authentication tokens before forwarding requests
- **Request routing** — Proxies `/api/users/*` to User Service, `/api/products/*` to Product Service, etc.
- **Health checks** — Exposes `/health` for load balancer probes

### Step 2: Set Up the User Service (Node.js)

```bash
cd services/user-service
npm init -y
npm install express pg redis bcryptjs jsonwebtoken joi
npm install --save-dev jest supertest
```

The User Service manages:
- **Registration and login** — Password hashing with bcryptjs, JWT token issuance
- **User profiles** — CRUD operations backed by PostgreSQL
- **Session caching** — Redis for fast session lookups and token blacklisting

### Step 3: Set Up the Product Service (Python/FastAPI)

```bash
cd services/product-service
python3 -m venv venv
source venv/bin/activate
pip install fastapi uvicorn sqlalchemy psycopg2-binary redis pydantic
```

The Product Service manages:
- **Product catalog** — Full CRUD with category filtering
- **Search** — Text-based product search with pagination
- **Inventory tracking** — Stock level management with optimistic locking

### Step 4: Set Up the Order Service (Node.js)

```bash
cd services/order-service
npm init -y
npm install express pg amqplib uuid joi
```

The Order Service manages:
- **Order lifecycle** — Create, update, cancel orders with state machine
- **Saga pattern** — Coordinates multi-service transactions (order → payment → notification)
- **Event publishing** — Emits `order.created`, `order.completed`, `order.cancelled` events to RabbitMQ

### Step 5: Set Up the Payment Service (Node.js)

```bash
cd services/payment-service
npm init -y
npm install express pg amqplib uuid
```

The Payment Service manages:
- **Payment processing** — Processes payments for orders
- **Idempotency** — Uses idempotency keys to prevent duplicate charges
- **Event consumption** — Listens for `order.created` events, publishes `payment.completed`

### Step 6: Set Up the Notification Service (Python)

```bash
cd services/notification-service
python3 -m venv venv
source venv/bin/activate
pip install pika jinja2
```

The Notification Service:
- **Event-driven** — Consumes events from RabbitMQ (no REST API)
- **Email/SMS** — Sends order confirmations, payment receipts, shipping updates
- **Template-based** — Uses Jinja2 templates for notification content

### Step 7: Create the Docker Compose Development Environment

Create `docker-compose.dev.yml` in the phase directory (see [Configuration Walkthrough](#4-configuration-walkthrough)):

```bash
# Start all services and infrastructure
docker compose -f docker-compose.dev.yml up -d

# Verify all containers are running
docker compose -f docker-compose.dev.yml ps
```

**Expected output:**

```
NAME                    STATUS    PORTS
api-gateway             Up        0.0.0.0:3000->3000/tcp
user-service            Up        0.0.0.0:3001->3001/tcp
product-service         Up        0.0.0.0:8000->8000/tcp
order-service           Up        0.0.0.0:3003->3003/tcp
payment-service         Up        0.0.0.0:3004->3004/tcp
notification-service    Up
postgres-users          Up        5432/tcp
postgres-products       Up        5432/tcp
postgres-orders         Up        5432/tcp
postgres-payments       Up        5432/tcp
redis                   Up        0.0.0.0:6379->6379/tcp
rabbitmq                Up        0.0.0.0:5672->5672/tcp, 0.0.0.0:15672->15672/tcp
```

### Step 8: Test the Services

```bash
# Health check — API Gateway
curl http://localhost:3000/health
# Expected: {"status":"ok"}

# Health check — User Service
curl http://localhost:3001/health
# Expected: {"status":"ok"}

# Health check — Product Service
curl http://localhost:8000/health
# Expected: {"status":"ok"}

# RabbitMQ Management UI
open http://localhost:15672
# Default credentials: guest/guest
```

---

## 4. Configuration Walkthrough

### `docker-compose.dev.yml` — Section by Section

#### Application Services

```yaml
services:
  api-gateway:
    build: ./services/api-gateway         # Build from local Dockerfile
    ports:
      - "3000:3000"                        # Expose on host port 3000
    environment:
      - NODE_ENV=development
      - USER_SERVICE_URL=http://user-service:3001       # Service discovery via Docker DNS
      - PRODUCT_SERVICE_URL=http://product-service:8000
      - ORDER_SERVICE_URL=http://order-service:3003
    depends_on:                            # Start after downstream services
      - user-service
      - product-service
      - order-service
```

The API Gateway uses **Docker DNS** for service discovery — containers can resolve each other by service name (e.g., `http://user-service:3001`).

#### Database-per-Service Pattern

```yaml
  postgres-users:
    image: postgres:16-alpine             # Lightweight PostgreSQL 16
    environment:
      POSTGRES_DB: users                   # Database name
      POSTGRES_USER: app                   # Application user
      POSTGRES_PASSWORD: password          # Dev-only password
    volumes:
      - pgdata-users:/var/lib/postgresql/data  # Persist data across restarts
```

Each service gets its own PostgreSQL instance:
- `postgres-users` — User Service (port 5432 internal)
- `postgres-products` — Product Service
- `postgres-orders` — Order Service
- `postgres-payments` — Payment Service

This enforces **data ownership** — services cannot directly query each other's databases.

#### Message Broker

```yaml
  rabbitmq:
    image: rabbitmq:3-management-alpine   # Includes management UI
    ports:
      - "5672:5672"                        # AMQP protocol
      - "15672:15672"                      # Management UI
```

RabbitMQ enables **event-driven architecture**:
- Order Service publishes `order.created` → Payment Service consumes it
- Payment Service publishes `payment.completed` → Notification Service consumes it
- This decouples services — each service can fail independently without cascading failures

#### Cache Layer

```yaml
  redis:
    image: redis:7-alpine
    ports:
      - "6379:6379"
```

Redis provides:
- **Session caching** for the User Service (JWT token lookup)
- **Product catalog caching** for the Product Service (reduces database load)

#### Persistent Volumes

```yaml
volumes:
  pgdata-users:
  pgdata-products:
  pgdata-orders:
  pgdata-payments:
```

Named volumes ensure database data persists across `docker compose down` and `docker compose up` cycles.

---

## 5. Verification Checklist

- [ ] All 12 containers start successfully: `docker compose -f docker-compose.dev.yml ps`
- [ ] API Gateway responds: `curl http://localhost:3000/health`
- [ ] User Service responds: `curl http://localhost:3001/health`
- [ ] Product Service responds: `curl http://localhost:8000/health`
- [ ] Order Service responds: `curl http://localhost:3003/health`
- [ ] Payment Service responds: `curl http://localhost:3004/health`
- [ ] PostgreSQL databases accept connections:
  ```bash
  docker compose -f docker-compose.dev.yml exec postgres-users pg_isready
  ```
- [ ] Redis responds: `docker compose -f docker-compose.dev.yml exec redis redis-cli ping`
- [ ] RabbitMQ management UI accessible at `http://localhost:15672`
- [ ] Services can communicate via Docker DNS (API Gateway routes to downstream services)
- [ ] RabbitMQ event flow works (order creation triggers payment and notification events)

---

## 6. Troubleshooting

### Container fails to start — port already in use

```bash
# Find what's using the port
lsof -i :3000

# Kill the process or change the host port mapping in docker-compose.dev.yml
```

### PostgreSQL connection refused

```bash
# Check if PostgreSQL is ready
docker compose -f docker-compose.dev.yml logs postgres-users

# PostgreSQL takes a few seconds to initialize on first run
# The application should retry connections — add restart: unless-stopped
```

### RabbitMQ connection error in services

```bash
# RabbitMQ takes 10-15 seconds to become ready
# Check the logs
docker compose -f docker-compose.dev.yml logs rabbitmq

# Verify the service is accepting connections
docker compose -f docker-compose.dev.yml exec rabbitmq rabbitmqctl status
```

### Service cannot resolve another service hostname

```bash
# Verify all services are on the same Docker network
docker compose -f docker-compose.dev.yml exec api-gateway nslookup user-service
```

### Python service dependency issues

```bash
# Rebuild the container after adding new pip packages
docker compose -f docker-compose.dev.yml build product-service
docker compose -f docker-compose.dev.yml up -d product-service
```

---

## 7. Key Decisions & Trade-offs

| Decision | Chosen | Alternative | Rationale |
|----------|--------|-------------|-----------|
| **Database-per-service** | Separate DB per service | Shared database | Enforces domain boundaries, enables independent scaling and schema evolution. Trade-off: cross-service queries require API calls. |
| **RabbitMQ vs. Kafka** | RabbitMQ | Apache Kafka | Simpler to operate, better for task queues and RPC patterns. Trade-off: Kafka is better for high-throughput event streaming and replay. |
| **Node.js + Python mix** | Polyglot | Single language | Best tool for each job — Express for REST APIs, FastAPI for high-perf search. Trade-off: more operational complexity. |
| **Saga pattern** | Choreography (events) | Orchestration (central coordinator) | Decoupled services, no single point of failure. Trade-off: harder to trace transaction flow (solved by observability in Phase 8). |
| **REST + Events** | Hybrid | gRPC / pure event-driven | REST for synchronous queries, events for async workflows. Trade-off: gRPC would offer better performance for inter-service calls. |

---

## 8. Production Considerations

- **Service discovery** — Replace Docker DNS with Kubernetes service discovery or Consul (Phase 6)
- **Database credentials** — Replace hardcoded passwords with Vault dynamic secrets (Phase 9)
- **Health checks** — Add readiness and liveness probes beyond simple `/health` (Phase 6)
- **Connection pooling** — Use `pg-pool` (Node.js) or SQLAlchemy connection pools for database efficiency
- **Circuit breakers** — Add Resilience4j or similar patterns for inter-service calls to prevent cascading failures (Phase 10)
- **API versioning** — Use URL-based versioning (`/api/v1/...`) from the start to enable future changes
- **Rate limiting** — The API Gateway should enforce rate limits per user/API key to prevent abuse

---

## 9. Next Phase

**[Phase 3: Containerization →](../phase-03-containerization/README.md)**

With all 6 services running locally via Docker Compose, Phase 3 optimizes the Docker images for production — multi-stage builds, distroless base images, non-root execution, and health checks that reduce image size by 80%.

---

[← Phase 1: Foundation](../phase-01-foundation/README.md) | [Back to Project Overview](../README.md) | [Phase 3: Containerization →](../phase-03-containerization/README.md)
