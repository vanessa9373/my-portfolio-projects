"""
Product Service

Full CRUD product catalog with search, inventory management, Redis caching,
and PostgreSQL storage via asyncpg. Exposes a FastAPI application on port 8000.
"""

import asyncio
import json
import logging
import os
import signal
import sys
from contextlib import asynccontextmanager
from datetime import datetime
from typing import Optional

import asyncpg
import redis.asyncio as aioredis
from fastapi import FastAPI, HTTPException, Query
from pydantic import BaseModel, Field

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------

DATABASE_URL = os.getenv(
    "DATABASE_URL", "postgresql://app:password@localhost:5432/products"
)
REDIS_URL = os.getenv("REDIS_URL", "redis://localhost:6379")
PORT = int(os.getenv("PORT", "8000"))
CACHE_TTL = 300  # seconds

# ---------------------------------------------------------------------------
# Structured JSON logging
# ---------------------------------------------------------------------------

class JsonFormatter(logging.Formatter):
    def format(self, record: logging.LogRecord) -> str:
        log_entry = {
            "level": record.levelname.lower(),
            "service": "product-service",
            "msg": record.getMessage(),
            "ts": datetime.utcnow().isoformat() + "Z",
        }
        if record.exc_info and record.exc_info[0]:
            log_entry["exception"] = self.formatException(record.exc_info)
        return json.dumps(log_entry)


handler = logging.StreamHandler(sys.stdout)
handler.setFormatter(JsonFormatter())
logger = logging.getLogger("product-service")
logger.setLevel(logging.INFO)
logger.addHandler(handler)
logger.propagate = False

# ---------------------------------------------------------------------------
# Global connection holders (set during lifespan)
# ---------------------------------------------------------------------------

db_pool: Optional[asyncpg.Pool] = None
redis_client: Optional[aioredis.Redis] = None

# ---------------------------------------------------------------------------
# Database initialization
# ---------------------------------------------------------------------------

CREATE_TABLE_SQL = """
CREATE TABLE IF NOT EXISTS products (
    id          SERIAL PRIMARY KEY,
    name        VARCHAR(255) NOT NULL,
    description TEXT DEFAULT '',
    price       NUMERIC(10, 2) NOT NULL CHECK (price >= 0),
    stock       INTEGER NOT NULL DEFAULT 0 CHECK (stock >= 0),
    category    VARCHAR(100) DEFAULT '',
    created_at  TIMESTAMP DEFAULT NOW(),
    updated_at  TIMESTAMP DEFAULT NOW()
);
"""

# ---------------------------------------------------------------------------
# Application lifespan — connect / disconnect resources
# ---------------------------------------------------------------------------

@asynccontextmanager
async def lifespan(app: FastAPI):
    global db_pool, redis_client

    # Startup
    db_pool = await asyncpg.create_pool(DATABASE_URL, min_size=2, max_size=10)
    async with db_pool.acquire() as conn:
        await conn.execute(CREATE_TABLE_SQL)
    logger.info("Connected to PostgreSQL")

    redis_client = aioredis.from_url(REDIS_URL, decode_responses=True)
    await redis_client.ping()
    logger.info("Connected to Redis")

    logger.info(f"Product service ready on port {PORT}")
    yield

    # Shutdown
    await redis_client.aclose()
    await db_pool.close()
    logger.info("Connections closed")


app = FastAPI(title="Product Service", version="1.0.0", lifespan=lifespan)

# ---------------------------------------------------------------------------
# Pydantic models
# ---------------------------------------------------------------------------

class ProductCreate(BaseModel):
    name: str = Field(..., min_length=1, max_length=255)
    description: str = ""
    price: float = Field(..., ge=0)
    stock: int = Field(0, ge=0)
    category: str = ""


class ProductUpdate(BaseModel):
    name: Optional[str] = Field(None, min_length=1, max_length=255)
    description: Optional[str] = None
    price: Optional[float] = Field(None, ge=0)
    stock: Optional[int] = Field(None, ge=0)
    category: Optional[str] = None


class InventoryUpdate(BaseModel):
    quantity: int = Field(..., description="Positive to add stock, negative to remove")

# ---------------------------------------------------------------------------
# Health endpoints
# ---------------------------------------------------------------------------

@app.get("/health")
async def health():
    return {"status": "ok", "service": "product-service"}


@app.get("/health/live")
async def liveness():
    return {"status": "alive"}


@app.get("/health/ready")
async def readiness():
    try:
        async with db_pool.acquire() as conn:
            await conn.fetchval("SELECT 1")
        await redis_client.ping()
        return {"status": "ready"}
    except Exception as exc:
        logger.error(f"Readiness check failed: {exc}")
        raise HTTPException(status_code=503, detail="Service not ready")

# ---------------------------------------------------------------------------
# Product CRUD
# ---------------------------------------------------------------------------

@app.post("/api/products", status_code=201)
async def create_product(product: ProductCreate):
    """Create a new product in the catalog."""
    async with db_pool.acquire() as conn:
        row = await conn.fetchrow(
            """INSERT INTO products (name, description, price, stock, category)
               VALUES ($1, $2, $3, $4, $5)
               RETURNING id, name, description, price, stock, category, created_at, updated_at""",
            product.name,
            product.description,
            product.price,
            product.stock,
            product.category,
        )
    result = dict(row)
    result["price"] = float(result["price"])
    logger.info(f"Product created: id={result['id']}")
    return {"product": _serialize(result)}


@app.get("/api/products")
async def list_products(
    category: Optional[str] = Query(None),
    search: Optional[str] = Query(None),
    limit: int = Query(20, ge=1, le=100),
    offset: int = Query(0, ge=0),
):
    """List products with optional category filter and full-text search."""
    # Build a cache key from query params
    cache_key = f"products:list:{category}:{search}:{limit}:{offset}"
    cached = await redis_client.get(cache_key)
    if cached:
        return {"products": json.loads(cached), "source": "cache"}

    conditions = []
    params = []
    idx = 1

    if category:
        conditions.append(f"category = ${idx}")
        params.append(category)
        idx += 1

    if search:
        conditions.append(f"(name ILIKE ${idx} OR description ILIKE ${idx})")
        params.append(f"%{search}%")
        idx += 1

    where = f"WHERE {' AND '.join(conditions)}" if conditions else ""
    params.extend([limit, offset])

    query = f"""
        SELECT id, name, description, price, stock, category, created_at, updated_at
        FROM products {where}
        ORDER BY created_at DESC
        LIMIT ${idx} OFFSET ${idx + 1}
    """

    async with db_pool.acquire() as conn:
        rows = await conn.fetch(query, *params)

    products = [_serialize(dict(r)) for r in rows]

    # Cache the result set
    await redis_client.set(cache_key, json.dumps(products, default=str), ex=CACHE_TTL)

    return {"products": products, "source": "db"}


@app.get("/api/products/{product_id}")
async def get_product(product_id: int):
    """Retrieve a single product by ID."""
    cached = await redis_client.get(f"product:{product_id}")
    if cached:
        return {"product": json.loads(cached), "source": "cache"}

    async with db_pool.acquire() as conn:
        row = await conn.fetchrow(
            "SELECT id, name, description, price, stock, category, created_at, updated_at FROM products WHERE id = $1",
            product_id,
        )
    if not row:
        raise HTTPException(status_code=404, detail="Product not found")

    product = _serialize(dict(row))
    await redis_client.set(f"product:{product_id}", json.dumps(product, default=str), ex=CACHE_TTL)
    return {"product": product, "source": "db"}


@app.put("/api/products/{product_id}")
async def update_product(product_id: int, updates: ProductUpdate):
    """Update product fields."""
    fields = []
    values = []
    idx = 1

    for field_name, value in updates.model_dump(exclude_unset=True).items():
        fields.append(f"{field_name} = ${idx}")
        values.append(value)
        idx += 1

    if not fields:
        raise HTTPException(status_code=400, detail="No fields to update")

    fields.append(f"updated_at = NOW()")
    values.append(product_id)

    query = f"""
        UPDATE products SET {', '.join(fields)}
        WHERE id = ${idx}
        RETURNING id, name, description, price, stock, category, created_at, updated_at
    """

    async with db_pool.acquire() as conn:
        row = await conn.fetchrow(query, *values)

    if not row:
        raise HTTPException(status_code=404, detail="Product not found")

    product = _serialize(dict(row))

    # Invalidate caches
    await redis_client.delete(f"product:{product_id}")
    await _invalidate_list_cache()

    logger.info(f"Product updated: id={product_id}")
    return {"product": product}


@app.delete("/api/products/{product_id}", status_code=204)
async def delete_product(product_id: int):
    """Delete a product from the catalog."""
    async with db_pool.acquire() as conn:
        result = await conn.execute("DELETE FROM products WHERE id = $1", product_id)

    if result == "DELETE 0":
        raise HTTPException(status_code=404, detail="Product not found")

    await redis_client.delete(f"product:{product_id}")
    await _invalidate_list_cache()
    logger.info(f"Product deleted: id={product_id}")

# ---------------------------------------------------------------------------
# Inventory management
# ---------------------------------------------------------------------------

@app.patch("/api/products/{product_id}/inventory")
async def update_inventory(product_id: int, body: InventoryUpdate):
    """
    Adjust inventory for a product. Positive quantity adds stock,
    negative quantity removes stock. Stock cannot go below zero.
    """
    async with db_pool.acquire() as conn:
        row = await conn.fetchrow(
            """UPDATE products
               SET stock = stock + $1, updated_at = NOW()
               WHERE id = $2 AND stock + $1 >= 0
               RETURNING id, name, stock""",
            body.quantity,
            product_id,
        )

    if not row:
        # Distinguish between "not found" and "insufficient stock"
        async with db_pool.acquire() as conn:
            exists = await conn.fetchval("SELECT 1 FROM products WHERE id = $1", product_id)
        if not exists:
            raise HTTPException(status_code=404, detail="Product not found")
        raise HTTPException(status_code=409, detail="Insufficient stock")

    await redis_client.delete(f"product:{product_id}")
    logger.info(f"Inventory updated: id={product_id}, delta={body.quantity}, new_stock={row['stock']}")
    return {"id": row["id"], "name": row["name"], "stock": row["stock"]}

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def _serialize(row: dict) -> dict:
    """Convert asyncpg record dict to JSON-safe dict."""
    for key in ("created_at", "updated_at"):
        if key in row and row[key] is not None:
            row[key] = row[key].isoformat()
    if "price" in row:
        row["price"] = float(row["price"])
    return row


async def _invalidate_list_cache():
    """Remove all cached list queries. Uses a simple key scan."""
    cursor = None
    while True:
        cursor, keys = await redis_client.scan(cursor=cursor or 0, match="products:list:*", count=100)
        if keys:
            await redis_client.delete(*keys)
        if cursor == 0:
            break

# ---------------------------------------------------------------------------
# Entrypoint
# ---------------------------------------------------------------------------

if __name__ == "__main__":
    import uvicorn

    uvicorn.run(app, host="0.0.0.0", port=PORT, log_level="info")
