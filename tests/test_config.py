"""Configuration validation tests."""

import pytest
from pydantic import ValidationError

from app.config import Settings


def test_settings_read_environment_variables(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setenv("APP_PORT", "9090")
    monkeypatch.setenv("APP_ENV", "Production")
    monkeypatch.setenv("LOG_LEVEL", "debug")
    monkeypatch.setenv("APP_VERSION", "1.2.3")

    settings = Settings()

    assert settings.app_port == 9090
    assert settings.app_env == "production"
    assert settings.log_level == "DEBUG"
    assert settings.app_version == "1.2.3"


def test_invalid_log_level_is_rejected(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setenv("LOG_LEVEL", "verbose")

    with pytest.raises(ValidationError):
        Settings()


def test_invalid_port_is_rejected(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setenv("APP_PORT", "70000")

    with pytest.raises(ValidationError):
        Settings()
