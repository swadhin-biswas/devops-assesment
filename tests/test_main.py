"""Runner configuration tests."""

import pytest

from app import __main__ as runner
from app.config import get_settings


def test_main_uses_configured_port(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setenv("APP_PORT", "9090")
    get_settings.cache_clear()
    captured: dict[str, object] = {}

    def fake_run(app: str, **kwargs: object) -> None:
        captured["app"] = app
        captured.update(kwargs)

    monkeypatch.setattr(runner.uvicorn, "run", fake_run)
    runner.main()

    assert captured["app"] == "app.main:app"
    assert captured["port"] == 9090
    assert captured["host"] == "0.0.0.0"

    get_settings.cache_clear()
