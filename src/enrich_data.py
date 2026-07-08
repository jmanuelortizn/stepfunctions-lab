"""Enrich the batch with metadata.

Runs as branch 1 of the Parallel state, concurrently with the
quality check branch.
"""

import logging
from datetime import datetime, timezone

logger = logging.getLogger()
logger.setLevel(logging.INFO)


def handler(event: dict, context) -> dict:
    """Attach enrichment metadata to the batch.

    Args:
        event: The validated pipeline payload.
        context: Lambda context (unused).

    Returns:
        Enrichment metadata for the batch.
    """
    record_count = len(event.get("records", []))
    logger.info("Enriching batch of %s records", record_count)

    return {
        "branch": "enrichment",
        "enriched_at": datetime.now(timezone.utc).isoformat(),
        "record_count": record_count,
    }
