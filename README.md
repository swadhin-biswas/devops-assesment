# FastAPI Service

FastAPI service with health and Prometheus endpoints, a distroless container image, and a local Compose setup.

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

Configuration comes from environment variables: `APP_PORT`, `APP_ENV`, `LOG_LEVEL`, and `APP_VERSION`. Logs are JSON on stdout.

## Local development

Requires Python 3.13 and [uv](https://docs.astral.sh/uv/).

```bash
uv sync --frozen
uv run uvicorn app.main:app --host 127.0.0.1 --port 8080
```

In another terminal:

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

Image size: **116 MB**. The container runs as UID 65532 with a read-only root filesystem, all capabilities dropped, and a 256 MB / 0.5 CPU limit.

## Tests

```bash
uv sync --frozen
uv run pytest --cov=app --cov-report=term-missing
uv run ruff check .
```

## License

MIT
