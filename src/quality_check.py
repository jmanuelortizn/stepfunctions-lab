"""Run data-quality checks on the batch.

Runs as branch 2 of the Parallel state. If quality fails, it
raises so the Catch on the Parallel state routes to the failure
handler — this is how you fail fast on bad data.
"""

import logging

logger = logging.getLogger()
logger.setLevel(logging.INFO)


class DataQualityError(Exception):
    """Raised when the batch does not meet quality thresholds."""


def handler(event: dict, context) -> dict:
    """Verify every record has a numeric ``value`` field.

    Args:
        event: The validated pipeline payload.
        context: Lambda context (unused).

    Returns:
        Quality metrics for the batch.

    Raises:
        DataQualityError: If any record is malformed.
    """
    records = event.get("records", [])
    bad_records = [
        r for r in records
        if not isinstance(r.get("value"), (int, float))
    ]

    if bad_records:
        logger.error("Quality check failed for %s records", len(bad_records))
        raise DataQualityError(
            f"{len(bad_records)} record(s) missing numeric 'value'"
        )

    logger.info("Quality check passed: %s records", len(records))
    return {"branch": "quality", "checked": len(records), "passed": True}
