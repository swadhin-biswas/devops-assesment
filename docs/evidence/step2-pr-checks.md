# Step 2 evidence: PR checks

Workflow: `.github/workflows/pr.yml`, run
[43082043497](https://github.com/swadhinbiswas/devops-assesment/actions/runs/43082043497)
on the self-hosted runner (`swadhin-local`).

## Jobs

```text
image-scan        success
lint-and-test     success
lint-containers   success
```

GitGuardian secret scanning also reported pass on the same PR.

## lint-and-test (ruff, pytest, coverage, rollback test)

From the job log:

```text
TOTAL               145      7     22      4    93%
============================== 12 passed in 0.99s ==============================
deploy rollback test passed
```

Ruff runs before pytest, and the job includes
`scripts/test_deploy_rollback.sh`, which proves the deploy script's rollback
path without touching a real instance.

## lint-containers (hadolint + shellcheck)

`hadolint` lints the Dockerfile with `failure-threshold: warning`, and
`ludeeus/action-shellcheck` scans `./scripts` at severity warning. Both actions
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
