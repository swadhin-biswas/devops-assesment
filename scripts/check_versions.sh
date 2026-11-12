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

# forbid KEY: fails when the file sets that key anywhere. Comments that
# mention the key are fine, so the match is anchored to the start of a line.
forbid() {
  local file=$1
  local key=$2
  if grep -Eq "^[[:space:]]*${key}:" "$ROOT/$file"; then
    printf 'version drift: %s must not set %s\n' "$file" "$key" >&2
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
# The app version must come from the image, never from the ConfigMap. The
# pod spec overrides the image's own ENV, so a hard-coded APP_VERSION would
# report a version that does not match the image actually running.
forbid charts/devops-task/values.yaml "APP_VERSION"
forbid k8s/configmap.yaml "APP_VERSION"
check k8s/deployment.yaml "devops-task:v$VERSION"
check terraform/envs/staging/staging.tfvars "devops-task:v$VERSION"
check terraform/envs/production/production.tfvars "devops-task:v$VERSION"

# The app version is derived from the image tag, never a second hard-coded
# value, so the container cannot report a version that differs from the tag.
check terraform/envs/staging/main.tf "app_version        = local.app_version"
check terraform/envs/production/main.tf "app_version        = local.app_version"
check terraform/envs/staging/main.tf 'trimprefix(local.image_tag, "v")'
check terraform/envs/production/main.tf 'trimprefix(local.image_tag, "v")'
check Makefile "\$\${APP_VERSION:-$VERSION}"
check .env.example "APP_VERSION=$VERSION"

# The Terraform user-data verifies this checksum; keep it in sync.
deploy_sha="$(sha256sum "$ROOT/scripts/deploy.sh" | awk '{print $1}')"
if ! grep -Fq -- "$deploy_sha" "$ROOT/terraform/modules/app-runtime/variables.tf"; then
  printf 'deploy checksum drift: terraform/modules/app-runtime/variables.tf does not contain %s\n' "$deploy_sha" >&2
  exit 1
fi

printf 'version %s is consistent; deploy script checksum %s\n' "$VERSION" "$deploy_sha"
