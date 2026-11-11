# Buildkite integration

## The error, and what caused it

The Buildkite checks on this repository come from Buildkite's GitHub integration,
pipeline `swadhin-biswas/devops-assesment`. It imports `.github/workflows/pr.yml`
and reports each job as a Buildkite check.

On the first imported run, `lint-and-test` and `lint-containers` passed. The
`image-scan` job failed with:

```text
buildkite-gha: run-job: step "step-4": composite action step 1: composite action step 4:
checkout adapter: explicit input "repository" value is unsupported
```

The culprit was `aquasecurity/trivy-action`. It is a composite action whose
internal tooling checkout passes an explicit `repository` input, and Buildkite's
checkout adapter only supports the event repository (see the compatibility
table in Buildkite's GitHub Actions migration docs). The `scan/...json` artifact
in the same build is the scan result the importer produced before the checkout
adapter rejected the step.

## The fix

The image scan no longer uses the composite action. It downloads a pinned Trivy
release and runs the CLI:

```yaml
      - name: Install Trivy
        env:
          TRIVY_VERSION: 0.70.0
        run: |
          mkdir -p .ci-bin
          curl -fsSL "https://github.com/aquasecurity/trivy/releases/download/v${TRIVY_VERSION}/trivy_${TRIVY_VERSION}_Linux-64bit.tar.gz" \
            | tar -xz -C .ci-bin trivy
          ./.ci-bin/trivy --version

      - name: Scan image
        run: |
          ./.ci-bin/trivy image --exit-code 1 --severity CRITICAL --ignore-unfixed=false "app:pr-${GITHUB_SHA}"
```

This keeps the same gate (fail on CRITICAL) and works identically in GitHub
Actions and the Buildkite importer.

## Proof

Buildkite run for the fix: pending; this file is updated with the result.

The imported jobs report these statuses on PRs:

| Buildkite check | Result before the fix |
|---|---|
| `PR checks / lint-and-test` | pass |
| `PR checks / lint-containers` | pass |
| `PR checks / image-scan` | fail (the checkout adapter error above) |

After the fix, all three should pass. The Buildkite build links are visible
under the PR checks, for example
`https://buildkite.com/swadhin-biswas/devops-assesment/builds/6`.

## Notes

- GitHub Actions remains the primary pipeline. The Buildkite import is a
  mirror; the native `.buildkite/pipeline.yml` stays as an agent-based
  fallback, with its release step gated behind `BUILDKITE_RELEASE=true`.
- The `BUILDKITE_API_KEY` repository secret is not used by this integration.
  The GitHub app owns the connection. If it is retained for separate API work,
  scope it to the pipeline and rotate it; otherwise remove it.
- At the time of writing, GitHub Actions is not scheduling jobs for this
  repository (queued runs have no jobs even though the self-hosted runner is
  online). The Buildkite checks still run because they are driven by the GitHub
  app, not by GitHub Actions.
