import json
import logging

logger = logging.getLogger()
logger.setLevel(logging.INFO)


def handler(event, context):
    """Placeholder handler — logs the event and returns 200.
    Replace with real business logic during application development."""
    logger.info("Event received: %s", json.dumps(event, default=str))
    return {
        "statusCode": 200,
        "body": json.dumps({"message": "placeholder"})
    }
