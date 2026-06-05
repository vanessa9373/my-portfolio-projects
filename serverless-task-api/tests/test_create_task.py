"""Unit tests for create_task Lambda using moto (no real AWS calls)."""
import json
import os
import pytest
import boto3
from moto import mock_aws

# Set environment before importing handler
os.environ["TABLE_NAME"] = "test-tasks"
os.environ["AWS_DEFAULT_REGION"] = "us-east-1"
os.environ["AWS_ACCESS_KEY_ID"] = "testing"
os.environ["AWS_SECRET_ACCESS_KEY"] = "testing"

from src.handlers.create_task import lambda_handler


@pytest.fixture(autouse=True)
def dynamodb_table():
    """Create a real DynamoDB table in moto's in-memory backend."""
    with mock_aws():
        dynamodb = boto3.resource("dynamodb", region_name="us-east-1")
        table = dynamodb.create_table(
            TableName="test-tasks",
            KeySchema=[{"AttributeName": "taskId", "KeyType": "HASH"}],
            AttributeDefinitions=[{"AttributeName": "taskId", "AttributeType": "S"}],
            BillingMode="PAY_PER_REQUEST",
        )
        table.wait_until_exists()
        yield table


def make_event(body: dict | None = None) -> dict:
    return {"body": json.dumps(body) if body else None, "pathParameters": None}


class TestCreateTask:
    def test_creates_task_successfully(self):
        event = make_event({"title": "Write unit tests", "priority": "high"})
        response = lambda_handler(event, {})

        assert response["statusCode"] == 201
        body = json.loads(response["body"])
        assert body["title"] == "Write unit tests"
        assert body["status"] == "pending"
        assert body["priority"] == "high"
        assert "taskId" in body
        assert "createdAt" in body

    def test_returns_400_when_title_missing(self):
        response = lambda_handler(make_event({}), {})
        assert response["statusCode"] == 400
        assert "title" in json.loads(response["body"])["error"]

    def test_returns_400_when_title_empty(self):
        response = lambda_handler(make_event({"title": "   "}), {})
        assert response["statusCode"] == 400

    def test_returns_400_when_title_too_long(self):
        response = lambda_handler(make_event({"title": "x" * 201}), {})
        assert response["statusCode"] == 400
        assert "200 characters" in json.loads(response["body"])["error"]

    def test_returns_400_on_invalid_json(self):
        event = {"body": "not json", "pathParameters": None}
        response = lambda_handler(event, {})
        assert response["statusCode"] == 400

    def test_default_priority_is_medium(self):
        event = make_event({"title": "No priority set"})
        response = lambda_handler(event, {})
        body = json.loads(response["body"])
        assert body["priority"] == "medium"

    def test_cors_header_present(self):
        event = make_event({"title": "CORS test"})
        response = lambda_handler(event, {})
        assert response["headers"]["Access-Control-Allow-Origin"] == "*"
