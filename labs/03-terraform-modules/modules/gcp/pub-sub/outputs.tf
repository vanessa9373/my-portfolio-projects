# ============================================================
# Pub/Sub Module — Outputs
# Author: Jenella Awo
# ============================================================

output "topic_id" {
  description = "The unique identifier of the Pub/Sub topic"
  value       = google_pubsub_topic.topic.id
}

output "topic_name" {
  description = "The name of the Pub/Sub topic"
  value       = google_pubsub_topic.topic.name
}

output "subscription_ids" {
  description = "Map of subscription names to their unique identifiers"
  value       = { for k, v in google_pubsub_subscription.subscriptions : k => v.id }
}

output "dead_letter_topic_id" {
  description = "The unique identifier of the dead-letter topic (null if disabled)"
  value       = var.enable_dead_letter ? google_pubsub_topic.dead_letter[0].id : null
}
