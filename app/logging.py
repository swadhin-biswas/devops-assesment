"""JSON logging configured for container stdout."""

import json
import logging
import sys
from datetime import UTC, datetime
from typing import Any

_REQUEST_FIELDS = ("event", "method", "path", "status_code", "duration_ms")


class JsonFormatter(logging.Formatter):
    """Emit one JSON object per log record."""

    def __init__(self, environment: str, version: str) -> None:
        super().__init__()
        self.environment = environment
        self.version = version

    def format(self, record: logging.LogRecord) -> str:
        payload: dict[str, Any] = {
            "timestamp": datetime.now(UTC)
            .isoformat(timespec="milliseconds")
            .replace("+00:00", "Z"),
            "level": record.levelname,
            "logger": record.name,
            "message": record.getMessage(),
            "environment": self.environment,
            "version": self.version,
        }

        for field in _REQUEST_FIELDS:
            value = getattr(record, field, None)
            if value is not None:
                payload[field] = value

        if record.exc_info:
            payload["exception"] = self.formatException(record.exc_info)

        return json.dumps(payload, default=str, separators=(",", ":"))


def configure_logging(level: str, environment: str, version: str) -> None:
    """Route application and Uvicorn logs through the JSON formatter."""
    handler = logging.StreamHandler(sys.stdout)
    handler.setFormatter(JsonFormatter(environment=environment, version=version))

    root = logging.getLogger()
    root.handlers.clear()
    root.addHandler(handler)
    root.setLevel(level)

    for name in ("uvicorn", "uvicorn.error", "uvicorn.access"):
        uvicorn_logger = logging.getLogger(name)
        uvicorn_logger.handlers = [handler]
        uvicorn_logger.propagate = False
        uvicorn_logger.setLevel(level)

    # The request middleware emits one structured line per request.
    logging.getLogger("uvicorn.access").disabled = True
