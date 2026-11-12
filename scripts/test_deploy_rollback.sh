#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

FAKE_BIN="$WORK/bin"
STATE_DIR="$WORK/state"
DOCKER_LOG="$WORK/docker.log"
RUNNING_STATE="$WORK/running-image"
mkdir -p "$FAKE_BIN" "$STATE_DIR"

cat >"$FAKE_BIN/docker" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >>"$FAKE_DOCKER_LOG"

case "${1:-}" in
  login)
    cat >/dev/null
    ;;
  run)
    for last in "$@"; do :; done
    printf '%s\n' "$last" >"$FAKE_RUNNING_STATE"
    ;;
  pull|rm|logs|image)
    ;;
  *)
    echo "unexpected docker command: $*" >&2
    exit 1
    ;;
esac
EOF

cat >"$FAKE_BIN/curl" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
if [[ -f "$FAKE_RUNNING_STATE" ]] && grep -q "older" "$FAKE_RUNNING_STATE"; then
  printf '%s\n' '{"status":"ok","version":"0.0.9"}'
  exit 0
fi
if [[ -f "$FAKE_RUNNING_STATE" ]] && grep -q "old" "$FAKE_RUNNING_STATE"; then
  printf '%s\n' '{"status":"ok","version":"0.1.0"}'
  exit 0
fi
exit 22
EOF

chmod +x "$FAKE_BIN/docker" "$FAKE_BIN/curl"

cat >"$STATE_DIR/app.env" <<'EOF'
APP_ENV=test
LOG_LEVEL=INFO
EOF

printf '%s\n' "registry.example/old:1" >"$STATE_DIR/current_image"
printf '%s\n' "0.1.0" >"$STATE_DIR/current_version"
printf '%s\n' "registry.example/older:0" >"$STATE_DIR/previous_image"
printf '%s\n' "0.0.9" >"$STATE_DIR/previous_version"

export PATH="$FAKE_BIN:$PATH"
export STATE_DIR
export FAKE_DOCKER_LOG="$DOCKER_LOG"
export FAKE_RUNNING_STATE="$RUNNING_STATE"
export HEALTH_RETRIES=1
export HEALTH_INTERVAL=0

set +e
"$REPO_ROOT/scripts/deploy.sh" "registry.example/new:2" "0.2.0" >/dev/null 2>&1
status=$?
set -e

if [[ "$status" -ne 1 ]]; then
  echo "expected deploy failure exit 1, got $status" >&2
  exit 1
fi

if ! grep -q "registry.example/old:1" "$STATE_DIR/current_image"; then
  echo "expected current_image to be the rolled-back image" >&2
  exit 1
fi

if ! grep -q "0.1.0" "$STATE_DIR/current_version"; then
  echo "expected current_version to be restored to the previous version" >&2
  exit 1
fi

if ! grep -q "APP_VERSION=0.1.0" "$DOCKER_LOG"; then
  echo "expected the rolled-back container to carry the previous version" >&2
  exit 1
fi

if ! grep -q "registry.example/new:2" "$DOCKER_LOG"; then
  echo "expected the new image to be started" >&2
  exit 1
fi

if ! grep -q "registry.example/old:1" "$DOCKER_LOG"; then
  echo "expected the previous image to be restarted" >&2
  exit 1
fi

printf '%s\n' "registry.example/older:0" >"$STATE_DIR/previous_image"
printf '%s\n' "0.0.9" >"$STATE_DIR/previous_version"
"$REPO_ROOT/scripts/deploy.sh" --rollback "rollback-test" >/dev/null 2>&1

if ! grep -q "registry.example/older:0" "$STATE_DIR/current_image"; then
  echo "expected current_image to be the rollback target" >&2
  exit 1
fi

echo "deploy rollback test passed"
