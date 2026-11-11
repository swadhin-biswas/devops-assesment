# DevOps Task: Containerized FastAPI Platform

A small FastAPI service delivered as a hardened container image, with CI/CD to AWS, Kubernetes manifests, and a self-hosted observability stack.

## Repository layout

| Path | Purpose |
|---|---|
| `app/` | FastAPI service and application configuration |
| `tests/` | Unit tests |
| `Dockerfile` | Multi-stage application image |
| `docker-compose.yml` | Local application stack |
| `monitoring/` | Prometheus, Grafana, Loki, and Alloy configuration |
| `terraform/` | AWS infrastructure and remote state |
| `k8s/` | Kubernetes deployment, service, and autoscaling |
| `scripts/` | Operational scripts |
| `.github/workflows/` | Pull request and release pipelines |

## Application

| Endpoint | Response |
|---|---|
| `GET /` | `{"message":"Hello from DevOps Task!","status":"running","version":"<version>"}` |
| `GET /health` | Liveness and readiness status |
| `GET /metrics` | Prometheus request count, error count, and latency histogram |

Configuration is read from environment variables: `APP_PORT`, `APP_ENV`, `LOG_LEVEL`, and `APP_VERSION`. Logs are JSON objects written to stdout.

### Run locally

Requires Python 3.12 and [uv](https://docs.astral.sh/uv/).

```bash
uv sync --frozen
uv run uvicorn app.main:app --host 127.0.0.1 --port 8080
```

Verify in another terminal:

```bash
curl -s http://127.0.0.1:8080/
curl -s http://127.0.0.1:8080/health
curl -s http://127.0.0.1:8080/metrics | head
```

### Run with Docker Compose

```bash
cp .env.example .env
docker compose up -d --build
docker compose ps
curl -s http://127.0.0.1:8080/health
docker compose logs -f app
docker compose down
```

The container runs as a non-root user on a read-only root filesystem with all capabilities dropped. The image is built in two stages: dependencies are resolved from `uv.lock`, and the runtime layer is distroless.

### Tests and linting

```bash
uv sync --frozen
uv run pytest --cov=app --cov-report=term-missing
uv run ruff check .
```

## License

MIT
