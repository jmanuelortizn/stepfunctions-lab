"""Validate the incoming pipeline payload.

First state of the pipeline. Demonstrates a Task state with
Retry (transient errors) and Catch (fatal errors) in the ASL.
"""

import json
import logging
import random

logger = logging.getLogger()
logger.setLevel(logging.INFO)

REQUIRED_FIELDS = ("source", "records")

# Simulate transient failures ~20% of the time so the Retry
# policy in the state machine can be observed in action.
TRANSIENT_FAILURE_RATE = 0.2


class TransientError(Exception):
    """Recoverable error — the state machine should retry."""


def handler(event: dict, context) -> dict:
    """Validate payload shape and simulate transient failures.

    Args:
        event: Pipeline input, e.g. {"source": "s3", "records": [...]}.
        context: Lambda context (unused).

    Returns:
        The event enriched with an ``is_valid`` flag.

    Raises:
        TransientError: Randomly, to exercise the Retry policy.
    """
    logger.info("Validating input: %s", json.dumps(event))

    if random.random() < TRANSIENT_FAILURE_RATE:
        raise TransientError("Simulated transient failure (retry me)")

    missing = [f for f in REQUIRED_FIELDS if f not in event]
    is_valid = not missing and isinstance(event.get("records"), list)

    if missing:
        logger.warning("Missing required fields: %s", missing)

    return {**event, "is_valid": is_valid, "missing_fields": missing}
