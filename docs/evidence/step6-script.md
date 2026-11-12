# Step 6 evidence: system_health.sh

Script: `scripts/system_health.sh` (bash, no dependencies beyond coreutils/awk/ps).
Scheduling units: `scripts/systemd/system-health.service` + `system-health.timer`.
All commands below were run on the development host (Arch, bash 5.3, 20 cores).
The script reports every real mounted filesystem and excludes pseudo
filesystems (tmpfs, devtmpfs, proc/sys/dev/run, squashfs, efivarfs); that host
had no separate EFI mount, so none appears in the sample.

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
| Critical | `./scripts/system_health.sh --mem 0.5 --mem-critical 1` | `2` |
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
  newlines, not spaces. Both deltas came back empty, so every run reported
  `cpu=100.0%` (critical). Replaced with `read` (IFS splitting); the healthy
  reading above (11.7%) is from the fixed version. The bug was found because
  a "100% CPU" report contradicted a load average of 0.8 on 20 cores.

## On the deploy target

The script was also run on the EC2 instance that serves the application, over
SSM, using the committed file straight from `main`:

```text
$ curl -fsSL https://raw.githubusercontent.com/swadhin-biswas/devops-assesment/main/scripts/system_health.sh -o /tmp/system_health.sh
$ /tmp/system_health.sh --json --log-file /tmp/health_log.txt; echo "exit=$?"
--- healthy run ---
{"timestamp":"2026-11-12T10:32:33Z","status":"healthy","cpu_percent":15.4,"mem_percent":47.4,"load1":0.00,"cores":2,"disks":[{"mount":"/","percent":15},{"mount":"/boot","percent":14},{"mount":"/boot/efi","percent":6},{"mount":"/var/lib/docker/rootfs/overlayfs/9ed88b26774a67499073d8a7b2d7665fc329dc3dea5b7836f85b808cf95589f0","percent":15}],"top_processes":[{"pid":1844,"name":"dockerd","percent_memory":9.5},{"pid":4364,"name":"python3","percent_memory":6.1},{"pid":1620,"name":"containerd","percent_memory":4.1},{"pid":5683,"name":"ssm-document-wo","percent_memory":3.0},{"pid":1076,"name":"ssm-agent-worke","percent_memory":3.0}],"warnings":[],"criticals":[]}
exit=0
--- warning run (--disk 1) ---
[2026-11-12T10:32:34Z] warning cpu=12.4% mem=48.0% load=0.00 cores=2 disks=/=15% /boot=14% /boot/efi=6% /var/lib/docker/rootfs/overlayfs/9ed88b26774a67499073d8a7b2d7665fc329dc3dea5b7836f85b808cf95589f0=15% top_mem=dockerd(1844):9.5% python3(4364):6.1% containerd(1620):4.1% ssm-document-wo(5683):3.0% ssm-agent-worke(1076):3.0%
exit=1
--- log rotation ---
-rw-r--r-- 1 root root 1302 Nov 12 10:32 /tmp/health_log.txt
-rw-r--r-- 1 root root    0 Nov 12 10:32 /tmp/health_log.txt.lock
6 /tmp/health_log.txt
```

The warnings went to stderr, as the script documents:

```text
[WARNING] disk(/) 15% >= 1%
[WARNING] disk(/boot) 14% >= 1%
[WARNING] disk(/boot/efi) 6% >= 1%
[WARNING] disk(/var/lib/docker/rootfs/overlayfs/9ed88b26774a67499073d8a7b2d7665fc329dc3dea5b7836f85b808cf95589f0) 15% >= 1%
```

Two runs appended two entries to the log file and the lock file beside it
stayed empty, which is what the script is supposed to do when two writers
overlap.
