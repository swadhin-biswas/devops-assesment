# Release evidence

Release: https://github.com/swadhinbiswas/devops-assesment/actions/runs/43033705446
Image: swadhinbiswas/devops-task:v0.1.6 + 666564b3d6db9a5c56802fbcd08e50941cde9741 (amd64+arm64)
Live: http://18.138.103.103:8080/health returned {"status":"ok","version":"0.1.6","environment":"production"}

## Multi-arch manifest (verified from the registry)

`v0.1.8` as served by Docker Hub:

```text
mediaType: application/vnd.oci.image.index.v1+json
platform: linux/amd64 digest: sha256:b13eb8ec9023d... size: 1242 bytes
platform: linux/arm64 digest: sha256:a2b2a988bb50a... size: 1242 bytes
platform: unknown/unknown digest: sha256:f10ed6a944b17... size: 1112 bytes
platform: unknown/unknown digest: sha256:a516a9aad1b11... size: 1112 bytes
```

The two `unknown/unknown` entries are the SBOM and provenance attestations
attached by buildx (`provenance: true`, `sbom: true` in `release.yml`).

## Release run 43041045214 (build-and-deploy, success)

Log excerpts:

```text
Cache restored successfully
"image.name": "swadhinbiswas/devops-task:v0.1.7,swadhinbiswas/devops-task:e61267a83954aa16d735606a1e90a320d13b34ae"
SSM command: 13d3e714-305d-4dc9-a541-093f92f9b565
2026-11-11T14:47:02Z pulling swadhinbiswas/devops-task:v0.1.7
Status: Downloaded newer image for swadhinbiswas/devops-task:v0.1.7
2026-11-11T14:47:14Z healthy: 0.1.7
```

Both tags (semver and full commit SHA) were pushed, the cache was reused, the
deploy ran over SSM, and the smoke test got a healthy response from the
instance after the container swap.
