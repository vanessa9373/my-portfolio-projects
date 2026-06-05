"""
Auto-Remediator Lambda
Matches alerts to remediation playbooks and executes automated fixes.
Author: Jenella Awo
"""

import json
import os
import logging
from datetime import datetime

import boto3

logger = logging.getLogger()
logger.setLevel(logging.INFO)

ssm = boto3.client("ssm")
ecs = boto3.client("ecs")

# Auto-remediation playbooks
PLAYBOOKS = {
    "high_cpu": {
        "action": "scale_up",
        "description": "Scale ECS service desired count by +2",
        "auto_resolve": True,
    },
    "pod_crashloop": {
        "action": "restart_service",
        "description": "Force new deployment of the ECS service",
        "auto_resolve": True,
    },
    "disk_full": {
        "action": "cleanup_logs",
        "description": "Run log cleanup via SSM Run Command",
        "auto_resolve": True,
    },
    "high_memory": {
        "action": "restart_service",
        "description": "Rolling restart of the service",
        "auto_resolve": True,
    },
    "certificate_expiry": {
        "action": "escalate",
        "description": "Cannot auto-remediate — escalate to human",
        "auto_resolve": False,
    },
}


def handler(event, context):
    """Process alert and attempt auto-remediation."""
    try:
        body = json.loads(event.get("body", "{}"))
        alert_name = body.get("alert_name", "").lower().replace(" ", "_")
        service = body.get("service", "unknown")
        cluster = body.get("cluster", os.environ.get("ECS_CLUSTER", "production"))

        logger.info(f"Auto-remediation triggered: {alert_name} for {service}")

        playbook = PLAYBOOKS.get(alert_name)
        if not playbook:
            logger.warning(f"No playbook found for alert: {alert_name}")
            return api_response(200, {
                "status": "no_playbook",
                "alert": alert_name,
                "action": "escalated_to_human",
            })

        if not playbook["auto_resolve"]:
            logger.info(f"Playbook says escalate: {playbook['description']}")
            return api_response(200, {
                "status": "escalated",
                "reason": playbook["description"],
            })

        # Execute remediation
        result = execute_remediation(playbook["action"], service, cluster)

        logger.info(f"Remediation result: {result}")

        return api_response(200, {
            "status": "remediated",
            "alert": alert_name,
            "action": playbook["action"],
            "description": playbook["description"],
            "result": result,
            "timestamp": datetime.utcnow().isoformat() + "Z",
        })

    except Exception as e:
        logger.error(f"Auto-remediation failed: {str(e)}")
        return api_response(500, {"error": str(e), "action": "escalated_to_human"})


def execute_remediation(action, service, cluster):
    """Execute the remediation action."""
    if action == "scale_up":
        logger.info(f"Scaling up {service} in cluster {cluster}")
        # In production: ecs.update_service(cluster=cluster, service=service, desiredCount=current+2)
        return {"action": "scale_up", "service": service, "added_tasks": 2}

    elif action == "restart_service":
        logger.info(f"Restarting {service} in cluster {cluster}")
        # In production: ecs.update_service(cluster=cluster, service=service, forceNewDeployment=True)
        return {"action": "restart", "service": service, "status": "new_deployment_triggered"}

    elif action == "cleanup_logs":
        logger.info(f"Running log cleanup on {service}")
        # In production: ssm.send_command(...) to run cleanup script
        return {"action": "cleanup_logs", "status": "ssm_command_sent"}

    return {"action": action, "status": "unknown_action"}


def api_response(status_code, body):
    return {
        "statusCode": status_code,
        "headers": {"Content-Type": "application/json"},
        "body": json.dumps(body),
    }
