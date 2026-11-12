#!/usr/bin/env bash
set -euo pipefail

STATE_DIR="${STATE_DIR:-/opt/devops-task}"
APP_NAME="${APP_NAME:-devops-task-app}"
HEALTH_URL="${HEALTH_URL:-http://127.0.0.1:8080/health}"
HEALTH_RETRIES="${HEALTH_RETRIES:-60}"
HEALTH_INTERVAL="${HEALTH_INTERVAL:-5}"

log() {
  printf '%s %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$*"
}

die() {
  log "ERROR: $*" >&2
  exit 1
}

MODE="deploy"
if [[ "${1:-}" == "--rollback" ]]; then
  MODE="rollback"
  shift
fi

IMAGE_URI=""
VERSION=""
if [[ "$MODE" == "deploy" ]]; then
  IMAGE_URI="${1:-}"
  VERSION="${2:-${APP_VERSION:-unknown}}"
  [[ -n "$IMAGE_URI" ]] || die "usage: $0 <image-uri> [version] | $0 --rollback"
fi

if [[ -f "$STATE_DIR/app.env" ]]; then
  set -a
  # shellcheck source=/dev/null
  . "$STATE_DIR/app.env"
  set +a
fi

# LOG_GROUP is optional. When empty, the container uses the default
# json-file log driver instead of CloudWatch Logs.
LOG_GROUP="${LOG_GROUP:-}"
APP_ENV="${APP_ENV:-production}"
LOG_LEVEL="${LOG_LEVEL:-INFO}"

mkdir -p "$STATE_DIR"
CURRENT_FILE="$STATE_DIR/current_image"
PREVIOUS_FILE="$STATE_DIR/previous_image"
CURRENT_VERSION_FILE="$STATE_DIR/current_version"
PREVIOUS_VERSION_FILE="$STATE_DIR/previous_version"

if [[ "$MODE" == "rollback" ]]; then
  [[ -f "$PREVIOUS_FILE" ]] || die "no previous image to roll back to"
  IMAGE_URI=$(cat "$PREVIOUS_FILE")
  if [[ -f "$PREVIOUS_VERSION_FILE" ]]; then
    VERSION=$(cat "$PREVIOUS_VERSION_FILE")
  else
    VERSION="${1:-rollback}"
  fi
fi

start_container() {
  local image="$1"
  local -a log_opts=()

  if [[ -n "$LOG_GROUP" ]]; then
    : "${AWS_REGION:?AWS_REGION is required for CloudWatch logging}"
    log_opts=(
      --log-driver awslogs
      --log-opt "awslogs-region=$AWS_REGION"
      --log-opt "awslogs-group=$LOG_GROUP"
      --log-opt "awslogs-stream=$APP_ENV"
    )
  fi

  docker rm -f "$APP_NAME" >/dev/null 2>&1 || true
  docker run -d \
    --name "$APP_NAME" \
    --restart unless-stopped \
    --init \
    --read-only \
    --tmpfs /tmp:size=16m,mode=1777 \
    --cap-drop ALL \
    --security-opt no-new-privileges:true \
    --memory 256m \
    --cpus 0.5 \
    -p 8080:8080 \
    "${log_opts[@]}" \
    -e APP_ENV="$APP_ENV" \
    -e APP_VERSION="$VERSION" \
    -e APP_PORT=8080 \
    -e LOG_LEVEL="$LOG_LEVEL" \
    "$image" >/dev/null
}

wait_for_health() {
  local response
  for _ in $(seq 1 "$HEALTH_RETRIES"); do
    if ! response=$(curl -fsS --max-time 2 "$HEALTH_URL" 2>/dev/null); then
      sleep "$HEALTH_INTERVAL"
      continue
    fi
    # A 200 from the wrong build is not a successful deploy.
    if [[ "$VERSION" == "unknown" ]] || printf '%s' "$response" | grep -q "\"version\":\"$VERSION\""; then
      return 0
    fi
    sleep "$HEALTH_INTERVAL"
  done

  return 1
}

log "pulling $IMAGE_URI"
docker pull "$IMAGE_URI"

# Only replace the rollback target after the new image is available.
if [[ "$MODE" == "deploy" && -f "$CURRENT_FILE" ]]; then
  cp "$CURRENT_FILE" "$PREVIOUS_FILE"
  if [[ -f "$CURRENT_VERSION_FILE" ]]; then
    cp "$CURRENT_VERSION_FILE" "$PREVIOUS_VERSION_FILE"
  fi
fi

log "starting $VERSION"
start_container "$IMAGE_URI"
printf '%s\n' "$IMAGE_URI" >"$CURRENT_FILE"
printf '%s\n' "$VERSION" >"$CURRENT_VERSION_FILE"
docker ps --filter name="$APP_NAME" --format '{{.Names}} {{.Status}} {{.Ports}}' || true
sleep 5

if wait_for_health; then
  log "healthy: $VERSION"
  if [[ "$MODE" == "deploy" ]]; then
    docker image prune -f --filter "until=168h" >/dev/null 2>&1 || true
  fi
  exit 0
fi

log "health check failed for $VERSION" >&2
docker logs --tail 50 "$APP_NAME" >&2 || true

if [[ "$MODE" == "deploy" && -f "$PREVIOUS_FILE" ]]; then
  previous_image=$(cat "$PREVIOUS_FILE")
  if [[ -f "$PREVIOUS_VERSION_FILE" ]]; then
    VERSION=$(cat "$PREVIOUS_VERSION_FILE")
  fi
  log "rolling back to $previous_image ($VERSION)" >&2
  start_container "$previous_image"
  printf '%s\n' "$previous_image" >"$CURRENT_FILE"
  printf '%s\n' "$VERSION" >"$CURRENT_VERSION_FILE"

  if wait_for_health; then
    log "rollback healthy: $previous_image ($VERSION)" >&2
    exit 1
  fi

  log "rollback failed: $previous_image" >&2
fi

exit 1
