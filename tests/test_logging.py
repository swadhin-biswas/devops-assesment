"""Structured logging tests."""

import json
import logging

from app.logging import JsonFormatter


def test_formatter_emits_json_with_request_fields() -> None:
    record = logging.LogRecord(
        name="app",
        level=logging.INFO,
        pathname=__file__,
        lineno=1,
        msg="request completed",
        args=(),
        exc_info=None,
    )
    record.method = "GET"
    record.path = "/health"
    record.status_code = 200
    record.duration_ms = 1.25

    payload = json.loads(JsonFormatter("test", "0.1.0").format(record))

    assert payload["level"] == "INFO"
    assert payload["message"] == "request completed"
    assert payload["environment"] == "test"
    assert payload["version"] == "0.1.0"
    assert payload["method"] == "GET"
    assert payload["path"] == "/health"
    assert payload["status_code"] == 200
    assert payload["duration_ms"] == 1.25
