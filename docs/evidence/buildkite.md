# Buildkite integration

## The error you saw

```text
buildkite-gha: run-job: step "step-4": composite action step 1: composite action step 4:
checkout adapter: explicit input "repository" value is unsupported
```

This comes from Buildkite's GitHub Actions importer (`github-actions-buildkite-plugin`),
not from this repository's checks. The importer runs GitHub Actions workflows as
Buildkite jobs; its checkout adapter supports only the event repository and rejects an
explicit `actions/checkout` `repository:` input. The `scan/...json` artifact in the same
build shows the failing step was an imported scan workflow, not `.buildkite/pipeline.yml`.

Two valid fixes:

1. If the imported workflow is yours, remove `repository:` from its `actions/checkout`
   step. The importers cannot check out alternate repositories.
2. If the workflow is not yours (as with a generated scan step), stop importing it and
   run the native pipeline in `.buildkite/pipeline.yml`.

This repo takes the second path.

## Native Buildkite pipeline

`.buildkite/pipeline.yml` runs the same checks as GitHub Actions without the importer:

```yaml
steps:
  - label: ":python: Checks"
    command: "./scripts/ci-check.sh"
    timeout_in_minutes: 20
    artifact_paths:
      - "coverage.xml"
    agents:
      queue: "default"
```

The release step exists but is opt-in with `BUILDKITE_RELEASE=true`; GitHub Actions is
the primary pipeline and the only release owner.

## One-time setup

`scripts/buildkite-setup.sh` creates or updates the pipeline from the native YAML,
sets the GitHub repository variables, and triggers one build:

```bash
BUILDKITE_API_KEY=... BUILDKITE_ORG=<org> ./scripts/buildkite-setup.sh
```

If the token can list organizations, `BUILDKITE_ORG` can be omitted. The script prints
the created build as JSON, including its `web_url` and `state`.

The same operation runs in CI from `.github/workflows/buildkite-setup.yml`
(`workflow_dispatch`) using the `BUILDKITE_API_KEY` repository secret.

`.github/workflows/buildkite.yml` mirrors every PR and `main` push into Buildkite. It
skips gracefully until `BUILDKITE_ORG` and `BUILDKITE_PIPELINE` are set.

## Required configuration

| Type | Name | Purpose |
|---|---|---|
| Secret | `BUILDKITE_API_KEY` | Create/update the pipeline and trigger builds |
| Variable | `BUILDKITE_ORG` | Buildkite organization slug |
| Variable | `BUILDKITE_PIPELINE` | Buildkite pipeline slug (`devops-task`) |

A pipeline-scoped token with `write_builds` is enough for the mirror; add
`write_pipelines` only for the one-time bootstrap. The broad organization token used
for this setup works, but it is more access than the steady state needs.

## Environment note

At the time of writing, GitHub Actions is not scheduling jobs for this repository:
queued runs have zero jobs despite the self-hosted runner being online and listening.
That is an account-level billing or scheduling condition, independent of these
workflows. The Buildkite setup can be run locally with the API token, or through
`.github/workflows/buildkite-setup.yml` once GitHub schedules jobs again.
