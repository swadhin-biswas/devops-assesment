#!/usr/bin/env bash
# Create or update the Buildkite pipeline from .buildkite/pipeline.yml and
# trigger one build. Uses native Buildkite steps, so it never hits the
# github-actions importer's restrictions (for example, its checkout adapter
# rejects an explicit actions/checkout "repository" input).
#
# Required environment:
#   BUILDKITE_API_KEY   Buildkite API token (pipelines + builds scope)
# Optional:
#   BUILDKITE_ORG       organization slug; discovered when the token can list orgs
#   BUILDKITE_PIPELINE  pipeline slug (default: devops-task)
set -euo pipefail

: "${BUILDKITE_API_KEY:?BUILDKITE_API_KEY is required}"
api="https://api.buildkite.com/v2"
auth="Authorization: Bearer ${BUILDKITE_API_KEY}"
pipeline="${BUILDKITE_PIPELINE:-devops-task}"
org="${BUILDKITE_ORG:-}"

repo_url="${GITHUB_REPOSITORY_URL:-$(git config --get remote.origin.url)}"
repo_url="${repo_url/git@github.com:/https://github.com/}"
repo_url="${repo_url%.git}"

if [[ -z $org ]]; then
  orgs=$(curl -fsS -H "$auth" "$api/organizations" | jq -r '.[].slug')
  count=$(printf '%s\n' "$orgs" | sed '/^$/d' | wc -l)
  if [[ $count -ne 1 ]]; then
    orgs_list=$(printf '%s\n' "$orgs" | tr '\n' ' ')
    printf 'Set BUILDKITE_ORG. Visible organizations: %s\n' "$orgs_list" >&2
    exit 1
  fi
  org=$orgs
fi

config=$(cat .buildkite/pipeline.yml)
payload=$(jq -cn \
  --arg name "$pipeline" \
  --arg repo "$repo_url" \
  --arg config "$config" \
  '{name: $name, repository: $repo, default_branch: "main", configuration: $config}')

if curl -fsS -H "$auth" "$api/organizations/$org/pipelines/$pipeline" >/dev/null 2>&1; then
  curl -fsS -X PATCH -H "$auth" -H 'Content-Type: application/json' \
    -d "$payload" "$api/organizations/$org/pipelines/$pipeline" >/dev/null
  printf 'updated pipeline %s/%s\n' "$org" "$pipeline"
else
  curl -fsS -X POST -H "$auth" -H 'Content-Type: application/json' \
    -d "$payload" "$api/organizations/$org/pipelines" >/dev/null
  printf 'created pipeline %s/%s\n' "$org" "$pipeline"
fi

if command -v gh >/dev/null 2>&1 && gh auth status >/dev/null 2>&1; then
  gh variable set BUILDKITE_ORG --body "$org"
  gh variable set BUILDKITE_PIPELINE --body "$pipeline"
fi

commit=$(git rev-parse HEAD)
branch=$(git rev-parse --abbrev-ref HEAD)
build_payload=$(jq -cn --arg c "$commit" --arg b "$branch" \
  '{commit: $c, branch: $b, message: "bootstrap from scripts/buildkite-setup.sh"}')
response=$(curl -fsS -X POST -H "$auth" -H 'Content-Type: application/json' \
  -d "$build_payload" "$api/organizations/$org/pipelines/$pipeline/builds")
printf '%s\n' "$response" | jq '{number, state, web_url, commit}'
