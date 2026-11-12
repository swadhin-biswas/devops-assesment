"""Application configuration loaded from environment variables."""

from functools import lru_cache

from pydantic import Field, field_validator
from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    """Runtime settings; every value can be overridden by an environment variable."""

    model_config = SettingsConfigDict(case_sensitive=False, extra="ignore")

    app_port: int = Field(default=8080, ge=1, le=65535)
    app_env: str = Field(default="development", min_length=1, max_length=32)
    log_level: str = Field(default="INFO")
    app_version: str = Field(default="2.0.2", min_length=1)

    @field_validator("log_level")
    @classmethod
    def validate_log_level(cls, value: str) -> str:
        normalized = value.upper()
        allowed = {"DEBUG", "INFO", "WARNING", "ERROR", "CRITICAL"}
        if normalized not in allowed:
            raise ValueError(f"LOG_LEVEL must be one of {sorted(allowed)}")
        return normalized

    @field_validator("app_env")
    @classmethod
    def normalize_app_env(cls, value: str) -> str:
        normalized = value.strip().lower()
        if not normalized:
            raise ValueError("APP_ENV must not be empty")
        return normalized


@lru_cache
def get_settings() -> Settings:
    """Cache settings so the process validates configuration once."""
    return Settings()
