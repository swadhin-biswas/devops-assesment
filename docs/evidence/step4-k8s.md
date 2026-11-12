# Kubernetes evidence (kind: devops-task)

> The zero-downtime and rollback runs below were captured against the
> current release, `v2.1.2`, using the `v2.1.1` and `v2.1.2` images. The
> earlier v0.1.x runs are kept in the history of this file.

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

## Zero-downtime rolling update

The loop runs inside the cluster against the Service DNS, so kube-proxy does
the routing and no single pod sits in the path. An earlier attempt used
`kubectl port-forward`, which dies with the pod it is attached to and reports
false downtime, so the measurement has to happen inside the cluster.

```bash
kubectl run zd --restart=Never --image=curlimages/curl:8.11.1 --command -- sh -c '
i=0; ok=0; fail=0
while [ $i -lt 900 ]; do
  code=$(curl -s -o /dev/null -w "%{http_code}" --max-time 5 http://devops-task.default.svc.cluster.local/health || echo 000)
  if [ "$code" = 200 ]; then ok=$((ok+1)); else fail=$((fail+1)); echo "request $i code=$code"; fi
  i=$((i+1)); sleep 0.2
done
echo "requests=900 ok=$ok fail=$fail"'
```

Result while the Deployment rolled from `v2.1.1` to `v2.1.2`:

```text
requests=900 ok=900 fail=0
```

Earlier runs of the same loop: 335/337 during endpoint churn before the
`preStop: sleep 15` drain was added, and 900/900 after it.

## Rollout and rollback

```text
$ kubectl set image deployment/devops-task app=swadhinbiswas/devops-task:v2.1.2
deployment.apps/devops-task image updated
$ kubectl rollout status deployment/devops-task
Waiting for deployment "devops-task" rollout to finish: 1 out of 2 new replicas have been updated...
Waiting for deployment "devops-task" rollout to finish: 1 old replicas are pending termination...
deployment "devops-task" successfully rolled out
$ kubectl rollout undo deployment/devops-task
deployment.apps/devops-task rolled back
$ kubectl rollout status deployment/devops-task
Waiting for deployment "devops-task" rollout to finish: 1 old replicas are pending termination...
deployment "devops-task" successfully rolled out
$ kubectl get deployment devops-task -o jsonpath='{.spec.template.spec.containers[0].image}'
swadhinbiswas/devops-task:v2.1.1
$ kubectl apply -k k8s/
deployment.apps/devops-task configured
$ kubectl get deployment devops-task -o jsonpath='{.spec.template.spec.containers[0].image}'
swadhinbiswas/devops-task:v2.1.2
```

## The reported version follows the image

The ConfigMap used to carry `APP_VERSION`, and the pod spec overrides the
image's own environment, so the application reported the ConfigMap value no
matter which image was running. That made a rollout impossible to prove by
version. It is fixed at the source: the key is gone from
`k8s/configmap.yaml` and from the chart values, the version comes from the
image tag, and `scripts/check_versions.sh` fails the build if the key is
added back.

```text
=== apply the manifests (APP_VERSION removed from the ConfigMap) ===
service/devops-task unchanged
deployment.apps/devops-task configured
horizontalpodautoscaler.autoscaling/devops-task unchanged
ingress.networking.k8s.io/devops-task unchanged

=== restart so the pods pick up the new ConfigMap ===
deployment.apps/devops-task restarted
Waiting for deployment "devops-task" rollout to finish: 1 old replicas are pending termination...
deployment "devops-task" successfully rolled out
image:  swadhinbiswas/devops-task:v2.1.2
health: {"status":"ok","version":"2.1.2","environment":"staging"}

=== roll back the image to v2.1.1: the version must follow the image ===
deployment.apps/devops-task image updated
Waiting for deployment "devops-task" rollout to finish: 1 old replicas are pending termination...
deployment "devops-task" successfully rolled out
image:  swadhinbiswas/devops-task:v2.1.1
health: {"status":"ok","version":"2.1.1","environment":"staging"}

=== rollout undo ===
deployment.apps/devops-task rolled back
Waiting for deployment "devops-task" rollout to finish: 1 old replicas are pending termination...
deployment "devops-task" successfully rolled out
image:  swadhinbiswas/devops-task:v2.1.2
health: {"status":"ok","version":"2.1.2","environment":"staging"}

=== configmap now ===
{"APP_ENV":"staging","LOG_LEVEL":"INFO"}
=== pod environment ===
APP_VERSION=2.1.2
```
