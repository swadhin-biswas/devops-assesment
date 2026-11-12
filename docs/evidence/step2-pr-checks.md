# Step 2 evidence: PR checks

Workflow: `.github/workflows/pr.yml`, run
[43183003082](https://github.com/swadhin-biswas/devops-assesment/actions/runs/43183003082)
on GitHub-hosted `ubuntu-latest` runners.

## Jobs

```text
config-lint        success
image-scan         success
lint-and-test      success
lint-containers    success
```

The same four jobs run on every pull request and on every push to `main`.
GitHub secret scanning covers the public repository.

## lint-and-test (ruff, pytest, coverage, rollback test)

From the job log:

```text
TOTAL     145      0     20      0   100%
============================== 17 passed in 0.97s ==============================
deploy rollback test passed
```

Ruff runs before pytest, and the job includes
`scripts/test_deploy_rollback.sh`, which proves the deploy script's rollback
path without touching a real instance.

## lint-containers (hadolint + shellcheck)

`hadolint` lints the Dockerfile with `failure-threshold: warning`, and
`ludeeus/action-shellcheck` scans `./scripts` at severity warning. The current
workflow also lints `monitoring/alertmanager/entrypoint.sh`. Both actions
reported success in this job.

## image-scan (Trivy, fails on CRITICAL)

The job builds the image and runs Trivy with `severity: CRITICAL` and
`exit-code: 1`. Log excerpt:

```text
INFO [python-pkg] Detecting vulnerabilities...
│ Target │ Type │ Vulnerabilities │ Secrets │
# action outcome=success
```

No CRITICAL findings, so the gate passed. The gate itself was proven separately
on run 43019232745: scanning `python:3.8-slim` reported 9 CRITICAL findings and
the step exited 1.
