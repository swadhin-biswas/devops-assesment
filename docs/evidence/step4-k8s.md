# Kubernetes evidence (kind: devops-task)

## Nodes
devops-task-control-plane   Ready   control-plane   17m   v1.37.0

## Workloads
pod/devops-task-84cf4f887-6qs55   1/1   Running   0     6m1s
pod/devops-task-84cf4f887-nwlwc   1/1   Running   0     6m7s
service/devops-task   ClusterIP   10.96.2.13   <none>   80/TCP   16m
ingress.networking.k8s.io/devops-task   nginx   devops-task.local         80    16m
horizontalpodautoscaler.autoscaling/devops-task   Deployment/devops-task   cpu: 3%/70%   2     5     2     16m
devops-task   nginx   devops-task.local         80    16m

## Config and secrets (names only)
devops-task-config   3     16m
devops-task-secret   Opaque   2     16m

## Rollout history
deployment.apps/devops-task 
REVISION  CHANGE-CAUSE
2         kubectl set image deployment/devops-task app=swadhinbiswas/devops-task:v0.1.7 --record=true
3         kubectl set image deployment/devops-task app=swadhinbiswas/devops-task:v0.1.8 --record=true
5         kubectl set image deployment/devops-task app=swadhinbiswas/devops-task:v0.1.8 --record=true
6         kubectl set image deployment/devops-task app=swadhinbiswas/devops-task:v0.1.8 --record=true

swadhinbiswas/devops-task:v0.1.8

## Probes, resources, security (deployment excerpt)
liveness=/health readiness=/health requests={"cpu":"100m","memory":"64Mi"} limits={"cpu":"500m","memory":"256Mi"}
pod.runAsUser=
container.readOnlyRootFilesystem=true runAsUser=10001 allowPrivilegeEscalation=false

## Rolling update demo
In-cluster curl loop against the Service during rollouts:
- v0.1.7 to v0.1.8 update: 335/337 HTTP 200 (2 refused during endpoint churn)
- after adding preStop sleep 15: 900/900 HTTP 200 across a rolling restart
- kubectl rollout undo: restored previous revision, deployment healthy, re-converged with apply -k
