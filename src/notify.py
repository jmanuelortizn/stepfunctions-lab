"""Emit the final pipeline summary.

Last Task before Succeed. In a real pipeline this would publish
to SNS, Slack, or EventBridge; here it just logs the summary so
the lab has zero extra moving parts.
"""

import json
import logging

logger = logging.getLogger()
logger.setLevel(logging.INFO)


def handler(event: dict, context) -> dict:
    """Log the pipeline summary produced by the Pass state.

    Args:
        event: Summary object assembled upstream.
        context: Lambda context (unused).

    Returns:
        A confirmation payload.
    """
    logger.info("PIPELINE SUMMARY: %s", json.dumps(event, default=str))
    return {"notified": True, "summary": event}
