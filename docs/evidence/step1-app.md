# Step 1 evidence: application and container

The service was running in Docker on `127.0.0.1:8080` while these outputs were
captured; the JSON log and shutdown run used a local process on port 8090 with
`APP_ENV=staging` and `LOG_LEVEL=DEBUG` to show the configuration is read from
the environment.

## Endpoints

```text
$ curl -s http://127.0.0.1:8080/
{"message":"Hello from DevOps Task!","status":"running","version":"0.1.0"}

$ curl -s http://127.0.0.1:8080/health
{"status":"ok","version":"0.1.0","environment":"development"}
```

## Prometheus metrics

```text
$ curl -s http://127.0.0.1:8080/metrics | grep '^# HELP app_\|^# TYPE app_'
# HELP app_requests_total Total HTTP requests processed.
# TYPE app_requests_total counter
# HELP app_errors_total Total HTTP responses with a 5xx status.
# TYPE app_errors_total counter
# HELP app_request_duration_seconds HTTP request latency in seconds.
# TYPE app_request_duration_seconds histogram

app_requests_total{method="GET",path="/health",status="200"} 222.0
app_requests_total{method="GET",path="/",status="200"} 1.0
app_request_duration_seconds_count{method="GET",path="/health"} 224.0
app_request_duration_seconds_count{method="GET",path="/"} 1.0
```

No 5xx responses had occurred at capture time, so `app_errors_total` appears
only as HELP/TYPE lines; the counter is exercised by the unit tests and by the
request middleware (`app/main.py`).

## Configuration from environment, JSON logs, graceful shutdown

```text
$ APP_PORT=8090 APP_ENV=staging LOG_LEVEL=DEBUG ./.venv/bin/python -m app
{"timestamp":"2026-11-11T18:15:40.812Z","level":"DEBUG","logger":"asyncio","message":"Using selector: EpollSelector","environment":"staging","version":"0.1.0"}
{"timestamp":"2026-11-11T18:15:40.826Z","level":"INFO","logger":"app","message":"application startup","environment":"staging","version":"0.1.0","event":"startup"}
{"timestamp":"2026-11-11T18:15:40.826Z","level":"INFO","logger":"uvicorn.error","message":"Uvicorn running on http://0.0.0.0:8090 (Press CTRL+C to quit)","environment":"staging","version":"0.1.0"}
{"timestamp":"2026-11-11T18:15:44.674Z","level":"INFO","logger":"app","message":"request completed","environment":"staging","version":"0.1.0","event":"request","method":"GET","path":"/","status_code":200,"duration_ms":0.732}
{"timestamp":"2026-11-11T18:15:44.681Z","level":"INFO","logger":"app","message":"request completed","environment":"staging","version":"0.1.0","event":"request","method":"GET","path":"/health","status_code":200,"duration_ms":0.396}
{"timestamp":"2026-11-11T18:15:44.735Z","level":"INFO","logger":"uvicorn.error","message":"Shutting down","environment":"staging","version":"0.1.0"}
{"timestamp":"2026-11-11T18:15:44.836Z","level":"INFO","logger":"app","message":"application shutdown","environment":"staging","version":"0.1.0","event":"shutdown"}
{"timestamp":"2026-11-11T18:15:44.836Z","level":"INFO","logger":"uvicorn.error","message":"Application shutdown complete.","environment":"staging","version":"0.1.0"}
```

The port (8090), environment (`staging`) and log level (`DEBUG`) all came from
environment variables. `SIGTERM` was sent to the process after the two
requests; the lifespan shutdown logged `application shutdown` and the process
exited with status 143 (128 + 15), the normal exit status when a process is
terminated by SIGTERM.

## Unit tests and coverage

```text
$ ./.venv/bin/python -m pytest -q --cov=app --cov-report=term
app/config.py        27      1      4      1    94%   33
app/logging.py       33      1      8      1    95%   38
app/main.py          53      3      4      0    95%   22-24
-------------------------------------------------------------
TOTAL               124      6     18      3    94%

10 passed in 0.45s
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
- Final image size: 84 MB (`docker images`, measured after the local build; CI
  builds the same Dockerfile in the `image-scan` job).

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
