#!/usr/bin/env bash
set -euo pipefail

: "${AWS_REGION:?AWS_REGION is required}"
: "${ECR_REGISTRY:?ECR_REGISTRY is required}"
: "${ECR_REPOSITORY:?ECR_REPOSITORY is required}"
: "${EC2_INSTANCE_ID:?EC2_INSTANCE_ID is required}"

COMMIT="${BUILDKITE_COMMIT:-$(git rev-parse HEAD)}"
BUILD_NUMBER="${BUILDKITE_BUILD_NUMBER:-$(date +%s)}"
APP_VERSION="0.1.${BUILD_NUMBER}"
IMAGE_TAG="v${APP_VERSION}"
IMAGE_URI="${ECR_REGISTRY}/${ECR_REPOSITORY}:${IMAGE_TAG}"
SHA_URI="${ECR_REGISTRY}/${ECR_REPOSITORY}:${COMMIT}"
BUILD_DATE="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
CACHE_DIR="${BUILDX_CACHE_DIR:-/tmp/buildkite-buildx-cache}"

log() {
  printf '%s %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$*"
}

die() {
  log "ERROR: $*" >&2
  exit 1
}

if [[ ! -e /proc/sys/fs/binfmt_misc/qemu-aarch64 ]]; then
  die "arm64 binfmt is not registered. Run: docker run --privileged --rm tonistiigi/binfmt --install arm64"
fi

log "logging in to $ECR_REGISTRY"
aws ecr get-login-password --region "$AWS_REGION" \
  | docker login --username AWS --password-stdin "$ECR_REGISTRY"

log "preparing buildx builder"
if ! docker buildx inspect buildkite-builder >/dev/null 2>&1; then
  docker buildx create --name buildkite-builder --driver docker-container
fi
docker buildx use buildkite-builder
docker buildx inspect --bootstrap >/dev/null

mkdir -p "$CACHE_DIR"

log "building $IMAGE_TAG for linux/amd64 and linux/arm64"
docker buildx build \
  --platform linux/amd64,linux/arm64 \
  --push \
  --tag "$IMAGE_URI" \
  --tag "$SHA_URI" \
  --build-arg APP_VERSION="$APP_VERSION" \
  --build-arg VCS_REF="$COMMIT" \
  --build-arg BUILD_DATE="$BUILD_DATE" \
  --cache-from "type=local,src=$CACHE_DIR" \
  --cache-to "type=local,dest=$CACHE_DIR,mode=max" \
  --provenance=true \
  --sbom=true \
  .

log "pushed $IMAGE_TAG and $COMMIT"
docker buildx imagetools inspect "$IMAGE_URI"

run_ssm() {
  local command="$1"
  local comment="$2"
  local parameters command_id status

  parameters=$(jq -cn --arg cmd "$command" '{commands: [$cmd]}')
  command_id=$(aws ssm send-command \
    --instance-ids "$EC2_INSTANCE_ID" \
    --document-name "AWS-RunShellScript" \
    --comment "$comment" \
    --parameters "$parameters" \
    --query 'Command.CommandId' \
    --output text)

  log "SSM $comment: $command_id"
  status=Pending
  for _ in $(seq 1 60); do
    status=$(aws ssm get-command-invocation \
      --command-id "$command_id" \
      --instance-id "$EC2_INSTANCE_ID" \
      --query Status \
      --output text 2>/dev/null || echo Pending)
    case "$status" in
      Success|Failed|Cancelled|TimedOut) break ;;
    esac
    sleep 5
  done

  aws ssm get-command-invocation \
    --command-id "$command_id" \
    --instance-id "$EC2_INSTANCE_ID" \
    --query StandardOutputContent \
    --output text
  aws ssm get-command-invocation \
    --command-id "$command_id" \
    --instance-id "$EC2_INSTANCE_ID" \
    --query StandardErrorContent \
    --output text >&2

  if [[ "$status" != "Success" ]]; then
    log "SSM $comment failed with status $status" >&2
    return 1
  fi
}

rollback() {
  log "rolling back to the previous image" >&2
  run_ssm \
    'if [ -f /opt/devops-task/previous_image ]; then /opt/devops-task/deploy.sh --rollback; else echo "no previous image"; fi' \
    "rollback" || true
}

if ! run_ssm "/opt/devops-task/deploy.sh $IMAGE_URI $APP_VERSION" "deploy"; then
  rollback
  exit 1
fi

if ! run_ssm "curl -fsS --max-time 5 http://127.0.0.1:8080/health" "smoke test"; then
  rollback
  exit 1
fi

log "release complete: $IMAGE_URI"
