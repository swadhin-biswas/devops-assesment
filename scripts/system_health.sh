#!/usr/bin/env bash
# system_health.sh — production host health probe for the DevOps task.
#
# Collects CPU, memory, per-filesystem disk usage, load average and the top
# memory consumers, appends a timestamped entry to a log file, prints
# [WARNING]/[CRITICAL] messages when thresholds are exceeded, and exits with
# a status monitoring tools can act on.
#
# Exit codes: 0 = healthy, 1 = warning, 2 = critical, 3 = usage error.
set -Eeuo pipefail

readonly VERSION="1.0.0"
readonly SCRIPT_NAME="system_health.sh"
readonly CPU_SAMPLE_SECS=1
readonly TOP_PROCS=5

# Unexpected failures must not look like a threshold warning to monitoring.
# Explicit exits set CLEAN_EXIT so warning (1) and critical (2) keep their meaning.
CLEAN_EXIT=0
# shellcheck disable=SC2154
trap 'rc=$?; if (( CLEAN_EXIT )); then exit "$rc"; fi; printf "%s: [ERROR] unexpected failure at line %s (status %s)\n" "$SCRIPT_NAME" "$LINENO" "$rc" >&2; exit 3' ERR

readonly DEFAULT_DISK_WARN=80
readonly DEFAULT_CPU_WARN=90
readonly DEFAULT_MEM_WARN=85
readonly DEFAULT_DISK_CRIT=95
readonly DEFAULT_CPU_CRIT=98
readonly DEFAULT_MEM_CRIT=95

LOG_FILE="health_log.txt"
MAX_LOG_BYTES="${HEALTH_LOG_MAX_BYTES:-1048576}"
KEEP_ROTATIONS="${HEALTH_LOG_KEEP:-3}"
OUTPUT_JSON=0
DISK_WARN=$DEFAULT_DISK_WARN
CPU_WARN=$DEFAULT_CPU_WARN
MEM_WARN=$DEFAULT_MEM_WARN
LOAD_WARN=""
DISK_CRIT=$DEFAULT_DISK_CRIT
CPU_CRIT=$DEFAULT_CPU_CRIT
MEM_CRIT=$DEFAULT_MEM_CRIT
LOAD_CRIT=""
WEBHOOK_URL="${HEALTH_WEBHOOK_URL:-}"
WEBHOOK_TIMEOUT="${HEALTH_WEBHOOK_TIMEOUT:-5}"
WEBHOOK_REPEAT="${HEALTH_WEBHOOK_REPEAT:-3600}"

usage() {
  printf '%s %s\n\n' "$SCRIPT_NAME" "$VERSION"
  cat <<'EOF'
system_health.sh — production host health probe.

Collects CPU, memory, disk usage for all real mounted filesystems (pseudo
filesystems excluded), load average and the top 5 processes by memory,
appends a timestamped entry to a log file, and exits with a status
monitoring tools can act on.

Usage:
  system_health.sh [--json] [--log-file PATH]
                   [--disk PCT] [--cpu PCT] [--mem PCT] [--load N]
                   [--disk-critical PCT] [--cpu-critical PCT]
                   [--mem-critical PCT] [--load-critical N]
                   [--help]

Options:
  --json               emit the log entry and stdout output as one JSON line
  --log-file PATH      file to append entries to (default: ./health_log.txt)
  --disk PCT           disk warning threshold in percent      (default 80)
  --cpu PCT            CPU warning threshold in percent       (default 90)
  --mem PCT            memory warning threshold in percent    (default 85)
  --load N             1-min load average warning threshold   (default: core count)
  --disk-critical PCT  disk critical threshold                (default 95)
  --cpu-critical PCT   CPU critical threshold                 (default 98)
  --mem-critical PCT   memory critical threshold              (default 95)
  --load-critical N    load critical threshold                (default: 2x cores)
  -h, --help           show this help

Exit codes:
  0  healthy  — no threshold exceeded
  1  warning  — a metric is at or above its warning threshold
  2  critical — a metric is at or above its critical threshold
  3  usage error — unknown flag or non-numeric threshold value

[WARNING] and [CRITICAL] lines go to stderr; the entry goes to stdout.
The log receives the entry and, in text mode, the warning lines too.

Log rotation: when the log file reaches HEALTH_LOG_MAX_BYTES (default
1048576) it is shifted to .1/.2/.3 and a fresh file starts; HEALTH_LOG_KEEP
(default 3) rotated files are kept.

Systemd units live in scripts/systemd/. Cron alternative (5 minutes):
  */5 * * * * /usr/local/bin/system_health.sh --json --log-file /var/log/system_health.log >/dev/null

Environment:
  HEALTH_WEBHOOK_URL      Slack or Discord webhook URL. When set, warning and
                          critical results are POSTed to it. Discord is
                          detected from the URL and gets a content payload;
                          everything else gets a Slack text payload.
  HEALTH_WEBHOOK_TIMEOUT  webhook request timeout in seconds (default 5)
  HEALTH_WEBHOOK_REPEAT   suppress repeat posts for the same status (default 3600)
  HEALTH_WEBHOOK_STATE_FILE  cooldown state file (default: <log-file>.webhook)
EOF
}

usage_error() {
  printf '%s: %s\n\n' "$SCRIPT_NAME" "$1" >&2
  usage >&2
  CLEAN_EXIT=1
  exit 3
}

is_number() {
  [[ $1 =~ ^[0-9]+([.][0-9]+)?$ ]]
}

require_number() {
  local flag=$1 value=$2
  if ! is_number "$value"; then
    usage_error "$flag requires a numeric argument (got: '${value:-}')"
  fi
}

# float_ge A B — exit 0 when A >= B (both decimal numbers).
float_ge() {
  awk -v a="$1" -v b="$2" 'BEGIN { exit !(a >= b) }'
}

validate_thresholds() {
  if float_ge "$DISK_WARN" "$DISK_CRIT"; then
    usage_error "--disk ($DISK_WARN) must be below --disk-critical ($DISK_CRIT)"
  fi
  if float_ge "$CPU_WARN" "$CPU_CRIT"; then
    usage_error "--cpu ($CPU_WARN) must be below --cpu-critical ($CPU_CRIT)"
  fi
  if float_ge "$MEM_WARN" "$MEM_CRIT"; then
    usage_error "--mem ($MEM_WARN) must be below --mem-critical ($MEM_CRIT)"
  fi
  if float_ge "$LOAD_WARN" "$LOAD_CRIT"; then
    usage_error "--load ($LOAD_WARN) must be below --load-critical ($LOAD_CRIT)"
  fi
}

json_escape() {
  local s=$1
  s=${s//\\/\\\\}
  s=${s//\"/\\\"}
  s=${s//$'\n'/\\n}
  s=${s//$'\r'/\\r}
  s=${s//$'\t'/\\t}
  printf '%s' "$s"
}

parse_args() {
  while (($#)); do
    case $1 in
      --json) OUTPUT_JSON=1 ;;
      --log-file)
        [[ ${2:-} && $2 != --* ]] || usage_error "--log-file requires a path argument"
        LOG_FILE=$2
        shift
        ;;
      --disk) require_number "$1" "${2:-}"; DISK_WARN=$2; shift ;;
      --cpu) require_number "$1" "${2:-}"; CPU_WARN=$2; shift ;;
      --mem) require_number "$1" "${2:-}"; MEM_WARN=$2; shift ;;
      --load) require_number "$1" "${2:-}"; LOAD_WARN=$2; shift ;;
      --disk-critical) require_number "$1" "${2:-}"; DISK_CRIT=$2; shift ;;
      --cpu-critical) require_number "$1" "${2:-}"; CPU_CRIT=$2; shift ;;
      --mem-critical) require_number "$1" "${2:-}"; MEM_CRIT=$2; shift ;;
      --load-critical) require_number "$1" "${2:-}"; LOAD_CRIT=$2; shift ;;
      -h | --help)
        usage
        exit 0
        ;;
      *) usage_error "unknown flag: $1" ;;
    esac
    shift
  done
}

read_cpu_line() {
  # Prints "<label> <total> <idle+iowait>" for the aggregate cpu line.
  awk '/^cpu /{t = 0; for (i = 2; i <= 8; i++) t += $i; print $1, t, $5 + $6}' /proc/stat
}

collect_metrics() {
  local _ label_total_before label_idle_before label_total_after label_idle_after
  read -r _ label_total_before label_idle_before _ < <(read_cpu_line)
  sleep "$CPU_SAMPLE_SECS"
  read -r _ label_total_after label_idle_after _ < <(read_cpu_line)

  local d_total=$(( label_total_after - label_total_before ))
  local d_idle=$(( label_idle_after - label_idle_before ))
  (( d_total > 0 )) || d_total=1
  CPU_PCT=$(awk -v busy=$(( d_total - d_idle )) -v total="$d_total" 'BEGIN { printf "%.1f", 100 * busy / total }')

  MEM_PCT=$(awk '/^MemTotal:/{t = $2} /^MemAvailable:/{a = $2} END { printf "%.1f", 100 * (t - a) / t }' /proc/meminfo)

  read -r LOAD1 _ _ _ < /proc/loadavg
  CORES=$(nproc)
  [[ -n $LOAD_WARN ]] || LOAD_WARN=$CORES
  [[ -n $LOAD_CRIT ]] || LOAD_CRIT=$(awk -v c="$CORES" 'BEGIN { print 2 * c }')

  mounts=()
  disk_pcts=()
  local mnt pct
  local -a df_cmd=(df -P -x tmpfs -x devtmpfs -x squashfs -x efivarfs -x ramfs -x iso9660)
  if command -v timeout >/dev/null 2>&1; then
    df_cmd=(timeout 5 "${df_cmd[@]}")
  fi
  while read -r mnt pct; do
    mounts+=("$mnt")
    disk_pcts+=("$pct")
  done < <("${df_cmd[@]}" |
    awk 'NR > 1 && $6 !~ /^\/(proc|sys|dev|run)/ { printf "%s %s\n", $6, $5 + 0 }')
  if ((${#mounts[@]} == 0)); then
    printf '[ERROR] df returned no mounted filesystems\n' >&2
    exit 3
  fi

  top_pids=()
  top_names=()
  top_pmems=()
  TOP_TEXT=""
  local pid name pmem
  while read -r pmem pid name; do
    top_pids+=("$pid")
    top_names+=("$name")
    top_pmems+=("$pmem")
    TOP_TEXT+="${name}(${pid}):${pmem}% "
  done < <(ps -eo pmem,pid,comm --no-headers --sort=-pmem | head -n "$TOP_PROCS")
  if ((${#top_pids[@]} == 0)); then
    printf '[ERROR] ps returned no processes\n' >&2
    exit 3
  fi

  TIMESTAMP=$(date -u +%Y-%m-%dT%H:%M:%SZ)
}

evaluate_thresholds() {
  warnings=()
  criticals=()
  local i
  for i in "${!mounts[@]}"; do
    if float_ge "${disk_pcts[$i]}" "$DISK_CRIT"; then
      criticals+=("disk(${mounts[$i]}) ${disk_pcts[$i]}% >= ${DISK_CRIT}%")
    elif float_ge "${disk_pcts[$i]}" "$DISK_WARN"; then
      warnings+=("disk(${mounts[$i]}) ${disk_pcts[$i]}% >= ${DISK_WARN}%")
    fi
  done

  if float_ge "$CPU_PCT" "$CPU_CRIT"; then
    criticals+=("cpu ${CPU_PCT}% >= ${CPU_CRIT}%")
  elif float_ge "$CPU_PCT" "$CPU_WARN"; then
    warnings+=("cpu ${CPU_PCT}% >= ${CPU_WARN}%")
  fi

  if float_ge "$MEM_PCT" "$MEM_CRIT"; then
    criticals+=("mem ${MEM_PCT}% >= ${MEM_CRIT}%")
  elif float_ge "$MEM_PCT" "$MEM_WARN"; then
    warnings+=("mem ${MEM_PCT}% >= ${MEM_WARN}%")
  fi

  if float_ge "$LOAD1" "$LOAD_CRIT"; then
    criticals+=("load ${LOAD1} >= ${LOAD_CRIT}")
  elif float_ge "$LOAD1" "$LOAD_WARN"; then
    warnings+=("load ${LOAD1} >= ${LOAD_WARN}")
  fi

  STATUS="healthy"
  EXIT_CODE=0
  if ((${#criticals[@]})); then
    STATUS="critical"
    EXIT_CODE=2
  elif ((${#warnings[@]})); then
    STATUS="warning"
    EXIT_CODE=1
  fi
}

build_text_entry() {
  local i
  TEXT_ENTRY="[$TIMESTAMP] $STATUS cpu=${CPU_PCT}% mem=${MEM_PCT}% load=${LOAD1} cores=${CORES} disks="
  if ((${#mounts[@]})); then
    for i in "${!mounts[@]}"; do
      TEXT_ENTRY+="${mounts[$i]}=${disk_pcts[$i]}% "
    done
  else
    TEXT_ENTRY+="none "
  fi
  if ((${#top_pids[@]})); then
    TEXT_ENTRY+="top_mem=${TOP_TEXT% }"
  else
    TEXT_ENTRY+="top_mem=none"
  fi
}

build_json_entry() {
  local i first
  JSON_ENTRY="{\"timestamp\":\"$(json_escape "$TIMESTAMP")\",\"status\":\"$STATUS\",\"cpu_percent\":$CPU_PCT,\"mem_percent\":$MEM_PCT,\"load1\":$LOAD1,\"cores\":$CORES,\"disks\":["
  first=1
  for i in "${!mounts[@]}"; do
    (( first )) || JSON_ENTRY+=","
    JSON_ENTRY+="{\"mount\":\"$(json_escape "${mounts[$i]}")\",\"percent\":${disk_pcts[$i]}}"
    first=0
  done
  JSON_ENTRY+="],\"top_processes\":["
  first=1
  for i in "${!top_pids[@]}"; do
    (( first )) || JSON_ENTRY+=","
    JSON_ENTRY+="{\"pid\":${top_pids[$i]},\"name\":\"$(json_escape "${top_names[$i]}")\",\"percent_memory\":${top_pmems[$i]}}"
    first=0
  done
  JSON_ENTRY+="],\"warnings\":["
  first=1
  for i in "${warnings[@]}"; do
    (( first )) || JSON_ENTRY+=","
    JSON_ENTRY+="\"$(json_escape "$i")\""
    first=0
  done
  JSON_ENTRY+="],\"criticals\":["
  first=1
  for i in "${criticals[@]}"; do
    (( first )) || JSON_ENTRY+=","
    JSON_ENTRY+="\"$(json_escape "$i")\""
    first=0
  done
  JSON_ENTRY+="]}"
}

rotate_log() {
  local size
  size=$(stat -c %s "$LOG_FILE" 2>/dev/null || printf '0')
  if (( size < MAX_LOG_BYTES )); then
    return 0
  fi
  local i
  for (( i = KEEP_ROTATIONS - 1; i >= 1; i-- )); do
    if [[ -f $LOG_FILE.$i ]]; then
      mv -f "$LOG_FILE.$i" "$LOG_FILE.$(( i + 1 ))"
    fi
  done
  mv -f "$LOG_FILE" "$LOG_FILE.1"
  : >"$LOG_FILE"
}

append_log() {
  if (( OUTPUT_JSON )); then
    printf '%s\n' "$JSON_ENTRY" >>"$LOG_FILE"
  else
    {
      printf '%s\n' "$TEXT_ENTRY"
      local i
      for i in "${warnings[@]}"; do
        printf '[%s] [WARNING] %s\n' "$TIMESTAMP" "$i"
      done
      for i in "${criticals[@]}"; do
        printf '[%s] [CRITICAL] %s\n' "$TIMESTAMP" "$i"
      done
    } >>"$LOG_FILE"
  fi
}

print_output() {
  local i
  if (( OUTPUT_JSON )); then
    printf '%s\n' "$JSON_ENTRY"
  else
    printf '%s\n' "$TEXT_ENTRY"
  fi
  for i in "${warnings[@]}"; do
    printf '[WARNING] %s\n' "$i" >&2
  done
  for i in "${criticals[@]}"; do
    printf '[CRITICAL] %s\n' "$i" >&2
  done
}

send_webhook() {
  [[ -n $WEBHOOK_URL ]] || return 0
  if (( EXIT_CODE == 0 )); then
    # Clear the cooldown state on recovery so the next incident pages again.
    rm -f "${HEALTH_WEBHOOK_STATE_FILE:-${LOG_FILE}.webhook}" 2>/dev/null || true
    return 0
  fi
  if ! command -v curl >/dev/null 2>&1; then
    printf '[WARNING] curl not found; webhook not sent\n' >&2
    return 0
  fi

  local state_file="${HEALTH_WEBHOOK_STATE_FILE:-${LOG_FILE}.webhook}"
  local now last_status="" last_epoch=0
  now=$(date +%s)
  if [[ -f $state_file ]]; then
    read -r last_status last_epoch < "$state_file" || true
  fi
  [[ $last_epoch =~ ^[0-9]+$ ]] || last_epoch=0
  [[ $WEBHOOK_REPEAT =~ ^[0-9]+$ ]] || WEBHOOK_REPEAT=3600
  if [[ "$STATUS" == "$last_status" ]] && (( now - last_epoch < WEBHOOK_REPEAT )); then
    printf '[INFO] webhook suppressed (same status within %ss)\n' "$WEBHOOK_REPEAT" >&2
    return 0
  fi

  local host
  host=${HOSTNAME:-$(hostname 2>/dev/null || printf 'unknown')}
  local message="[${STATUS^^}] $host at $TIMESTAMP"
  local i
  for i in "${warnings[@]}"; do
    message+="; warning: $i"
  done
  for i in "${criticals[@]}"; do
    message+="; critical: $i"
  done

  local payload
  case ${WEBHOOK_URL,,} in
    *discord*) payload="{\"content\":\"$(json_escape "$message")\"}" ;;
    *) payload="{\"text\":\"$(json_escape "$message")\"}" ;;
  esac

  if curl -fsS --max-time "$WEBHOOK_TIMEOUT" \
    -H 'Content-Type: application/json' -d "$payload" "$WEBHOOK_URL" >/dev/null; then
    printf '%s %s\n' "$STATUS" "$now" > "$state_file" 2>/dev/null || true
    printf '[INFO] webhook delivered (%s)\n' "$STATUS" >&2
  else
    printf '[WARNING] webhook delivery failed\n' >&2
  fi
  return 0
}

main() {
  parse_args "$@"

  # Serialize writers so two timers cannot rotate the same log at once.
  if command -v flock >/dev/null 2>&1; then
    exec 9>"${LOG_FILE}.lock"
    flock -n 9 || {
      printf '[WARNING] another system_health.sh is running\n' >&2
      CLEAN_EXIT=1
      exit 1
    }
  fi

  collect_metrics
  validate_thresholds
  evaluate_thresholds
  build_text_entry
  build_json_entry
  rotate_log
  append_log
  print_output
  send_webhook
  # shellcheck disable=SC2034
  CLEAN_EXIT=1
  exit "$EXIT_CODE"
}

main "$@"
