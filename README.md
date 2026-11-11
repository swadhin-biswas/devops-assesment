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

Pull requests run ruff, pytest with an 80% coverage gate and XML artifact, hadolint, shellcheck, an image build, and a Trivy scan that fails on CRITICAL findings.

Pushes to `main` build `linux/amd64` and `linux/arm64` images with GitHub Actions layer caching. Images are tagged with the full commit SHA and `v0.1.<run-number>`; `latest` is not used. The release assumes an AWS role through GitHub OIDC, pushes to ECR, deploys over SSM, and smoke tests `/health`. If the deploy or smoke test fails, `scripts/deploy.sh --rollback` restores the previous image.

No repository secrets are required. All deployment values are repository variables.

### Fallback checks

GitHub Actions is the primary pipeline. The same checks run locally with:

```bash
make ci                  # lint, tests, image build, Trivy scan
./scripts/ci-check.sh --no-docker   # lint and tests only
```

`.circleci/config.yml` mirrors the PR job for CircleCI. It requires a connected CircleCI project; the local script is the offline fallback. Release and deployment stay in GitHub Actions because the AWS role trusts GitHub OIDC. The local script needs `docker`, `hadolint`, `shellcheck`, and `trivy`.

### Bootstrap AWS once

```bash
cd terraform/bootstrap
cp terraform.tfvars.example terraform.tfvars
terraform init
terraform apply
```

The bootstrap stack uses local state. It creates the S3 bucket for the environment stacks, the GitHub OIDC provider and deploy role, and the ECR repository. `github_repository` in `terraform.tfvars` must match the GitHub repository exactly; the OIDC trust policy is scoped to that name and the `main` branch.

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
