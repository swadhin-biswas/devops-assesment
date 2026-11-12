#!/usr/bin/env bash
# Fail if a release version is hard-coded out of sync with VERSION.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VERSION="$(tr -d '[:space:]' < "$ROOT/VERSION")"

check() {
  local file=$1
  local pattern=$2
  if ! grep -Fq -- "$pattern" "$ROOT/$file"; then
    printf 'version drift: %s does not contain %q\n' "$file" "$pattern" >&2
    exit 1
  fi
}

check app/config.py "default=\"$VERSION\""
check Dockerfile "ARG APP_VERSION=$VERSION"
check docker-compose.yml "APP_VERSION:-$VERSION"
check pyproject.toml "version = \"$VERSION\""
check charts/devops-task/Chart.yaml "version: $VERSION"
check charts/devops-task/Chart.yaml "appVersion: \"$VERSION\""
check charts/devops-task/values.yaml "tag: v$VERSION"
check charts/devops-task/values.yaml "APP_VERSION: \"$VERSION\""
check k8s/configmap.yaml "APP_VERSION: \"$VERSION\""
check k8s/deployment.yaml "devops-task:v$VERSION"
check terraform/envs/staging/staging.tfvars "devops-task:v$VERSION"
check terraform/envs/production/production.tfvars "devops-task:v$VERSION"
check terraform/modules/app-runtime/variables.tf "default     = \"$VERSION\""
check Makefile "\$\${APP_VERSION:-$VERSION}"
check .env.example "APP_VERSION=$VERSION"

# The Terraform user-data verifies this checksum; keep it in sync.
deploy_sha="$(sha256sum "$ROOT/scripts/deploy.sh" | awk '{print $1}')"
if ! grep -Fq -- "$deploy_sha" "$ROOT/terraform/modules/app-runtime/variables.tf"; then
  printf 'deploy checksum drift: terraform/modules/app-runtime/variables.tf does not contain %s\n' "$deploy_sha" >&2
  exit 1
fi

printf 'version %s is consistent; deploy script checksum %s\n' "$VERSION" "$deploy_sha"
