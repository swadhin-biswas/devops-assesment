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
| `.github/workflows/` | Pull request and release pipelines |
| `terraform/bootstrap/` | State bucket, GitHub OIDC role, and ECR repository |
| `scripts/deploy.sh` | EC2 deploy and rollback script |

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

Image size: **84 MB**. The image is Alpine 3.23 with Python 3.12; the shell and `apk` are removed. The container runs as UID 10001 with a read-only root filesystem, all capabilities dropped, and a 256 MB / 0.5 CPU limit.

## CI/CD

Pull requests run lint, tests with coverage, hadolint, shellcheck, an image build, and a Trivy scan that fails on CRITICAL findings.

Pushes to `main` build `linux/amd64` and `linux/arm64` images, push them to ECR with the commit SHA and a semantic version (`v0.1.<run-number>`), deploy over SSM, and smoke test `/health`. If the health check fails, `scripts/deploy.sh` restarts the previous image and exits non-zero.

### Bootstrap AWS once

```bash
cd terraform/bootstrap
cp terraform.tfvars.example terraform.tfvars
terraform init
terraform apply
```

The bootstrap stack uses local state. It creates the S3 bucket for the environment stacks, the GitHub OIDC provider and deploy role, and the ECR repository.

If the AWS account already has the GitHub OIDC provider, import it before applying:

```bash
terraform import aws_iam_openid_connect_provider.github \
  arn:aws:iam::<account-id>:oidc-provider/token.actions.githubusercontent.com
```

Set these repository variables under **Settings → Secrets and variables → Actions → Variables**:

| Variable | Value |
|---|---|
| `AWS_REGION` | `us-east-1` |
| `AWS_ROLE_ARN` | `terraform output -raw github_deploy_role_arn` |
| `ECR_REGISTRY` | `terraform output -raw ecr_registry` |
| `ECR_REPOSITORY` | `devops-task/app` |
| `EC2_INSTANCE_ID` | Instance ID from the Terraform environment stack |

No AWS access keys are stored in GitHub. The workflow assumes the role through OIDC.

## Tests

```bash
uv sync --frozen
uv run pytest --cov=app --cov-report=term-missing
uv run ruff check .
```

## License

MIT
