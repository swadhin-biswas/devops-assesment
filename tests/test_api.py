"""Endpoint and metrics tests."""

import pytest
from fastapi.testclient import TestClient
from prometheus_client import REGISTRY

from app.main import app

client = TestClient(app)
error_client = TestClient(app, raise_server_exceptions=False)


def test_root_returns_expected_payload() -> None:
    response = client.get("/")

    assert response.status_code == 200
    assert response.json() == {
        "message": "Hello from DevOps Task!",
        "status": "running",
        "version": "0.0.0-test",
    }


def test_health_returns_ok() -> None:
    response = client.get("/health")

    assert response.status_code == 200
    assert response.json() == {
        "status": "ok",
        "version": "0.0.0-test",
        "environment": "test",
    }


def test_metrics_exposes_request_error_and_latency_series() -> None:
    client.get("/")
    response = client.get("/metrics")

    assert response.status_code == 200
    assert response.headers["content-type"].startswith("text/plain")
    assert "app_requests_total" in response.text
    assert "app_errors_total" in response.text
    assert "app_request_duration_seconds_bucket" in response.text


def test_unknown_route_returns_404() -> None:
    response = client.get("/does-not-exist")

    assert response.status_code == 404


@pytest.fixture
def failing_route():
    async def fail() -> None:
        raise RuntimeError("intentional test failure")

    app.add_api_route("/_test/fail", fail, methods=["GET"])
    yield
    app.router.routes = [
        route for route in app.router.routes if getattr(route, "path", None) != "/_test/fail"
    ]


def test_5xx_increments_error_counter(failing_route: None) -> None:
    labels = {"method": "GET", "path": "/_test/fail"}
    before = REGISTRY.get_sample_value("app_errors_total", labels) or 0

    response = error_client.get("/_test/fail")

    after = REGISTRY.get_sample_value("app_errors_total", labels) or 0
    assert response.status_code == 500
    assert after == before + 1
