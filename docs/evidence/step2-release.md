# Release evidence

Release: https://github.com/swadhinbiswas/devops-assesment/actions/runs/43033705446
Image: swadhinbiswas/devops-task:v0.1.6 + 666564b3d6db9a5c56802fbcd08e50941cde9741 (amd64+arm64)
Live: http://18.138.103.103:8080/health returned {"status":"ok","version":"0.1.6","environment":"production"}

## Multi-arch manifest (linux/amd64 + linux/arm64)
Verified with: docker buildx imagetools inspect swadhinbiswas/devops-task:v0.1.6
