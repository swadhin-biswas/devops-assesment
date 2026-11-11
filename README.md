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
| `.circleci/` | CircleCI fallback for PR checks |
| `.buildkite/` | Self-hosted Buildkite fallback pipeline |
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

Pull requests run ruff, pytest with an 80% coverage gate and a job-summary report, hadolint, shellcheck, an image build, and a Trivy scan that fails on CRITICAL findings.

Pushes to `main` build `linux/amd64` and `linux/arm64` images with GitHub Actions layer caching. Images are tagged with the full commit SHA and `v0.1.<run-number>`; `latest` is not used. The release logs in to Docker Hub, pushes, syncs `scripts/deploy.sh` to the instance over SSM, deploys, and smoke tests `/health`. If the deploy or smoke test fails, `scripts/deploy.sh --rollback` restores the previous image.

No repository secrets are required. All deployment values are repository variables.

### Fallback checks

GitHub Actions is the primary pipeline. The same checks run locally with:

```bash
make ci                  # lint, tests, image build, Trivy scan
./scripts/ci-check.sh --no-docker   # lint and tests only
```

`.circleci/config.yml` mirrors the PR job for CircleCI. `.buildkite/pipeline.yml` runs the same checks and, on `main`, `scripts/buildkite-release.sh` on a self-hosted agent. The Buildkite release uses the agent's AWS credentials; it does not use GitHub OIDC. The local script is the offline fallback and needs `docker`, `hadolint`, `shellcheck`, and `trivy`.

The GitHub PR jobs run on a repository-scoped self-hosted runner. They are restricted to branches in this repository; fork pull requests are skipped so untrusted code does not run on the runner.

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
| `AWS_REGION` | `ap-southeast-1` |
| `AWS_ROLE_ARN` | `terraform output -raw github_deploy_role_arn` |
| `DOCKERHUB_USERNAME` | Your Docker Hub username |
| `EC2_INSTANCE_ID` | `i-...` of the Step 3 instance |

Set this repository secret under **Settings → Secrets and variables → Actions → Secrets**:

| Secret | Value |
|---|---|
| `DOCKER_HUB_KEY` | Docker Hub personal access token with Read & Write |

No AWS access keys are stored in GitHub. AWS calls assume the role through OIDC. The Docker Hub token lives only in the secret store; the EC2 instance pulls the public image anonymously, so no registry credential sits on the host.

## Terraform

`terraform/bootstrap` (local state) creates the S3 state bucket, GitHub OIDC role, and ECR repository. `terraform/envs/staging` and `terraform/envs/production` share `terraform/modules/app-runtime` (EC2, SG with only port 8080 open, least-privilege IAM role, CloudWatch log group with 14-day retention) and keep separate S3-locked state.

```bash
cd terraform/bootstrap
cp terraform.tfvars.example terraform.tfvars
terraform init
terraform apply

cd ../envs/staging
terraform init
terraform validate
terraform plan -var-file=staging.tfvars
terraform apply -var-file=staging.tfvars
curl -s http://$(terraform output -raw public_ip):8080/health
aws logs tail $(terraform output -raw log_group_name) --follow
terraform destroy -var-file=staging.tfvars   # after evidence is captured
```

Production is planned, not applied: `terraform -chdir=terraform/envs/production plan -var-file=production.tfvars`. The instance boots from user data (Docker install, pull, run) and retries until IMDS credentials appear. No SSH: access is SSM only, no key pair, no port 22.

## Tests

```bash
uv sync --frozen
uv run pytest --cov=app --cov-report=term-missing
uv run ruff check .
```

## Evidence

Workflow runs: [PR checks](https://github.com/swadhinbiswas/devops-assesment/actions/runs/43019232745) · [Release to Docker Hub + EC2](https://github.com/swadhinbiswas/devops-assesment/actions/runs/43033705446) · [Release to Terraform instance](https://github.com/swadhinbiswas/devops-assesment/actions/runs/43041045214)

Machine-readable proof lives in [`docs/evidence/`](docs/evidence/):

| File | Proves |
|---|---|
| `step2-pr-checks.md` | Lint, tests, coverage, hadolint, shellcheck, build, Trivy gate |
| `step2-release.md` | SHA + semver tags, multi-arch manifest |
| `step2-rollback.md` | Failed deploy rolls back with version restored |
| `step3-terraform.md` | Clean plan, apply outputs, state list, destroy |
| `step3-security.md` | SG 8080-only, scoped IAM, no static keys, no key pair |
| `step3-cloudwatch-sample.txt` | JSON app logs in CloudWatch (14-day retention) |

AWS compute was destroyed after testing per the task; the ECR images, Terraform state, and these files remain.

## License

MIT
