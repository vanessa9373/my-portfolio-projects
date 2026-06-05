# ============================================================
# Pub/Sub Module — Topics, subscriptions, dead-letter, and encryption
# Author: Jenella Awo
# ============================================================

# ---------- Schema (optional) ----------

resource "google_pubsub_schema" "schema" {
  count = var.schema != null ? 1 : 0

  project    = var.project_id
  name       = "${var.project_name}-${var.topic_name}-schema"
  type       = lookup(var.schema, "type", "AVRO")
  definition = lookup(var.schema, "definition", "")
}

# ---------- Dead-letter Topic ----------

resource "google_pubsub_topic" "dead_letter" {
  count   = var.enable_dead_letter ? 1 : 0
  project = var.project_id
  name    = "${var.project_name}-${var.topic_name}-dlq"

  labels = var.tags
}

resource "google_pubsub_subscription" "dead_letter_sub" {
  count   = var.enable_dead_letter ? 1 : 0
  project = var.project_id
  name    = "${var.project_name}-${var.topic_name}-dlq-sub"
  topic   = google_pubsub_topic.dead_letter[0].id

  message_retention_duration = "604800s"
  retain_acked_messages      = true
  ack_deadline_seconds       = 60

  labels = var.tags
}

# ---------- Main Topic ----------

resource "google_pubsub_topic" "topic" {
  project = var.project_id
  name    = "${var.project_name}-${var.topic_name}"

  dynamic "schema_settings" {
    for_each = var.schema != null ? [1] : []
    content {
      schema   = google_pubsub_schema.schema[0].id
      encoding = lookup(var.schema, "encoding", "JSON")
    }
  }

  # CMEK encryption
  kms_key_name = var.kms_key_name

  message_retention_duration = "604800s"

  labels = var.tags
}

# ---------- Subscriptions ----------

resource "google_pubsub_subscription" "subscriptions" {
  for_each = { for s in var.subscriptions : s.name => s }

  project = var.project_id
  name    = "${var.project_name}-${each.value.name}"
  topic   = google_pubsub_topic.topic.id

  ack_deadline_seconds       = lookup(each.value, "ack_deadline", 20)
  message_retention_duration = "${lookup(each.value, "message_retention", 604800)}s"
  retain_acked_messages      = false

  # Push configuration
  dynamic "push_config" {
    for_each = lookup(each.value, "push_endpoint", null) != null ? [1] : []
    content {
      push_endpoint = each.value.push_endpoint
      attributes = {
        x-goog-version = "v1"
      }
    }
  }

  # Retry policy
  dynamic "retry_policy" {
    for_each = lookup(each.value, "retry_policy", null) != null ? [1] : []
    content {
      minimum_backoff = lookup(each.value.retry_policy, "minimum_backoff", "10s")
      maximum_backoff = lookup(each.value.retry_policy, "maximum_backoff", "600s")
    }
  }

  # Dead-letter policy
  dynamic "dead_letter_policy" {
    for_each = var.enable_dead_letter ? [1] : []
    content {
      dead_letter_topic     = google_pubsub_topic.dead_letter[0].id
      max_delivery_attempts = var.dead_letter_max_delivery_attempts
    }
  }

  enable_message_ordering = lookup(each.value, "enable_ordering", false)

  labels = var.tags
}
