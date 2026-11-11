# DevOps task: FastAPI service, end to end

A small FastAPI service taken through the full assessment: hardened container, CI/CD with security gates, Terraform for AWS, Kubernetes manifests, a full Grafana/Prometheus/Loki stack, and a host health script.

[![PR checks](https://github.com/swadhinbiswas/devops-assesment/actions/workflows/pr.yml/badge.svg)](https://github.com/swadhinbiswas/devops-assesment/actions/workflows/pr.yml)
![tests](https://img.shields.io/badge/tests-10%20passed-brightgreen)
![coverage](https://img.shields.io/badge/coverage-94%25-brightgreen)
![image size](https://img.shields.io/badge/image-84%20MB-blue)
![license](https://img.shields.io/badge/license-MIT-blue)

All seven task steps are complete on `main`. The final image is 84 MB, 10 tests cover 94% of the app code, every commit is signed, and CI is green. Every command below was run on my machine; the raw output lives in [`docs/evidence/`](docs/evidence/) and the key excerpts are inline.

## Contents

- [How this maps to the assessment](#how-this-maps-to-the-assessment)
- [Repository layout](#repository-layout)
- [Architecture](#architecture)
- [Prerequisites](#prerequisites)
- [Quick start](#quick-start)
  - [1. Run the app](#1-run-the-app)
  - [2. Run the observability stack](#2-run-the-observability-stack)
  - [3. Run the tests](#3-run-the-tests)
  - [4. Run the health script](#4-run-the-health-script)
  - [5. Terraform](#5-terraform-ec2--cloudwatch--s3-state)
  - [6. Kubernetes](#6-kubernetes-kind)
- [Observability details](#observability-details)
- [CI/CD](#cicd)
- [Deployment & rollback strategy](#deployment--rollback-strategy)
- [Security considerations](#security-considerations)
- [Design decisions](#design-decisions)
- [AWS cost estimate](#aws-cost-estimate-production-ap-southeast-1-on-demand)
- [What I would improve with more time](#what-i-would-improve-with-more-time)
- [AI usage](#ai-usage)
- [Evidence](#evidence)
- [License](#license)

## How this maps to the assessment

| Step | What the task asks for | Where to look in this README | Raw evidence |
|---|---|---|---|
| 1 | Endpoints, env config, JSON logs, tests, Dockerfile, Compose | [Run the app](#1-run-the-app), [tests](#3-run-the-tests), [design decisions](#design-decisions) | [step1-app.md](docs/evidence/step1-app.md) |
| 2 | PR gates, release pipeline with rollback | [CI/CD](#cicd) | [step2-pr-checks.md](docs/evidence/step2-pr-checks.md), [step2-release.md](docs/evidence/step2-release.md), [step2-rollback.md](docs/evidence/step2-rollback.md) |
| 3 | EC2, IAM, user data, CloudWatch, remote state | [Terraform](#5-terraform-ec2--cloudwatch--s3-state) | [step3-terraform.md](docs/evidence/step3-terraform.md), [step3-security.md](docs/evidence/step3-security.md), [step3-cloudwatch-sample.txt](docs/evidence/step3-cloudwatch-sample.txt) |
| 4 | Deployment, Service, Ingress, HPA, rollout and undo | [Kubernetes](#6-kubernetes-kind) | [step4-k8s.md](docs/evidence/step4-k8s.md) |
| 5 | Six monitoring components, three dashboards, four alerts | [Observability stack](#2-run-the-observability-stack), [details](#observability-details) | [step5-observability.md](docs/evidence/step5-observability.md) |
| 6 | `system_health.sh` with thresholds, JSON, rotation, timer | [Health script](#4-run-the-health-script) | [step6-script.md](docs/evidence/step6-script.md) |
| 7 | This README | every section | [`docs/evidence/`](docs/evidence/) |

## Repository layout

| Path | What it is |
|---|---|
| [`app/`](app/) | Application code: [`main.py`](app/main.py) (routes), [`config.py`](app/config.py), [`logging.py`](app/logging.py), [`metrics.py`](app/metrics.py) |
| [`tests/`](tests/) | pytest suite (10 tests) |
| [`Dockerfile`](Dockerfile) | Multi-stage build: Alpine 3.23, non-root UID 10001 |
| [`docker-compose.yml`](docker-compose.yml) | The app plus the `monitoring` profile |
| [`monitoring/prometheus/prometheus.yml`](monitoring/prometheus/prometheus.yml) | Scrape config; alert rules in [`alerts.yml`](monitoring/prometheus/alerts.yml) |
| [`monitoring/loki/loki-config.yml`](monitoring/loki/loki-config.yml) | Loki config, 168h retention |
| [`monitoring/alloy/config.alloy`](monitoring/alloy/config.alloy) | Docker container discovery and JSON log parsing |
| [`monitoring/grafana/`](monitoring/grafana/) | Provisioned datasources and the three dashboards: [`application`](monitoring/grafana/dashboards/application.json), [`host`](monitoring/grafana/dashboards/host.json), [`containers`](monitoring/grafana/dashboards/containers.json) |
| [`k8s/`](k8s/) | Deployment, Service, Ingress, ConfigMap, HPA, [`secret.example.yaml`](k8s/secret.example.yaml) |
| [`terraform/`](terraform/) | [`bootstrap/`](terraform/bootstrap/main.tf) (state bucket, OIDC role, ECR), shared [`modules/app-runtime/`](terraform/modules/app-runtime/main.tf), [`envs/staging/`](terraform/envs/staging/main.tf), [`envs/production/`](terraform/envs/production/main.tf) |
| [`scripts/system_health.sh`](scripts/system_health.sh) | Host health probe (task step 6) |
| [`scripts/systemd/system-health.timer`](scripts/systemd/system-health.timer) | Timer, with its [`service`](scripts/systemd/system-health.service), to run the probe every 5 minutes |
| [`scripts/deploy.sh`](scripts/deploy.sh) | EC2 deploy and rollback over SSM |
| [`scripts/ci-check.sh`](scripts/ci-check.sh) | The CI checks, runnable locally |
| [`.github/workflows/pr.yml`](.github/workflows/pr.yml) and [`release.yml`](.github/workflows/release.yml) | PR gates and the release/deploy pipeline |
| [`.circleci/config.yml`](.circleci/config.yml), [`.buildkite/pipeline.yml`](.buildkite/pipeline.yml) | Fallback pipelines running the same checks |
| [`Makefile`](Makefile) | lint, test, build targets |
| [`pyproject.toml`](pyproject.toml), [`uv.lock`](uv.lock) | Dependencies, locked |
| [`.env.example`](.env.example) | Template for `.env` (copy it, fill in the Grafana credentials) |
| [`docs/evidence/`](docs/evidence/) | Proof for each task step (table under Evidence) |
| [`docs/images/`](docs/images/) | Dashboard and alert screenshots |

## Architecture

```mermaid
flowchart LR
    dev[Developer] -->|commit + PR| gh[GitHub]
    gh --> ci["PR checks: ruff · pytest 80% gate<br/>hadolint · shellcheck · build · Trivy CRITICAL gate"]
    ci -->|merge main| rel["Release: buildx amd64+arm64<br/>tags = commit SHA + v0.1.N"]
    rel --> hub[(Docker Hub<br/>swadhinbiswas/devops-task)]
    hub -->|SSM RunCommand| dep["scripts/deploy.sh<br/>deploy → smoke /health → auto-rollback"]
    dep --> ec2["EC2 (Terraform)<br/>user-data: Docker + container<br/>logs → CloudWatch, 14-day retention"]
    hub -.->|kubectl apply -k| k8s["kind cluster<br/>Deployment 2× · probes · HPA CPU 70%"]

    subgraph obs ["Observability — docker compose --profile monitoring"]
        app["app :8080 /metrics"] --> prom[Prometheus · 15d retention]
        ne[node-exporter] --> prom
        cad[cAdvisor] --> prom
        alloy["Alloy: Docker discovery<br/>+ JSON log parse"] --> loki[(Loki · 7d retention)]
        prom --> graf["Grafana :3000<br/>3 dashboards + 4 alert rules"]
        loki --> graf
    end
```

The same image deploys two ways: to EC2 (Terraform provisions the instance, SSM runs the deploy, logs go to CloudWatch) and to a local kind cluster (manifests only). Prometheus scrapes the app, node-exporter, and cAdvisor; Alloy ships parsed container logs to Loki; Grafana reads both.

## Prerequisites

| Tool | Needed for | Tested with |
|---|---|---|
| Docker + Compose v2 | app + observability stack | Docker 29, Compose 5.7 |
| [uv](https://docs.astral.sh/uv/) (Python 3.12) | tests, local app run | uv 0.9 |
| kind + kubectl | Kubernetes step | kind v0.30 |
| Terraform + AWS CLI | cloud steps | TF 1.14, AWS CLI 2 |

## Quick start

### 1. Run the app

```bash
cp .env.example .env          # APP_PORT/APP_ENV/LOG_LEVEL/APP_VERSION
docker compose up -d --build
curl -s http://127.0.0.1:8080/
curl -s http://127.0.0.1:8080/health
docker compose logs -f app    # JSON logs on stdout
```

`GET /` returns exactly `{"message":"Hello from DevOps Task!","status":"running","version":"0.1.0"}`.

From the running service:

```text
$ curl -s http://127.0.0.1:8080/
{"message":"Hello from DevOps Task!","status":"running","version":"0.1.0"}
$ curl -s http://127.0.0.1:8080/health
{"status":"ok","version":"0.1.0","environment":"development"}
```

The service reads every setting from the environment, logs one JSON object per line to stdout, and shuts down gracefully on SIGTERM. Same image, run with `APP_PORT=8090 APP_ENV=staging LOG_LEVEL=DEBUG` (timestamps trimmed):

```text
{"timestamp":"...","level":"INFO","logger":"app","message":"application startup","environment":"staging","version":"0.1.0","event":"startup"}
{"timestamp":"...","level":"INFO","logger":"app","message":"request completed","environment":"staging","version":"0.1.0","event":"request","method":"GET","path":"/health","status_code":200,"duration_ms":0.396}
{"timestamp":"...","level":"INFO","logger":"app","message":"application shutdown","environment":"staging","version":"0.1.0","event":"shutdown"}
{"timestamp":"...","level":"INFO","logger":"uvicorn.error","message":"Application shutdown complete.","environment":"staging","version":"0.1.0"}
```

SIGTERM was sent between the request and the shutdown lines; the process exited 143 (128 + 15). The final image is 84 MB and runs as UID 10001 from a digest-pinned Alpine 3.23 base with a HEALTHCHECK on `/health` and OCI labels; the Dockerfile and compose hardening are detailed in [step1-app.md](docs/evidence/step1-app.md).

### 2. Run the observability stack

```bash
# .env must contain GF_SECURITY_ADMIN_USER and GF_SECURITY_ADMIN_PASSWORD
docker compose --profile monitoring up -d
docker compose --profile monitoring ps
```

Open Grafana at `http://127.0.0.1:3000` and sign in with the `GF_SECURITY_ADMIN_*` values from `.env`. There is no external Grafana account: the admin user is created from `.env` on first start, and Compose refuses to start Grafana if the variables are missing. Data sources (Prometheus, Loki) and all three dashboards are provisioned from files under `monitoring/`, so nothing is configured by hand in the UI:

| Dashboard | Panels |
|---|---|
| Application (`devops-task-application`) | request rate, 5xx error ratio, latency p50/p95/p99, Loki log panel |
| Host (`devops-task-host`) | CPU, memory, disk, network (Node Exporter) |
| Containers (`devops-task-containers`) | per-container CPU, memory, memory vs limit (cAdvisor) |

![Application dashboard](docs/images/application-dashboard.png)
![Host dashboard](docs/images/host-dashboard.png)
![Containers dashboard](docs/images/containers-dashboard.png)

Prometheus keeps 15 days (`--storage.tsdb.retention.time=15d`); Loki keeps 7 days (`retention_period: 168h`). Only Grafana publishes a host port (127.0.0.1:3000); everything else talks over the internal `monitoring` network. Grafana joins both networks because this Docker daemon does not publish ports for containers on an internal-only network. Image versions are pinned; cAdvisor is `0.54.0` with `--docker_only=true`, the build that resolves container names on Docker 29 / containerd-snapshotter hosts (0.56.x panics there). Alert rules, an error-spike walkthrough, the host-mount table, and the collection proof are in [Observability details](#observability-details).

### 3. Run the tests

```bash
uv sync --frozen
uv run pytest --cov=app --cov-report=term-missing   # 10 tests, 94% coverage
uv run ruff check .
make ci                                             # lint + tests + build + Trivy
```

Coverage from the suite:

```text
app/config.py        27      1      4      1    94%   33
app/logging.py       33      1      8      1    95%   38
app/main.py          53      3      4      0    95%   22-24
-------------------------------------------------------------
TOTAL               124      6     18      3    94%

10 passed in 0.45s
```

### 4. Run the health script

`scripts/system_health.sh` collects CPU, memory, disk usage for all mounted filesystems, load average, and the top 5 processes by memory; appends a timestamped entry to `health_log.txt` (or `--json` for JSONL); prints `[WARNING]`/`[CRITICAL]` on stderr; and exits `0` healthy / `1` warning / `2` critical / `3` usage error.

```bash
./scripts/system_health.sh                       # one-shot, defaults: --disk 80 --cpu 90 --mem 85
./scripts/system_health.sh --json --disk 70      # JSONL entry, lower disk threshold
./scripts/system_health.sh --help                # all flags, defaults, cron example
```

Each exit path was exercised against the thresholds:

| Run | Command | Exit |
|---|---|---|
| Healthy | `./scripts/system_health.sh` | 0 |
| Warning | `./scripts/system_health.sh --disk 1` | 1 |
| Critical | `./scripts/system_health.sh --mem-critical 1` | 2 |
| Usage error | `./scripts/system_health.sh --bogus` | 3 |

`shellcheck -x scripts/system_health.sh` exits 0, and the same check runs in CI. A healthy text entry and a JSON entry:

```text
[2026-11-11T17:25:15Z] healthy cpu=12.3% mem=44.4% load=1.26 cores=20 disks=/=20% /home=20% /var/log=20% /.snapshots=20% /var/cache/pacman/pkg=20% /boot=12% top_mem=qs(4244):3.7% chromium(370061):2.3% Telegram(590167):2.0% chromium(7992):1.9% zed-editor(22696):1.8%
```

```json
{"timestamp":"2026-11-11T17:25:16Z","status":"healthy","cpu_percent":11.7,"mem_percent":44.5,"load1":0.8,"cores":20,"disks":[{"mount":"/","percent":20},{"mount":"/home","percent":20},{"mount":"/var/log","percent":20},{"mount":"/.snapshots","percent":20},{"mount":"/var/cache/pacman/pkg","percent":20},{"mount":"/boot","percent":12}],"top_processes":[{"pid":4244,"name":"qs","percent_memory":3.7},{"pid":370061,"name":"chromium","percent_memory":2.3},{"pid":590167,"name":"Telegram","percent_memory":2.0},{"pid":7992,"name":"chromium","percent_memory":1.9},{"pid":22696,"name":"zed-editor","percent_memory":1.8}],"warnings":[],"criticals":[]}
```

Rotation was verified with `HEALTH_LOG_MAX_BYTES=250 HEALTH_LOG_KEEP=2` over six runs: the current file, `.1` and `.2` exist, and the oldest is deleted (`.3` never appears). To run the probe every 5 minutes, install the systemd units from `scripts/systemd/`:

```bash
sudo cp scripts/system_health.sh /usr/local/bin/
sudo cp scripts/systemd/system-health.{service,timer} /etc/systemd/system/
sudo systemctl daemon-reload && sudo systemctl enable --now system-health.timer
```

A cron alternative (`*/5 * * * *`) is in `--help`. The timer is the monitoring integration point: exit 1/2 mark the unit failed for `systemctl --failed` or a watchdog.

### 5. Terraform (EC2 + CloudWatch + S3 state)

```bash
cd terraform/bootstrap           # S3 state bucket, GitHub OIDC role, ECR (local state)
cp terraform.tfvars.example terraform.tfvars
terraform init && terraform apply

cd ../envs/staging
terraform init
terraform validate
terraform plan -var-file=staging.tfvars
terraform apply -var-file=staging.tfvars
curl -s http://$(terraform output -raw public_ip):8080/health
aws logs tail $(terraform output -raw log_group_name) --follow
terraform destroy -var-file=staging.tfvars   # after evidence is captured
```

Apply outputs and the destroy from the staging run:

```text
instance_id   = "i-087d5d7936610b736"
log_group_name = "/aws/ec2/devops-task/staging"
public_ip     = "18.143.167.212"

Destroy complete! Resources: 7 destroyed.
```

What the applied environment showed:

- Security group ingress: one rule, TCP 8080 from 0.0.0.0/0. No SSH, no other ports.
- Instance profile policy: `logs:CreateLogStream` and `logs:PutLogEvents` on the staging log group only, plus `AmazonSSMManagedInstanceCore` for the SSM deploy channel.
- `aws iam list-access-keys` for the local user returned `[]`; the instance has `"Key": null` (no key pair).
- Log group retention: 14 days. A real JSON log line from CloudWatch is in [step3-cloudwatch-sample.txt](docs/evidence/step3-cloudwatch-sample.txt).

Remote state, from `terraform/envs/staging/main.tf`:

```hcl
backend "s3" {
  bucket       = "devops-task-tfstate-33b24359cdc06619b607c93fe3"
  key          = "staging/terraform.tfstate"
  region       = "ap-southeast-1"
  encrypt      = true
  use_lockfile = true
}
```

There is no local state file; `ls terraform/envs/staging/*.tfstate` returns nothing and the state list is read through this backend. `use_lockfile` is Terraform's S3-native locking, which is why `required_version` is `>= 1.10.0`.

<details>
<summary>Terraform state (10 resources)</summary>

```text
module.runtime.data.aws_ami.ubuntu
module.runtime.data.aws_subnets.default
module.runtime.data.aws_vpc.default
module.runtime.aws_cloudwatch_log_group.app
module.runtime.aws_iam_instance_profile.instance
module.runtime.aws_iam_role.instance
module.runtime.aws_iam_role_policy.logs
module.runtime.aws_iam_role_policy_attachment.ssm
module.runtime.aws_instance.app
module.runtime.aws_security_group.app
```
</details>

`terraform/envs/staging` and `envs/production` share `terraform/modules/app-runtime` (EC2, security group with only port 8080, least-privilege IAM role, CloudWatch log group with 14-day retention) with separate S3-locked state. Production is planned but not applied: `terraform -chdir=terraform/envs/production plan -var-file=production.tfvars`. The instance boots from user data (Docker install, pull, run) and retries until IMDS credentials appear. No SSH: SSM only, no key pair, no port 22.

If the account already has the GitHub OIDC provider, import it first:

```bash
terraform import aws_iam_openid_connect_provider.github \
  arn:aws:iam::<account-id>:oidc-provider/token.actions.githubusercontent.com
```

### 6. Kubernetes (kind)

```bash
kind create cluster --name devops-task
kubectl create secret generic devops-task-secret \
  --from-literal=APP_ENV=staging \
  --from-literal=LOG_LEVEL=INFO
kubectl apply -k k8s/
kubectl rollout status deployment/devops-task
kubectl get pods,svc,hpa
kubectl port-forward svc/devops-task 8080:80
curl -s localhost:8080/health
```

Only [`k8s/secret.example.yaml`](k8s/secret.example.yaml) is committed; the real Secret is created in the cluster. 2 replicas, `maxUnavailable: 0`, liveness/readiness/startup probes on `/health`, requests `100m/64Mi`, limits `500m/256Mi`, UID 10001, read-only root filesystem, all capabilities dropped, HPA on CPU 70% (min 2, max 5). Zero-downtime update and rollback, proven with a 900-request loop against the Service (900/900 HTTP 200; `preStop: sleep 15` drains terminating pods), and again with a rollout to `v0.1.7` followed by `rollout undo`:

```bash
kubectl set image deployment/devops-task app=swadhinbiswas/devops-task:v0.1.7
kubectl rollout status deployment/devops-task
kubectl rollout undo deployment/devops-task
kubectl rollout status deployment/devops-task
```

Output from this kind cluster:

```text
$ kubectl set image deployment/devops-task app=swadhinbiswas/devops-task:v0.1.7
deployment.apps/devops-task image updated
$ kubectl rollout status deployment/devops-task
Waiting for deployment "devops-task" rollout to finish: 0 out of 2 new replicas have been updated...
Waiting for deployment "devops-task" rollout to finish: 1 old replicas are pending termination...
deployment "devops-task" successfully rolled out
$ kubectl rollout undo deployment/devops-task
deployment.apps/devops-task rolled back
$ kubectl rollout status deployment/devops-task
Waiting for deployment "devops-task" rollout to finish: 1 out of 2 new replicas have been updated...
deployment "devops-task" successfully rolled out
```

HPA on the same cluster:

```text
NAME          REFERENCE                TARGETS       MINPODS   MAXPODS   REPLICAS   AGE
devops-task   Deployment/devops-task   cpu: 4%/70%   2         5         2          153m
```

For EKS: AWS Load Balancer Controller with ACM TLS instead of ingress-nginx, External Secrets Operator + Secrets Manager instead of a generated Secret, Karpenter or Cluster Autoscaler for nodes, IRSA / Pod Identity instead of instance roles, and managed Prometheus/Grafana or kube-prometheus-stack with remote storage.

## Observability details

### Collection proof

Prometheus targets, all `up`:

```text
app            up
node-exporter  up
cadvisor       up
```

The rule file loads four alerts (`AppInstanceDown`, `HighErrorRate`, `HostDiskUsageHigh`, `ContainerMemoryNearLimit`), all inactive at capture time. Alloy parses the app's JSON logs and keeps the low-cardinality labels `level` and `path`; a Loki stream:

```text
labels: {'container': 'devops-task-app-1', 'detected_level': 'INFO', 'level': 'INFO', 'path': '/health', 'service': 'app', 'service_name': 'app'}
```

`AppInstanceDown` firing was verified by stopping the app for three minutes, then restarting it:

![Alert firing](docs/images/alert-firing.png)

### Alert rules

Prometheus loads `monitoring/prometheus/alerts.yml`. The rule group evaluates every 30s; the global scrape and evaluation interval is 15s.

| Alert | Fires when | For | Why this threshold and duration |
|---|---|---|---|
| `AppInstanceDown` | `up{job="app"} == 0` | 2m | A scrape every 15s means two minutes covers a missed scrape and a short restart, so a normal redeploy does not page anyone. |
| `HighErrorRate` | `sum(rate(app_errors_total[5m])) / sum(rate(app_requests_total[5m])) > 0.05` | 5m | 5% over five minutes separates a real regression from a few bad requests; 4xx are client errors and excluded. |
| `HostDiskUsageHigh` | root filesystem used > 80% | 10m | 80% leaves room to act before writes fail, and ten minutes ignores brief build or cache spikes. |
| `ContainerMemoryNearLimit` | working set / limit > 90% | 5m | OOMKill is close once a container approaches its limit; five minutes avoids reacting to a single GC spike. |

`AppInstanceDown` and `HighErrorRate` are critical severity; the two resource alerts are warnings.

### Investigating an error spike

The Application dashboard holds the metrics and the app logs in one view, so the first pass happens without switching tools.

1. Read the error rate panel first. `Error rate (5xx ratio)` uses `sum(rate(app_errors_total[5m])) / sum(rate(app_requests_total[5m]))`; it tells you when the spike started and how large it is. If it stays above 5% for five minutes, `HighErrorRate` fires.
2. Compare with latency. If p95/p99 climbed with the errors, something got slow (a dependency or the event loop). If latency stayed flat, requests are failing fast, which usually means a bad deploy or a config error.
3. Open the `App logs` Loki panel on the same dashboard. The query is `{service="app"} | json`; narrow it to errors with `{service="app", level="ERROR"}`, then use the `path` label to separate one broken endpoint from a global failure.
4. Correlate with the Host and Containers dashboards. CPU saturation, disk pressure, or a container memory curve approaching its limit around the same timestamp points to resource pressure; a memory curve that hits the limit suggests an OOMKill.
5. Check whether Prometheus can scrape at all. If `AppInstanceDown` is firing and the logs stop, the process crashed or a deploy failed, which is a different investigation from a bad request path.
6. Close the loop after the fix: the error ratio should drop back under 5% and the `ERROR` log lines should stop.

### Host access for monitoring

| Container | Mounts | Why |
|---|---|---|
| Node Exporter | `/proc`, `/sys`, `/` read-only | Reads host CPU, memory, disk and network counters. Nothing is written. |
| cAdvisor | `/`, `/var/run`, `/sys`, `/var/lib/docker`, `/dev/disk` read-only | Reads cgroups and Docker metadata to attribute CPU and memory per container; `--docker_only=true` restricts it to Docker containers. |
| Alloy | `/var/run/docker.sock` read-only | Docker service discovery finds containers and tails their logs. Read-only access cannot create or stop containers. |
| Grafana | no host mounts | Reads provisioned files and its own data volume. |

All host paths are mounted `:ro`. None of these containers runs `--privileged`, uses host networking, or adds capabilities. The app container goes further: read-only root filesystem, all capabilities dropped, `no-new-privileges`.

## CI/CD

Pull requests run ruff, pytest with an 80% coverage gate and a job-summary report, hadolint, shellcheck, an image build, and a Trivy scan that fails on CRITICAL findings. GitGuardian scans every push for leaked secrets.

| Job | Result | Covers |
|---|---|---|
| `lint-and-test` | pass | ruff, pytest with an 80% gate, coverage summary, deploy rollback test |
| `lint-containers` | pass | hadolint on the Dockerfile, shellcheck on `scripts/` |
| `image-scan` | pass | image build, Trivy with `severity: CRITICAL`, `exit-code: 1` |
| GitGuardian | pass | secret scan on every commit |

From PR run [43068495399](https://github.com/swadhinbiswas/devops-assesment/actions/runs/43068495399):

```text
TOTAL               124      6     18      3    94%
============================== 10 passed in 0.76s ==============================
deploy rollback test passed
```

The Trivy gate itself was proven on run 43019232745: `python:3.8-slim` reported 9 CRITICAL findings and the step exited 1.

Pushes to `main` build `linux/amd64` and `linux/arm64` images with GitHub Actions layer caching. Images are tagged with the full commit SHA and `v0.1.<run-number>`; `latest` is never used. The release logs in to Docker Hub, pushes, syncs `scripts/deploy.sh` to the instance over SSM, deploys, and smoke tests `/health`. If the deploy or smoke test fails, `scripts/deploy.sh --rollback` restores the previous image tag.

From release run [43041045214](https://github.com/swadhinbiswas/devops-assesment/actions/runs/43041045214):

```text
Cache restored successfully
"image.name": "swadhinbiswas/devops-task:v0.1.7,swadhinbiswas/devops-task:e61267a83954aa16d735606a1e90a320d13b34ae"
SSM command: 13d3e714-305d-4dc9-a541-093f92f9b565
2026-11-11T14:47:14Z healthy: 0.1.7
```

The registry serves one OCI index with both platforms:

```text
mediaType: application/vnd.oci.image.index.v1+json
platform: linux/amd64 digest: sha256:b13eb8ec9023d... size: 1242 bytes
platform: linux/arm64 digest: sha256:a2b2a988bb50a... size: 1242 bytes
```

The two `unknown/unknown` entries in that index are the SBOM and provenance attestations attached by buildx.

The failed-deploy rollback was proven live with a deliberately bogus tag (`hello-world:9.9.9-bogus`):

```text
rolling back to swadhinbiswas/devops-task:v0.1.8 (0.1.8)
rollback healthy: swadhinbiswas/devops-task:v0.1.8 (0.1.8)
```

Full transcript in [step2-rollback.md](docs/evidence/step2-rollback.md).

Repository configuration (in GitHub under Settings → Secrets and variables → Actions):

| Type | Name | Purpose |
|---|---|---|
| Variable | `AWS_REGION` | `ap-southeast-1` |
| Variable | `AWS_ROLE_ARN` | OIDC deploy role from `terraform output` |
| Variable | `DOCKERHUB_USERNAME` | Docker Hub account |
| Variable | `EC2_INSTANCE_ID` | `i-...` target instance |
| Secret | `DOCKER_HUB_KEY` | Docker Hub token (Read & Write) |

No AWS access keys exist anywhere. AWS calls assume the deploy role through GitHub OIDC; the instance pulls the public image anonymously, so no registry credential sits on the host either.

### Fallback checks

GitHub Actions is the primary pipeline; the same checks run locally with `make ci` or `./scripts/ci-check.sh --no-docker`. `.circleci/config.yml` mirrors the PR job for CircleCI; `.buildkite/pipeline.yml` runs the same checks and, on `main`, `scripts/buildkite-release.sh` on a self-hosted agent. The GitHub PR jobs run on a repository-scoped self-hosted runner restricted to branches in this repository; fork pull requests are skipped so untrusted code never runs on it.

## Deployment & rollback strategy

1. Build once, promote by tag. `main` merges produce exactly one multi-arch image, tagged with the commit SHA and `v0.1.N`. Environments never build their own image, so what CI tested is what runs.
2. Deploy atomically. The release job sends `scripts/deploy.sh <tag>` over SSM. The script records the currently running tag, pulls the new one, swaps the container, and waits for `/health` to answer.
3. Smoke before calling it done. `/health` must return 200 within the smoke window; anything else is a failed deploy.
4. Roll back automatically. On any deploy or smoke failure the script redeploys the previous tag (the `--rollback` path) and exits non-zero so the workflow fails visibly. This is the path proven by the bogus-tag run above.
5. On Kubernetes, `kubectl set image` plus `rollout status`, with `maxUnavailable: 0` so capacity never drops; `kubectl rollout undo` returns to the previous ReplicaSet revision (demonstrated, 900/900).
6. The service is stateless (no database schema), so image-level rollback is complete and there is no data migration to undo.

## Security considerations

- Secrets management: no secrets in the repo or CI logs. AWS access uses GitHub OIDC (no static keys), the Docker Hub token lives only in the Actions secret store, Grafana credentials come from `.env` (gitignored, with a fail-closed entrypoint), and the Kubernetes Secret is created at apply time (only an example file is committed). GitGuardian and GitHub secret scanning run on every PR.
- Image supply chain: both base images are pinned by digest (`@sha256:...`), and CI fails the build on Trivy CRITICAL findings; hadolint gates Dockerfile hygiene.
- IAM: the GitHub Actions deploy role is trusted only for this repo and `main`; the EC2 instance profile is scoped to ECR pull and CloudWatch Logs write. No static access keys anywhere, no SSH key pair on the instance (SSM Session Manager only).
- Network exposure: the security group opens only 8080, the app binds 127.0.0.1 locally, and in the monitoring stack only Grafana is published (on loopback) while everything else stays on the internal Docker network.
- Runtime hardening: containers run as UID 10001 with read-only root filesystems, all capabilities dropped, `no-new-privileges`, and resource limits; the Kubernetes `securityContext` mirrors this. cAdvisor and Node Exporter mount host paths read-only only (see the host access table above).

## Design decisions

| Decision | Choice | Why |
|---|---|---|
| Final image | Alpine 3.23, pinned by digest; shell + `apk` removed | 84 MB vs ~250 MB python:slim; keeps `python3` for the container `HEALTHCHECK`. Distroless would drop the shell entirely, making the healthcheck exec-only and incident debugging harder; the app is Python, so a Python base is required anyway. |
| Compute | EC2 + SSM over ECS/EKS | One stateless service: EC2 is the cheapest production-ready target, ECS adds scheduling value only at multi-service scale, EKS costs ~$73/mo control plane before nodes. K8s competency is demonstrated on kind without paying for it. |
| Registry | Docker Hub (public) | The EC2 instance pulls anonymously, so no registry credentials sit on the host and the deploy path needs no ECR login. ECR remains available in bootstrap for private-mode deployments. |
| Tagging | SHA + `v0.1.N`, never `latest` | Every deploy and rollback names an immutable tag; `latest` would make rollback nondeterministic. |
| Deploy channel | SSM Run Command | No inbound SSH surface, no key management; the instance role already allows `ssm:SendCommand` scoped to itself. |
| Log labels | `level` + `path` only | Both are low-cardinality: a few levels, bounded route templates. Request IDs and raw URLs stay in the line body; indexing them would explode Loki's stream count with traffic. |
| Prometheus retention | 15d | Local filesystem store; 15 days is enough to see weekly patterns without unbounded disk growth. Loki: 7d. |
| Alert thresholds | See Alert rules above | Each `for` duration tolerates transient spikes; the table explains every value. |

## AWS cost estimate (production, ap-southeast-1, on-demand)

| Item | Spec | Monthly |
|---|---|---|
| EC2 t3.micro | 2 vCPU / 1 GB, 24/7 | ~$7.60 |
| EBS gp3 root volume | 8 GB | ~$0.72 |
| EBS snapshots | 1 × 8 GB | ~$0.80 |
| CloudWatch Logs | ~1 GB ingest, 14-day retention | ~$0.70 |
| S3 (Terraform state + versions) | < 1 GB | ~$0.05 |
| Data transfer out | few GB (image pulls are inbound/free) | ~$0.25 |
| **Total** | single instance | **~$10/month** |

t3.small (2 GB) if the app needs headroom: about $15.2 plus storage, call it $18/month. The EKS path would add a ~$73 control plane and two t3.small nodes (~$30), so $103+/month before load balancers; that is why EC2 was chosen for this scope.

## What I would improve with more time

- Alert routing: Alertmanager (or Grafana Alerting) with Slack/PagerDuty receivers, silences, and dedup. The four rules currently have no notification channel.
- Staging environment in CI: deploy to a staging instance on PR merge, run an integration smoke suite, then promote the same tag to production.
- SLO burn-rate alerts on top of the static thresholds, with multi-window paging instead of single-metric trips.
- Loki on object storage (S3 backend) so retention and restarts don't depend on one node's disk.
- E2E tests (testcontainers) and a k6 load profile in CI, to catch latency regressions the unit tests can't.
- Dependency automation: Renovate for base images and Python dependencies, with a Trivy re-scan per bump.
- HA for the EC2 path: two instances behind an ALB in an ASG, or ECS with blue/green deploys.
- Containerd-native container metrics: this workstation runs Docker 29's containerd snapshotter; cAdvisor 0.54 works, but a containerd-native exporter would age better.

## AI usage

AI tools helped while building this: scaffolding config files, drafting PromQL and LogQL queries, and debugging. Three concrete examples: removing a deprecated Loki config field, pinning cAdvisor to 0.54.0 for Docker 29, and fixing a `/proc/stat` parsing bug in `system_health.sh` that made every run report 100% CPU. I reviewed and ran everything myself; the evidence files hold real output from my machine, and I can explain any part of this submission.

## Evidence

Workflow runs: [PR checks](https://github.com/swadhinbiswas/devops-assesment/actions/runs/43019232745), [Release to Docker Hub + EC2](https://github.com/swadhinbiswas/devops-assesment/actions/runs/43033705446), [Release to Terraform instance](https://github.com/swadhinbiswas/devops-assesment/actions/runs/43041045214).

Task-step proof, captured from real runs (all files in [`docs/evidence/`](docs/evidence/)):

| Task step | File | What it proves |
|---|---|---|
| 1 | [`step1-app.md`](docs/evidence/step1-app.md) | Endpoints, metrics, JSON logs, SIGTERM shutdown, tests, image and compose facts |
| 2 | [`step2-pr-checks.md`](docs/evidence/step2-pr-checks.md) | Lint, tests, coverage, hadolint, shellcheck, build, Trivy gate |
| 2 | [`step2-release.md`](docs/evidence/step2-release.md) | SHA + semver tags, cache hit, multi-arch manifest, deploy smoke result |
| 2 | [`step2-rollback.md`](docs/evidence/step2-rollback.md) | Failed deploy rolls back, previous version restored |
| 3 | [`step3-terraform.md`](docs/evidence/step3-terraform.md) | Clean plan, apply outputs, state list, destroy, S3 backend with lockfile |
| 3 | [`step3-security.md`](docs/evidence/step3-security.md) | SG 8080-only, scoped IAM, no static keys, no key pair |
| 3 | [`step3-cloudwatch-sample.txt`](docs/evidence/step3-cloudwatch-sample.txt) | JSON app logs in CloudWatch, 14-day retention |
| 4 | [`step4-k8s.md`](docs/evidence/step4-k8s.md) | Rolling update 900/900, HPA metrics, rollout undo output |
| 5 | [`step5-observability.md`](docs/evidence/step5-observability.md) | Prometheus targets, alert rules, firing proof, Loki parsed labels |
| 6 | [`step6-script.md`](docs/evidence/step6-script.md) | Shellcheck clean, exit codes, JSON, rotation, scheduling units |

Screenshots live in [`docs/images/`](docs/images/): `application-dashboard.png`, `host-dashboard.png`, `containers-dashboard.png`, and `alert-firing.png` (AppInstanceDown firing after the app was stopped for 3 minutes, then restored).

AWS compute was destroyed after testing, as the task asked; the ECR images, Terraform state, and these files remain.

## License

MIT
