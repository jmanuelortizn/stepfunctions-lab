"""Process a single record.

Invoked once per element by the Map state, which fans out the
``records`` array with a bounded MaxConcurrency.
"""

import logging

logger = logging.getLogger()
logger.setLevel(logging.INFO)


def handler(event: dict, context) -> dict:
    """Transform one record from the batch.

    Args:
        event: A single record, e.g. {"id": 1, "value": 10}.
        context: Lambda context (unused).

    Returns:
        The processed record with a derived field.
    """
    record_id = event.get("id", "unknown")
    value = event.get("value", 0)

    processed_value = value * 2  # Placeholder business transformation
    logger.info("Processed record %s: %s -> %s", record_id, value,
                processed_value)

    return {"id": record_id, "processed_value": processed_value,
            "status": "processed"}
