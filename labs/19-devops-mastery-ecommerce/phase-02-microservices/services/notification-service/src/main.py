"""
Notification Service

Event-driven consumer that listens to RabbitMQ for payment and order events,
then simulates sending notifications (email, SMS) by logging structured output.

This service does not expose an HTTP server — it runs as a long-lived consumer
process. A health check file is written to disk so that Docker or Kubernetes
can verify liveness via an exec probe.
"""

import json
import logging
import os
import signal
import sys
import time
from datetime import datetime
from pathlib import Path

import pika
from jinja2 import Environment

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------

RABBITMQ_URL = os.getenv("RABBITMQ_URL", "amqp://localhost:5672")
EXCHANGE_NAME = "ecommerce.events"
HEALTH_FILE = "/tmp/notification-service-healthy"

# ---------------------------------------------------------------------------
# Structured JSON logging
# ---------------------------------------------------------------------------

class JsonFormatter(logging.Formatter):
    def format(self, record: logging.LogRecord) -> str:
        entry = {
            "level": record.levelname.lower(),
            "service": "notification-service",
            "msg": record.getMessage(),
            "ts": datetime.utcnow().isoformat() + "Z",
        }
        if record.exc_info and record.exc_info[0]:
            entry["exception"] = self.formatException(record.exc_info)
        return json.dumps(entry)


handler = logging.StreamHandler(sys.stdout)
handler.setFormatter(JsonFormatter())
logger = logging.getLogger("notification-service")
logger.setLevel(logging.INFO)
logger.addHandler(handler)
logger.propagate = False

# ---------------------------------------------------------------------------
# Jinja2 templates for notification messages
# ---------------------------------------------------------------------------

jinja_env = Environment(autoescape=False)

TEMPLATES = {
    "order.created": jinja_env.from_string(
        "New order {{ orderId }} placed by user {{ userId }}. "
        "Total: ${{ '%.2f' | format(total) }}. Items: {{ items | length }}."
    ),
    "payment.completed": jinja_env.from_string(
        "Payment {{ paymentId }} for order {{ orderId }} completed successfully. "
        "Amount charged: ${{ '%.2f' | format(amount) }}."
    ),
    "payment.failed": jinja_env.from_string(
        "Payment for order {{ orderId }} FAILED. "
        "Amount: ${{ '%.2f' | format(amount) }}. Please retry or contact support."
    ),
    "order.cancelled": jinja_env.from_string(
        "Order {{ orderId }} has been cancelled."
    ),
    "order.paid": jinja_env.from_string(
        "Order {{ orderId }} is now confirmed and paid. Preparing for shipment."
    ),
}

# ---------------------------------------------------------------------------
# Notification dispatcher
# ---------------------------------------------------------------------------

def send_email(to: str, subject: str, body: str) -> None:
    """Simulate sending an email by logging the content."""
    logger.info(
        "email_sent",
        extra={},  # extra not used by our formatter; we pass via msg
    )
    # Log as structured JSON manually so the portfolio can show the output
    print(
        json.dumps({
            "level": "info",
            "service": "notification-service",
            "msg": "email_notification",
            "to": to,
            "subject": subject,
            "body": body,
            "ts": datetime.utcnow().isoformat() + "Z",
        })
    )


def send_sms(to: str, message: str) -> None:
    """Simulate sending an SMS by logging the content."""
    print(
        json.dumps({
            "level": "info",
            "service": "notification-service",
            "msg": "sms_notification",
            "to": to,
            "message": message,
            "ts": datetime.utcnow().isoformat() + "Z",
        })
    )


def handle_event(routing_key: str, event: dict) -> None:
    """Route an event to the appropriate notification channel."""
    template = TEMPLATES.get(routing_key)
    if not template:
        logger.info(f"No template for event type '{routing_key}' — skipping")
        return

    # Render notification body from the event data
    body = template.render(**event)
    subject = f"E-Commerce Notification: {routing_key}"

    # Determine recipient (in a real system, look up from user service)
    user_id = event.get("userId", "unknown")
    email_address = f"user-{user_id}@example.com"
    phone_number = f"+1-555-{str(user_id).zfill(4)}"

    # Send both email and SMS simulations
    send_email(to=email_address, subject=subject, body=body)
    send_sms(to=phone_number, message=body)

# ---------------------------------------------------------------------------
# RabbitMQ consumer
# ---------------------------------------------------------------------------

def connect_and_consume() -> None:
    """Establish connection to RabbitMQ and start consuming events."""
    params = pika.URLParameters(RABBITMQ_URL)
    # Heartbeat to keep connection alive
    params.heartbeat = 60
    params.blocked_connection_timeout = 30

    connection = pika.BlockingConnection(params)
    channel = connection.channel()

    # Declare the shared exchange
    channel.exchange_declare(exchange=EXCHANGE_NAME, exchange_type="topic", durable=True)

    # Declare a queue for this service
    queue_name = "notification-service.events"
    channel.queue_declare(queue=queue_name, durable=True)

    # Bind to all events we care about
    binding_keys = [
        "order.created",
        "order.cancelled",
        "order.paid",
        "payment.completed",
        "payment.failed",
    ]
    for key in binding_keys:
        channel.queue_bind(exchange=EXCHANGE_NAME, queue=queue_name, routing_key=key)

    logger.info(f"Bound to events: {', '.join(binding_keys)}")

    # Callback for each message
    def on_message(ch, method, properties, body):
        try:
            event = json.loads(body.decode("utf-8"))
            logger.info(f"Received event: {method.routing_key}")
            handle_event(method.routing_key, event)
            ch.basic_ack(delivery_tag=method.delivery_tag)
        except Exception:
            logger.exception(f"Error processing event: {method.routing_key}")
            # Requeue the message for retry
            ch.basic_nack(delivery_tag=method.delivery_tag, requeue=True)

    channel.basic_qos(prefetch_count=1)
    channel.basic_consume(queue=queue_name, on_message_callback=on_message)

    # Write health file to signal readiness
    Path(HEALTH_FILE).touch()
    logger.info("Health file written — service is ready")

    logger.info("Notification service consuming events...")
    try:
        channel.start_consuming()
    except KeyboardInterrupt:
        logger.info("Received interrupt — stopping consumer")
        channel.stop_consuming()
    finally:
        connection.close()
        # Remove health file on shutdown
        Path(HEALTH_FILE).unlink(missing_ok=True)
        logger.info("Connection closed")

# ---------------------------------------------------------------------------
# Main entry point with retry logic
# ---------------------------------------------------------------------------

def main() -> None:
    """Start the consumer with automatic reconnection."""
    # Handle SIGTERM for graceful shutdown in containers
    def sigterm_handler(signum, frame):
        logger.info("Received SIGTERM — exiting")
        Path(HEALTH_FILE).unlink(missing_ok=True)
        sys.exit(0)

    signal.signal(signal.SIGTERM, sigterm_handler)

    max_retries = 10
    retry_delay = 3  # seconds

    for attempt in range(1, max_retries + 1):
        try:
            logger.info(f"Connecting to RabbitMQ (attempt {attempt}/{max_retries})")
            connect_and_consume()
            break  # Clean exit
        except pika.exceptions.AMQPConnectionError as exc:
            logger.error(f"RabbitMQ connection failed: {exc}")
            if attempt < max_retries:
                logger.info(f"Retrying in {retry_delay}s...")
                time.sleep(retry_delay)
            else:
                logger.error("Max retries reached — exiting")
                sys.exit(1)
        except Exception:
            logger.exception("Unexpected error in consumer loop")
            if attempt < max_retries:
                time.sleep(retry_delay)
            else:
                sys.exit(1)


if __name__ == "__main__":
    main()
