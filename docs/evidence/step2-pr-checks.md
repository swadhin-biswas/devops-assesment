# CI evidence

## PR checks (lint, tests, coverage, hadolint, shellcheck, build, Trivy)

Run 43019232745 (self-hosted runner swadhin-local): lint-and-test, lint-containers, image-scan all SUCCESS.
Trivy gate proven separately: python:3.8-slim -> 9 CRITICAL findings -> exit 1.
