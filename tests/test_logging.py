"""Structured logging tests."""

import json
import logging
import sys

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


def test_formatter_includes_exception_traceback() -> None:
    try:
        raise RuntimeError("boom")
    except RuntimeError:
        record = logging.LogRecord(
            name="app",
            level=logging.ERROR,
            pathname=__file__,
            lineno=1,
            msg="request failed",
            args=(),
            exc_info=sys.exc_info(),
        )

    payload = json.loads(JsonFormatter("test", "0.1.0").format(record))

    assert payload["level"] == "ERROR"
    assert "RuntimeError: boom" in payload["exception"]
    assert "Traceback" in payload["exception"]
