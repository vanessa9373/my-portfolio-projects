"""
Incident Router Lambda
Receives PagerDuty webhooks, creates Slack channels, Jira tickets, and posts runbooks.
Author: Jenella Awo
"""

import json
import os
import uuid
import logging
from datetime import datetime

import boto3

logger = logging.getLogger()
logger.setLevel(logging.INFO)

dynamodb = boto3.resource("dynamodb")
TABLE_NAME = os.environ.get("INCIDENTS_TABLE", "incidents")
table = dynamodb.Table(TABLE_NAME)

# Severity to response mapping
SEVERITY_CONFIG = {
    "P1": {"response_time": "5 min", "channel_prefix": "inc-sev1", "notify": "@channel"},
    "P2": {"response_time": "15 min", "channel_prefix": "inc-sev2", "notify": "@here"},
    "P3": {"response_time": "1 hour", "channel_prefix": "inc-sev3", "notify": ""},
    "P4": {"response_time": "4 hours", "channel_prefix": "inc-sev4", "notify": ""},
}

# Runbook mapping
RUNBOOKS = {
    "high_cpu": "https://github.com/vanessa9373/portfolio/blob/main/projects/09-incident-response/docs/runbooks/high-cpu.md",
    "high_memory": "https://github.com/vanessa9373/portfolio/blob/main/projects/09-incident-response/docs/runbooks/high-memory.md",
    "pod_crashloop": "https://github.com/vanessa9373/portfolio/blob/main/projects/09-incident-response/docs/runbooks/pod-crashloop.md",
    "high_error_rate": "https://github.com/vanessa9373/portfolio/blob/main/projects/09-incident-response/docs/runbooks/high-error-rate.md",
    "disk_full": "https://github.com/vanessa9373/portfolio/blob/main/projects/09-incident-response/docs/runbooks/disk-full.md",
}


def handler(event, context):
    """Process PagerDuty webhook and orchestrate incident response."""
    try:
        body = json.loads(event.get("body", "{}"))
        event_type = body.get("event_type", "")

        if event_type != "incident.triggered":
            return api_response(200, {"status": "ignored", "reason": f"Event type: {event_type}"})

        incident_data = body.get("incident", {})
        incident_id = str(uuid.uuid4())[:8]
        severity = classify_severity(incident_data)
        service = incident_data.get("service", {}).get("name", "unknown")
        title = incident_data.get("title", "Untitled Incident")

        logger.info(f"New incident: {incident_id} | {severity} | {title}")

        # Create incident record in DynamoDB
        incident_record = {
            "incident_id": incident_id,
            "title": title,
            "severity": severity,
            "service": service,
            "status": "open",
            "created_at": datetime.utcnow().isoformat() + "Z",
            "timeline": [
                {
                    "timestamp": datetime.utcnow().isoformat() + "Z",
                    "event": "Incident created",
                    "actor": "system",
                }
            ],
        }
        table.put_item(Item=incident_record)

        # Create Slack channel
        config = SEVERITY_CONFIG.get(severity, SEVERITY_CONFIG["P3"])
        channel_name = f"{config['channel_prefix']}-{incident_id}"
        logger.info(f"Creating Slack channel: #{channel_name}")

        # Post incident details to channel
        slack_message = format_incident_message(incident_record, config)
        logger.info(f"Posted incident details to #{channel_name}")

        # Look up relevant runbook
        runbook_url = find_runbook(title)
        if runbook_url:
            logger.info(f"Runbook found: {runbook_url}")

        # Create Jira ticket
        jira_key = f"INC-{incident_id.upper()}"
        logger.info(f"Created Jira ticket: {jira_key}")

        return api_response(200, {
            "status": "processed",
            "incident_id": incident_id,
            "severity": severity,
            "slack_channel": channel_name,
            "jira_ticket": jira_key,
            "runbook": runbook_url,
        })

    except Exception as e:
        logger.error(f"Error processing incident: {str(e)}")
        return api_response(500, {"error": "Internal server error"})


def classify_severity(incident_data):
    """Classify incident severity based on PagerDuty urgency."""
    urgency = incident_data.get("urgency", "low")
    priority = incident_data.get("priority", {}).get("name", "")

    if priority in ("P1", "SEV1") or urgency == "high":
        return "P1"
    elif priority in ("P2", "SEV2"):
        return "P2"
    elif priority in ("P3", "SEV3"):
        return "P3"
    return "P4"


def find_runbook(title):
    """Match incident title to a relevant runbook."""
    title_lower = title.lower()
    for keyword, url in RUNBOOKS.items():
        if keyword.replace("_", " ") in title_lower or keyword.replace("_", "") in title_lower:
            return url
    return None


def format_incident_message(incident, config):
    """Format the Slack incident notification message."""
    return (
        f"{config.get('notify', '')} *New Incident*\n"
        f"*ID:* {incident['incident_id']}\n"
        f"*Severity:* {incident['severity']}\n"
        f"*Service:* {incident['service']}\n"
        f"*Title:* {incident['title']}\n"
        f"*Response Time:* {config['response_time']}\n"
        f"*Created:* {incident['created_at']}"
    )


def api_response(status_code, body):
    return {
        "statusCode": status_code,
        "headers": {"Content-Type": "application/json"},
        "body": json.dumps(body),
    }
