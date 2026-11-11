# Observability verification

Stack: prometheus, grafana, loki, alloy, node-exporter, cadvisor (+ app) via `docker compose --profile monitoring up -d`.

## Prometheus targets (all UP)
```
app up
node-exporter up
cadvisor up
```

## Alert rules loaded (4, evaluated every 15s)
```
AppInstanceDown inactive
HighErrorRate inactive
HostDiskUsageHigh inactive
ContainerMemoryNearLimit inactive
```

## Firing proof
Stopped the app container for 3 minutes: ALERTS metric showed AppInstanceDown firing (see docs/images/alert-firing.png). Restarted afterwards.

## Loki log parsing (service=app, limit 1)
```
labels: {'container': 'devops-task-app-1', 'detected_level': 'INFO', 'level': 'INFO', 'path': '/health', 'service': 'app', 'service_name': 'app'}
line: {"timestamp":"2026-11-11T16:27:57.132Z","level":"INFO","logger":"app","message":"request completed","environment":"development","version":"0.1.0","event":"request","method":"GET","path":"/health","sta
```

## Containers dashboard

cAdvisor `0.54.0` with `--docker_only=true` resolves Docker 29 container names on this host. Sample Prometheus results:

```text
devops-task-app-1       38.9 MiB
devops-task-grafana-1   73.7 MiB
devops-task-prometheus-1 100.9 MiB
```

The Containers dashboard shows per-container CPU, memory, and memory/limit for the `devops-task-*` containers. Screenshot: `docs/images/containers-dashboard.png`.
