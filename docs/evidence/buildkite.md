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

Buildkite build [7](https://buildkite.com/swadhin-biswas/devops-assesment/builds/7)
after the fix:

| Buildkite check | Before the fix | After the fix |
|---|---|---|
| `PR checks / lint-and-test` | pass | pass |
| `PR checks / lint-containers` | pass | pass |
| `PR checks / image-scan` | fail (the checkout adapter error above) | pass |

The image scan installs Trivy `0.70.0` and still fails the build on any
CRITICAL finding. The final documentation commit (build 8) also passed all
three checks. GitHub Actions subsequently recovered once the workflows used
the runner's exact `Linux/X64` labels.

## Notes

- GitHub Actions remains the primary pipeline. The Buildkite import is a
  mirror; the native `.buildkite/pipeline.yml` stays as an agent-based
  fallback, with its release step gated behind `BUILDKITE_RELEASE=true`.
- The `BUILDKITE_API_KEY` repository secret was used once to set the pipeline
  provider settings. It is not needed at runtime; remove it, or rotate and
  scope it to pipeline administration if you keep it.
- The GitHub Actions queue was caused by case-sensitive self-hosted label
  matching (`linux/x64` requested, `Linux/X64` reported). Workflows now use the
  exact labels and run normally. Old queued run records could not be canceled
  or deleted through the API; they are historical and do not block new runs.

## Provider settings (applied)

The Buildkite pipeline is in GitHub Actions mode with:

```text
github_actions_mode: true
build_branches: false
build_pull_requests: true
build_tags: false
```

The GitHub Actions pipeline trigger still matches `pr.yml` on main pushes, but that
workflow only runs checks. The release workflow is triggered by `workflow_run` of
`PR checks`; Buildkite pipeline triggers explicitly do not support `workflow_run`,
so the release cannot be imported and the GitHub OIDC failure cannot recur. The
earlier `Release / build-and-deploy` failure on `986cbad` came from the former
push-triggered release workflow.

The canonical settings were applied with `PATCH /v2/organizations/swadhin-biswas/pipelines/devops-assesment`
using `provider_settings`; a partial payload without `github_actions_mode` nulled the
provider object, so the final update sends the full supported set and the result was
verified by a follow-up GET.
