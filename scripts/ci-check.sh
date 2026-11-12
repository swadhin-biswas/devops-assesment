#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

./scripts/check_versions.sh

RUN_DOCKER=1
if [[ "${1:-}" == "--no-docker" ]]; then
  RUN_DOCKER=0
fi

echo "== lint and tests =="
uv sync --frozen
uv run ruff check .
uv run pytest --cov=app --cov-report=term-missing --cov-report=xml --cov-fail-under=90
./scripts/test_deploy_rollback.sh

echo
echo "== Dockerfile and shell lint =="
hadolint Dockerfile
shellcheck scripts/*.sh monitoring/alertmanager/entrypoint.sh

if [[ "$RUN_DOCKER" -eq 1 ]]; then
  if ! command -v docker >/dev/null 2>&1; then
    echo "docker is required for the image build" >&2
    exit 1
  fi
  if ! command -v trivy >/dev/null 2>&1; then
    echo "trivy is required for the image scan" >&2
    exit 1
  fi

  echo
  echo "== image build and scan =="
  tag="ci-$(git rev-parse --short HEAD 2>/dev/null || echo local)"
  docker build --tag "devops-task-app:${tag}" .
  trivy image --quiet --severity CRITICAL --exit-code 1 "devops-task-app:${tag}"
  docker images --format '{{.Repository}}:{{.Tag}} {{.Size}}' | grep "devops-task-app:${tag}"
fi

echo
echo "CI checks passed"
