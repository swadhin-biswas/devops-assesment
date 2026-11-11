"""FastAPI service with health, metrics, and structured request logging."""

import logging
import time
from collections.abc import AsyncIterator
from contextlib import asynccontextmanager

from fastapi import FastAPI, Request, Response
from prometheus_client import CONTENT_TYPE_LATEST, generate_latest

from app.config import get_settings
from app.logging import configure_logging
from app.metrics import ERROR_COUNT, REQUEST_COUNT, REQUEST_LATENCY
from app.tracing import configure_tracing

settings = get_settings()
configure_logging(settings.log_level, settings.app_env, settings.app_version)
logger = logging.getLogger("app")


@asynccontextmanager
async def lifespan(_: FastAPI) -> AsyncIterator[None]:
    logger.info("application startup", extra={"event": "startup"})
    yield
    logger.info("application shutdown", extra={"event": "shutdown"})


app = FastAPI(
    title="FastAPI Service",
    version=settings.app_version,
    lifespan=lifespan,
)

if configure_tracing(
    app,
    service_name="devops-task-app",
    service_version=settings.app_version,
    environment=settings.app_env,
):
    logger.info("tracing initialized", extra={"event": "tracing"})


def _route_path(request: Request) -> str:
    """Use the route template, not the raw URL, to keep metric labels bounded."""
    route = request.scope.get("route")
    return getattr(route, "path", "unmatched")


@app.middleware("http")
async def observe_requests(request: Request, call_next):
    # Scrapes would otherwise dominate the request rate on an idle service.
    if request.url.path == "/metrics":
        return await call_next(request)

    method = request.method
    status = 500
    path = "unmatched"
    started = time.perf_counter()

    try:
        response = await call_next(request)
        status = response.status_code
        path = _route_path(request)
        return response
    except Exception:
        path = _route_path(request)
        raise
    finally:
        duration_seconds = time.perf_counter() - started
        REQUEST_COUNT.labels(method=method, path=path, status=str(status)).inc()
        REQUEST_LATENCY.labels(method=method, path=path).observe(duration_seconds)

        log = logger.error if status >= 500 else logger.info
        if status >= 500:
            ERROR_COUNT.labels(method=method, path=path).inc()

        log(
            "request completed",
            extra={
                "event": "request",
                "method": method,
                "path": path,
                "status_code": status,
                "duration_ms": round(duration_seconds * 1000, 3),
            },
        )


@app.get("/")
async def root() -> dict[str, str]:
    return {
        "message": "Hello from DevOps Task!",
        "status": "running",
        "version": settings.app_version,
    }


@app.get("/health")
async def health() -> dict[str, str]:
    return {
        "status": "ok",
        "version": settings.app_version,
        "environment": settings.app_env,
    }


@app.get("/metrics", include_in_schema=False)
async def metrics() -> Response:
    return Response(content=generate_latest(), media_type=CONTENT_TYPE_LATEST)
