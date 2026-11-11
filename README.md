# FastAPI Service

FastAPI service with health and Prometheus endpoints, a hardened Alpine container image, and a local Compose setup.

## Layout

| Path | Purpose |
|---|---|
| `app/` | Application code |
| `tests/` | Unit tests |
| `Dockerfile` | Multi-stage container build |
| `docker-compose.yml` | Local container setup |
| `pyproject.toml` | Dependencies and tool configuration |
| `uv.lock` | Locked dependency graph |
| `Makefile` | Common local commands |

## Endpoints

| Endpoint | Response |
|---|---|
| `GET /` | `{"message":"Hello from DevOps Task!","status":"running","version":"<version>"}` |
| `GET /health` | Liveness and readiness status |
| `GET /metrics` | Prometheus counters and request latency histogram |

`app_errors_total` counts 5xx responses. Client errors remain queryable through the `status` label on `app_requests_total`.

Configuration comes from environment variables: `APP_PORT`, `APP_ENV`, `LOG_LEVEL`, and `APP_VERSION`. Logs are JSON on stdout.

## Local development

Requires Python 3.12 and [uv](https://docs.astral.sh/uv/).

```bash
uv sync --frozen
APP_PORT=8080 uv run python -m app
```

`APP_PORT` controls both the listener and the Compose port mapping. In another terminal:

```bash
curl -s http://127.0.0.1:8080/
curl -s http://127.0.0.1:8080/health
curl -s http://127.0.0.1:8080/metrics | head
```

## Container

```bash
cp .env.example .env
docker compose up -d --build
docker compose ps
curl -s http://127.0.0.1:8080/health
docker compose logs -f app
docker compose down
```

Image size: **84 MB**. The container runs as UID 10001 with a read-only root filesystem, all capabilities dropped, and a 256 MB / 0.5 CPU limit.

## Tests

```bash
uv sync --frozen
uv run pytest --cov=app --cov-report=term-missing
uv run ruff check .
```

## License

MIT
