"""Test configuration is applied before the application imports its settings."""

import os

os.environ["APP_ENV"] = "test"
os.environ["APP_VERSION"] = "0.0.0-test"
os.environ["LOG_LEVEL"] = "WARNING"
os.environ["APP_PORT"] = "8080"
