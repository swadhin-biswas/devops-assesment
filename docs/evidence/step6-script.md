# Step 6 evidence — system_health.sh

Script: `scripts/system_health.sh` (bash, no dependencies beyond coreutils/awk/ps).
Scheduling units: `scripts/systemd/system-health.service` + `system-health.timer`.
All commands below were run on the development host (Arch, bash 5.3, 20 cores).

## Shellcheck clean (no warnings)

```text
$ shellcheck -x scripts/system_health.sh
$ echo $?
0
```

The same check runs in CI via `ludeeus/action-shellcheck` (pinned to SHA).

## Exit codes

| Run | Command | Exit |
|---|---|---|
| Healthy | `./scripts/system_health.sh --log-file /tmp/health.log` | `0` |
| Warning | `./scripts/system_health.sh --disk 1` | `1` |
| Critical | `./scripts/system_health.sh --mem-critical 1` | `2` |
| Usage error | `./scripts/system_health.sh --bogus` | `3` |
| Help | `./scripts/system_health.sh --help` | `0` |

## Sample healthy entry (text mode, appended to log)

```text
[2026-11-11T17:25:15Z] healthy cpu=12.3% mem=44.4% load=1.26 cores=20 disks=/=20% /home=20% /var/log=20% /.snapshots=20% /var/cache/pacman/pkg=20% /boot=12% top_mem=qs(4244):3.7% chromium(370061):2.3% Telegram(590167):2.0% chromium(7992):1.9% zed-editor(22696):1.8%
```

## Sample JSON entry (--json, one JSONL line, validated with python json.load)

```json
{"timestamp":"2026-11-11T17:25:16Z","status":"healthy","cpu_percent":11.7,"mem_percent":44.5,"load1":0.8,"cores":20,"disks":[{"mount":"/","percent":20},{"mount":"/home","percent":20},{"mount":"/var/log","percent":20},{"mount":"/.snapshots","percent":20},{"mount":"/var/cache/pacman/pkg","percent":20},{"mount":"/boot","percent":12}],"top_processes":[{"pid":4244,"name":"qs","percent_memory":3.7},{"pid":370061,"name":"chromium","percent_memory":2.3},{"pid":590167,"name":"Telegram","percent_memory":2.0},{"pid":7992,"name":"chromium","percent_memory":1.9},{"pid":22696,"name":"zed-editor","percent_memory":1.8}],"warnings":[],"criticals":[]}
```

CPU% is measured from a `/proc/stat` delta over a 1-second window; the
delta math was cross-checked by hand (2005 jiffies over 2 s on 20 cores at
100 Hz = exactly the counter increment).

## Threshold messages (stderr)

```text
$ ./scripts/system_health.sh --disk 1 --log-file /tmp/w.log
[2026-11-11T17:25:17Z] warning cpu=10.0% ... (stdout)
$ # stderr:
[WARNING] disk(/) 20% >= 1%
[WARNING] disk(/home) 20% >= 1%
```

## Log rotation proof

Six runs with `HEALTH_LOG_MAX_BYTES=250 HEALTH_LOG_KEEP=2` (each JSON line is
642 bytes, so every run overflows the limit):

```text
$ ls -la /tmp/health/rot*
rot.txt     642 bytes  (current, 1 line)
rot.txt.1   642 bytes  (1 line)
rot.txt.2   642 bytes  (1 line)
# rot.txt.3 does not exist — oldest is deleted on shift (KEEP=2)
```

## Scheduling

`scripts/systemd/system-health.timer` fires `system-health.service` every 5
minutes (`OnBootSec=2min`, `OnUnitActiveSec=5min`). Install:

```bash
sudo cp scripts/system_health.sh /usr/local/bin/
sudo cp scripts/systemd/system-health.{service,timer} /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable --now system-health.timer
systemctl list-timers system-health.timer
```

Cron alternative is documented in `--help`.

## Bugs caught during development

- Initial CPU logic used `mapfile` to parse `/proc/stat`, which splits on
  newlines, not spaces — both deltas were empty and every run reported
  `cpu=100.0%` (critical). Replaced with `read` (IFS splitting); the healthy
  reading above (11.7%) is from the fixed version. The bug was found because
  a "100% CPU" report contradicted a load average of 0.8 on 20 cores.
