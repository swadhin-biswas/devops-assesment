# Step 1 evidence: application and container

Captured on 2026-11-12 against the current 2.0.0 code. The service ran as a
local process on `127.0.0.1:8091` with `APP_PORT=8091`, `APP_ENV=staging`,
`LOG_LEVEL=DEBUG`, and `APP_VERSION=2.0.0`; the container facts below are from
the same code and the CI image build.

## Endpoints

```text
$ curl -s http://127.0.0.1:8091/
{"message":"Hello from DevOps Task!","status":"running","version":"2.0.0"}

$ curl -s http://127.0.0.1:8091/health
{"status":"ok","version":"2.0.0","environment":"staging"}
```

## Prometheus metrics

```text
$ curl -s http://127.0.0.1:8091/metrics | grep '^# HELP app_\|^# TYPE app_\|^app_requests_total\|^app_request_duration_seconds_bucket'
# HELP app_requests_total Total HTTP requests processed.
# TYPE app_requests_total counter
# HELP app_errors_total Total HTTP responses with a 5xx status.
# TYPE app_errors_total counter
# HELP app_request_duration_seconds HTTP request latency in seconds.
# TYPE app_request_duration_seconds histogram
app_requests_total{method="GET",path="/health",status="200"} 2.0
app_requests_total{method="GET",path="/",status="200"} 1.0
app_request_duration_seconds_bucket{le="0.005",method="GET",path="/health"} 2.0
```

No 5xx responses occurred at capture time, so `app_errors_total` appears only
as HELP/TYPE lines; the counter is exercised by the unit tests and by the
request middleware (`app/main.py`).

## Configuration from environment, JSON logs, graceful shutdown

```text
$ APP_PORT=8091 APP_ENV=staging LOG_LEVEL=DEBUG APP_VERSION=2.0.0 \
  OTEL_EXPORTER_OTLP_ENDPOINT=http://127.0.0.1:4318 ./.venv/bin/python -m app
{"timestamp":"2026-11-12T04:09:28.482Z","level":"INFO","logger":"app","message":"tracing initialized","environment":"staging","version":"2.0.0","event":"tracing"}
{"timestamp":"2026-11-12T04:09:28.492Z","level":"DEBUG","logger":"asyncio","message":"Using selector: EpollSelector","environment":"staging","version":"2.0.0"}
{"timestamp":"2026-11-12T04:09:28.499Z","level":"INFO","logger":"uvicorn.error","message":"Started server process [1270110]","environment":"staging","version":"2.0.0"}
{"timestamp":"2026-11-12T04:09:28.499Z","level":"INFO","logger":"app","message":"application startup","environment":"staging","version":"2.0.0","event":"startup"}
{"timestamp":"2026-11-12T04:09:28.499Z","level":"INFO","logger":"uvicorn.error","message":"Uvicorn running on http://0.0.0.0:8091 (Press CTRL+C to quit)","environment":"staging","version":"2.0.0"}
{"timestamp":"2026-11-12T04:09:28.534Z","level":"INFO","logger":"app","message":"request completed","environment":"staging","version":"2.0.0","event":"request","method":"GET","path":"/health","status_code":200,"duration_ms":0.485}
{"timestamp":"2026-11-12T04:09:28.541Z","level":"INFO","logger":"app","message":"request completed","environment":"staging","version":"2.0.0","event":"request","method":"GET","path":"/","status_code":200,"duration_ms":0.36}
{"timestamp":"2026-11-12T04:09:28.547Z","level":"INFO","logger":"app","message":"request completed","environment":"staging","version":"2.0.0","event":"request","method":"GET","path":"/health","status_code":200,"duration_ms":0.211}
{"timestamp":"2026-11-12T04:09:28.601Z","level":"INFO","logger":"uvicorn.error","message":"Shutting down","environment":"staging","version":"2.0.0"}
{"timestamp":"2026-11-12T04:09:28.701Z","level":"INFO","logger":"app","message":"application shutdown","environment":"staging","version":"2.0.0","event":"shutdown"}
{"timestamp":"2026-11-12T04:09:28.701Z","level":"INFO","logger":"uvicorn.error","message":"Application shutdown complete.","environment":"staging","version":"2.0.0"}
{"timestamp":"2026-11-12T04:09:28.701Z","level":"INFO","logger":"uvicorn.error","message":"Finished server process [1270110]","environment":"staging","version":"2.0.0"}
```

The port (8091), environment (`staging`), log level (`DEBUG`), version
(`2.0.0`), and tracing endpoint all came from environment variables. `SIGTERM`
was sent after the requests; the lifespan shutdown logged `application
shutdown` and the process exited with status 143 (128 + 15), the normal exit
status when a process is terminated by SIGTERM.

## Unit tests and coverage

```text
$ ./.venv/bin/python -m pytest -q --cov=app --cov-report=term-missing
Name    Stmts   Miss Branch BrPart  Cover   Missing
---------------------------------------------------
TOTAL     145      0     20      0   100%

7 files skipped due to complete coverage.
17 passed in 0.60s
```

## Container image

From `Dockerfile`:

- Multi-stage build; both base images are pinned by digest:
  `python:3.12-alpine@sha256:e064671ca452...` in the builder and
  `alpine:3.23@sha256:469c9ea410b9...` for the final stage.
- `USER 10001:10001` (non-root), `STOPSIGNAL SIGTERM`, OCI labels for title,
  description, version, revision, created and license.
- `HEALTHCHECK` calls `/health` with the bundled `python3`, since the shell and
  `apk` are removed from the final image.
- Final image size: 93 MB (93,367,962 bytes, reported by the CI image build in
  the `image-scan` job; the tracing dependencies add to the earlier 84 MB build).

`.dockerignore` keeps `.git`, `.venv`, tests, docs, terraform, k8s, monitoring,
scripts and local env files out of the build context.

## docker-compose app service

From `docker-compose.yml`:

- Publishes `127.0.0.1:8080`.
- Healthcheck: `python3` urllib request to `/health` every 30s, 3s timeout,
  3 retries, 10s start period.
- `restart: unless-stopped`.
- Resource limits 0.50 CPU / 256M memory, reservations 0.10 CPU / 64M.
- `read_only: true` with a 16M tmpfs at `/tmp`, all capabilities dropped,
  `no-new-privileges:true`.
