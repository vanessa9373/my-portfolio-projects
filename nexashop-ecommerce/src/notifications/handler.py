"""
NexaShop — Notifications Lambda
Triggered by: SQS order queue (async processing)
Actions: send order confirmation via SES, publish SNS event for downstream systems
"""

import json
import os

import boto3

ses = boto3.client("ses")
sns = boto3.client("sns")

SENDER_EMAIL    = os.environ["SENDER_EMAIL"]
ORDERS_SNS_ARN  = os.environ["ORDERS_SNS_ARN"]


def handler(event, context):
    for record in event.get("Records", []):
        try:
            body  = json.loads(record["body"])
            process_order(body)
        except Exception as exc:
            print(f"ERROR processing record: {exc}")
            raise  # Re-raise so SQS returns to queue / routes to DLQ after max retries


def process_order(order: dict):
    order_id   = order["orderId"]
    user_email = order.get("userEmail")
    total      = order.get("total", 0)
    items      = order.get("items", [])

    if user_email:
        ses.send_email(
            Source      = SENDER_EMAIL,
            Destination = {"ToAddresses": [user_email]},
            Message     = {
                "Subject": {"Data": f"NexaShop — Order #{order_id[:8].upper()} Confirmed"},
                "Body": {
                    "Html": {"Data": _build_email_html(order_id, total, items)},
                    "Text": {"Data": f"Your order #{order_id[:8].upper()} has been confirmed. Total: ${total:.2f}"},
                },
            },
        )

    sns.publish(
        TopicArn = ORDERS_SNS_ARN,
        Message  = json.dumps({
            "eventType": "ORDER_CONFIRMED",
            "orderId":   order_id,
            "total":     total,
        }),
        MessageAttributes = {
            "eventType": {"DataType": "String", "StringValue": "ORDER_CONFIRMED"},
        },
    )


def _build_email_html(order_id: str, total: float, items: list) -> str:
    items_html = "".join(
        f"<tr><td>{i.get('name', 'Item')}</td><td>{i.get('quantity', 1)}</td><td>${float(i.get('price', 0)):.2f}</td></tr>"
        for i in items
    )
    return f"""
    <html><body style="font-family:sans-serif;max-width:600px;margin:auto;padding:24px">
      <h2 style="color:#4f46e5">Order Confirmed</h2>
      <p>Order ID: <strong>#{order_id[:8].upper()}</strong></p>
      <table border="1" cellpadding="8" style="border-collapse:collapse;width:100%">
        <tr><th>Item</th><th>Qty</th><th>Price</th></tr>
        {items_html}
      </table>
      <p style="margin-top:16px;font-size:18px"><strong>Total: ${total:.2f}</strong></p>
      <p style="color:#6b7280;font-size:12px">NexaShop — Cloud-Native E-Commerce</p>
    </body></html>
    """
