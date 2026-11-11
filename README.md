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
