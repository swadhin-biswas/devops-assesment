"""Tracing configuration tests."""

import pytest
from fastapi import FastAPI

from app import tracing


def test_tracing_disabled_without_endpoint(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.delenv("OTEL_EXPORTER_OTLP_ENDPOINT", raising=False)
    app = FastAPI()

    assert tracing.configure_tracing(
        app, service_name="svc", service_version="0.0.1", environment="test"
    ) is False


def test_tracing_enabled_builds_otlp_endpoint(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setenv("OTEL_EXPORTER_OTLP_ENDPOINT", "http://collector:4318/")
    captured: dict[str, object] = {}

    class FakeExporter:
        def __init__(self, endpoint: str) -> None:
            captured["endpoint"] = endpoint

    class FakeProcessor:
        pass

    monkeypatch.setattr(tracing, "OTLPSpanExporter", FakeExporter)
    monkeypatch.setattr(tracing, "BatchSpanProcessor", lambda exporter: FakeProcessor())
    monkeypatch.setattr(tracing.TracerProvider, "add_span_processor", lambda self, p: None)
    monkeypatch.setattr(tracing.trace, "set_tracer_provider", lambda provider: None)
    monkeypatch.setattr(
        tracing.FastAPIInstrumentor,
        "instrument_app",
        lambda app: captured.setdefault("instrumented", True),
    )

    app = FastAPI()

    assert tracing.configure_tracing(
        app, service_name="svc", service_version="0.0.1", environment="test"
    ) is True
    assert captured["endpoint"] == "http://collector:4318/v1/traces"
    assert captured["instrumented"] is True
