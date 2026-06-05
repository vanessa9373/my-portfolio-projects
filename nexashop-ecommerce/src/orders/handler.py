"""
NexaShop — Orders Lambda
Handles: POST /orders, GET /orders/{id}, GET /orders (user's orders)
Backend: Aurora PostgreSQL (via psycopg2) + SQS (async order processing)
"""

import json
import os
import uuid
from datetime import datetime, timezone

import boto3
import psycopg2
import psycopg2.extras

secrets   = boto3.client("secretsmanager")
sqs       = boto3.client("sqs")

ORDER_QUEUE_URL = os.environ["ORDER_QUEUE_URL"]
DB_SECRET_ARN   = os.environ["DB_SECRET_ARN"]

_db_conn = None


def _get_db():
    global _db_conn
    if _db_conn and not _db_conn.closed:
        return _db_conn

    secret = json.loads(secrets.get_secret_value(SecretId=DB_SECRET_ARN)["SecretString"])
    _db_conn = psycopg2.connect(
        host     = secret["host"],
        port     = secret["port"],
        dbname   = secret["dbname"],
        user     = secret["username"],
        password = secret["password"],
        sslmode  = "require",
    )
    return _db_conn


def handler(event, context):
    method = event.get("httpMethod", "")
    params = event.get("pathParameters") or {}
    claims = event.get("requestContext", {}).get("authorizer", {}).get("claims", {})
    user_id = claims.get("sub", "anonymous")

    try:
        if method == "POST":
            return create_order(json.loads(event.get("body") or "{}"), user_id)
        if method == "GET" and params.get("orderId"):
            return get_order(params["orderId"], user_id)
        if method == "GET":
            return list_user_orders(user_id)
    except psycopg2.Error as e:
        print(f"DB ERROR: {e}")
        return _resp(503, {"error": "Database unavailable"})
    except Exception as exc:
        print(f"ERROR: {exc}")
        return _resp(500, {"error": "Internal server error"})

    return _resp(404, {"error": "Not found"})


def create_order(body: dict, user_id: str):
    items = body.get("items", [])
    if not items:
        return _resp(400, {"error": "Order must contain at least one item"})

    order_id = str(uuid.uuid4())
    now      = datetime.now(timezone.utc).isoformat()
    total    = sum(float(i.get("price", 0)) * int(i.get("quantity", 1)) for i in items)

    db   = _get_db()
    cur  = db.cursor()
    cur.execute(
        """
        INSERT INTO orders (order_id, user_id, status, total, items, created_at, updated_at)
        VALUES (%s, %s, %s, %s, %s, %s, %s)
        """,
        (order_id, user_id, "pending", total, json.dumps(items), now, now),
    )
    db.commit()

    # Enqueue for async processing (inventory check, payment, fulfillment)
    sqs.send_message(
        QueueUrl    = ORDER_QUEUE_URL,
        MessageBody = json.dumps({"orderId": order_id, "userId": user_id, "items": items, "total": total}),
        MessageGroupId = user_id,  # FIFO queue — one group per user for ordering guarantee
    )

    return _resp(201, {"orderId": order_id, "status": "pending", "total": total, "createdAt": now})


def get_order(order_id: str, user_id: str):
    db  = _get_db()
    cur = db.cursor(cursor_factory=psycopg2.extras.RealDictCursor)
    cur.execute("SELECT * FROM orders WHERE order_id = %s AND user_id = %s", (order_id, user_id))
    row = cur.fetchone()
    if not row:
        return _resp(404, {"error": "Order not found"})
    return _resp(200, dict(row))


def list_user_orders(user_id: str):
    db  = _get_db()
    cur = db.cursor(cursor_factory=psycopg2.extras.RealDictCursor)
    cur.execute(
        "SELECT order_id, status, total, created_at FROM orders WHERE user_id = %s ORDER BY created_at DESC LIMIT 50",
        (user_id,),
    )
    return _resp(200, {"orders": [dict(r) for r in cur.fetchall()]})


def _resp(status: int, body: dict):
    return {
        "statusCode": status,
        "headers": {
            "Content-Type": "application/json",
            "Access-Control-Allow-Origin": "*",
        },
        "body": json.dumps(body, default=str),
    }
