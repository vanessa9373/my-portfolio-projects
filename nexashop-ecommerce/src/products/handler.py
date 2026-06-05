"""
NexaShop — Products Lambda
Handles: GET /products, GET /products/{id}, POST /products, PUT /products/{id}
Backend: DynamoDB (PAY_PER_REQUEST)
"""

import json
import os
import uuid
from datetime import datetime, timezone

import boto3
from boto3.dynamodb.conditions import Key

dynamodb = boto3.resource("dynamodb")
table = dynamodb.Table(os.environ["PRODUCTS_TABLE"])


def handler(event, context):
    method = event.get("httpMethod", "")
    path   = event.get("path", "")
    params = event.get("pathParameters") or {}

    try:
        if method == "GET" and params.get("productId"):
            return get_product(params["productId"])
        if method == "GET":
            return list_products(event.get("queryStringParameters") or {})
        if method == "POST":
            return create_product(json.loads(event.get("body") or "{}"))
        if method == "PUT" and params.get("productId"):
            return update_product(params["productId"], json.loads(event.get("body") or "{}"))
        if method == "DELETE" and params.get("productId"):
            return delete_product(params["productId"])
    except Exception as exc:
        print(f"ERROR: {exc}")
        return _resp(500, {"error": "Internal server error"})

    return _resp(404, {"error": "Not found"})


def get_product(product_id: str):
    result = table.get_item(Key={"productId": product_id})
    item = result.get("Item")
    if not item:
        return _resp(404, {"error": "Product not found"})
    return _resp(200, item)


def list_products(qs: dict):
    category = qs.get("category")
    limit    = min(int(qs.get("limit", 20)), 100)

    if category:
        result = table.query(
            IndexName="category-createdAt-index",
            KeyConditionExpression=Key("category").eq(category),
            ScanIndexForward=False,
            Limit=limit,
        )
    else:
        result = table.scan(Limit=limit)

    return _resp(200, {"items": result.get("Items", []), "count": result.get("Count", 0)})


def create_product(body: dict):
    required = ["name", "price", "category"]
    missing  = [f for f in required if f not in body]
    if missing:
        return _resp(400, {"error": f"Missing required fields: {missing}"})

    product_id = str(uuid.uuid4())
    now        = datetime.now(timezone.utc).isoformat()

    item = {
        "productId":   product_id,
        "name":        body["name"],
        "description": body.get("description", ""),
        "price":       str(body["price"]),
        "category":    body["category"],
        "imageKey":    body.get("imageKey", ""),
        "inStock":     body.get("inStock", True),
        "createdAt":   now,
        "updatedAt":   now,
    }

    table.put_item(Item=item)
    return _resp(201, item)


def update_product(product_id: str, body: dict):
    existing = table.get_item(Key={"productId": product_id}).get("Item")
    if not existing:
        return _resp(404, {"error": "Product not found"})

    allowed = ["name", "description", "price", "category", "imageKey", "inStock"]
    updates = {k: v for k, v in body.items() if k in allowed}
    updates["updatedAt"] = datetime.now(timezone.utc).isoformat()

    expr        = "SET " + ", ".join(f"#k{i} = :v{i}" for i, k in enumerate(updates))
    names       = {f"#k{i}": k for i, k in enumerate(updates)}
    values      = {f":v{i}": v for i, (k, v) in enumerate(updates.items())}

    table.update_item(
        Key={"productId": product_id},
        UpdateExpression=expr,
        ExpressionAttributeNames=names,
        ExpressionAttributeValues=values,
    )
    return _resp(200, {"productId": product_id, **updates})


def delete_product(product_id: str):
    table.delete_item(Key={"productId": product_id})
    return _resp(204, {})


def _resp(status: int, body: dict):
    return {
        "statusCode": status,
        "headers": {
            "Content-Type": "application/json",
            "Access-Control-Allow-Origin": "*",
        },
        "body": json.dumps(body, default=str),
    }
