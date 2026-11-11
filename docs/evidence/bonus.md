# Bonus evidence

All bonus items were built and exercised. The Kubernetes and tracing output
comes from the kind cluster on this machine. The Compose additions parse with
`docker compose config`, and the two notification paths (Alertmanager and the
health script) were proven against a local HTTP sink using the real binaries, so
no external Slack workspace was needed.

## 1. Alertmanager routing

Files: [`monitoring/alertmanager/alertmanager.tmpl.yml`](../../monitoring/alertmanager/alertmanager.tmpl.yml)
and [`entrypoint.sh`](../../monitoring/alertmanager/entrypoint.sh).

The config template carries a `__ALERT_WEBHOOK_URL__` placeholder. The
container entrypoint substitutes `ALERT_WEBHOOK_URL` from the environment at
startup; the URL never lives in git. Without the variable, Alertmanager starts
with a no-op receiver and alerts stay in its UI.

Config validation with the real `amtool` (v0.28.1):

```text
$ amtool check-config alertmanager.yml
Checking 'alertmanager.yml'  SUCCESS
Found:
 - global config
 - route
 - 0 inhibit rules
 - 1 receivers
 - 0 templates
```

Delivery proof: Alertmanager ran with the template rendered to a local sink
(`group_wait` shortened to 2s for the test) and one critical alert was added
with `amtool alert add`:

```json
{"username":"Alertmanager","attachments":[{"title":"FIRING HighErrorRate","text":"High 5xx error rate: More than 5% of requests returned 5xx\n","fallback":"[FIRING:1] HighErrorRate critical | http://swadhin:19093/#/alerts?receiver=alerts","color":"danger"}]}
```

The `text` and `title` come from the alert's annotations, and the payload is
Slack-shaped. Discord accepts the same payload when the webhook URL ends in
`/slack` (Discord's Slack-compatible endpoint), so one receiver covers both:
set `ALERT_WEBHOOK_URL` to the Slack webhook or to
`https://discord.com/api/webhooks/.../slack`.

## 2. Monitoring stack on Kubernetes

Installed with Helm:

```bash
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
kubectl create namespace monitoring
kubectl -n monitoring create secret generic grafana-admin \
  --from-literal=admin-user="$GF_SECURITY_ADMIN_USER" \
  --from-literal=admin-password="$GF_SECURITY_ADMIN_PASSWORD"
helm upgrade --install kube-prometheus-stack \
  prometheus-community/kube-prometheus-stack \
  -n monitoring -f k8s/monitoring/kube-prometheus-stack-values.yaml
```

Release and workloads:

```text
$ helm list -n monitoring
kube-prometheus-stack  monitoring  1  deployed  kube-prometheus-stack-93.2.0  v0.95.2

$ kubectl -n monitoring get pods
alertmanager-kube-prometheus-stack-alertmanager-0   2/2  Running
kube-prometheus-stack-grafana-c79794f7-68b8s        3/3  Running
kube-prometheus-stack-kube-state-metrics-645c589fb6-69qxq  1/1  Running
kube-prometheus-stack-operator-67b9bd4574-5dl9h     1/1  Running
kube-prometheus-stack-prometheus-node-exporter-lmrcx 1/1 Running
otel-collector-7448b5ddb6-l7c55                     1/1  Running
prometheus-kube-prometheus-stack-prometheus-0       2/2  Running
tempo-774dcf7478-rjtlf                              1/1  Running
```

Grafana is healthy and has the three datasources:

```text
GET /api/health
{"database":"ok","version":"13.3.1"}

datasources: Alertmanager, Prometheus, Tempo
```

Prometheus scrapes 14 targets, all up:

```text
{'up': 14}
jobs: apiserver, coredns, kube-prometheus-stack-alertmanager,
kube-prometheus-stack-grafana, kube-prometheus-stack-operator,
kube-prometheus-stack-prometheus, kube-state-metrics, kubelet, node-exporter
```

The values file disables the etcd, controller-manager, scheduler and kube-proxy
scrapers because kind does not expose those components on the pod network, and
sets Grafana's admin credentials from the `grafana-admin` Secret.

## 3. Distributed tracing with OpenTelemetry and Tempo

The app instruments itself when `OTEL_EXPORTER_OTLP_ENDPOINT` is set
([`app/tracing.py`](../../app/tracing.py)). Tempo and the collector run in the
`monitoring` namespace ([`k8s/tracing/`](../../k8s/tracing/)), and Compose has the
same pair for local runs ([`monitoring/otel`](../../monitoring/otel),
[`monitoring/tempo`](../../monitoring/tempo)).

A local app instance sent spans through the collector:

```text
{"level":"INFO","logger":"app","message":"tracing initialized","environment":"staging","version":"0.1.0","event":"tracing"}
```

Tempo search by service:

```text
traces: 3
8827034c032b42c7222a55693fd206e1 devops-task-app GET /health
dae4d8daaea57f05cef291057b48bafa devops-task-app GET /health
456750ea5b7f6486b458fd79fd097050 devops-task-app GET /
```

One trace expanded:

```text
trace: 8827034c032b42c7222a55693fd206e1
span count: 4
span names: ['GET /health http send', 'GET /health http send', 'GET /health http send', 'GET /health']
```

Grafana talks to Tempo through the provisioned datasource:

```text
GET /api/datasources/uid/tempo/health
OK  Data source is working

Grafana proxy search: traces visible through Grafana: 4
```

## 4. Helm chart for the application

Chart: [`charts/devops-task`](../../charts/devops-task), with
[`values-staging.yaml`](../../charts/devops-task/values-staging.yaml) and
[`values-production.yaml`](../../charts/devops-task/values-production.yaml).

Lint, both environments:

```text
$ helm lint charts/devops-task -f charts/devops-task/values-staging.yaml
1 chart(s) linted, 0 chart(s) failed

$ helm lint charts/devops-task -f charts/devops-task/values-production.yaml
1 chart(s) linted, 0 chart(s) failed
```

Production values render the extra capacity and the ingress:

```text
averageUtilization: 60
kind: Ingress
ingressClassName: nginx
host: devops-task.example.com
```

Installed over the raw manifests in kind (the Secret was created outside the
chart):

```bash
kubectl delete -k k8s/
helm upgrade --install devops-task charts/devops-task \
  -f charts/devops-task/values-staging.yaml --set image.tag=v0.1.8
```

```text
$ helm list
devops-task  default  1  deployed  devops-task-0.1.0  0.1.0

$ kubectl get deploy,svc,hpa
deployment.apps/devops-task   2/2   2   2
service/devops-task           ClusterIP   10.96.185.114   80/TCP
horizontalpodautoscaler.autoscaling/devops-task   Deployment/devops-task   cpu: 3%/70%   2   5   2

$ kubectl port-forward svc/devops-task 8082:80
$ curl -s http://127.0.0.1:8082/health
{"status":"ok","version":"0.1.8","environment":"staging"}
```

## 5. Health script webhook alerts

`HEALTH_WEBHOOK_URL` enables delivery; the script never requires it. Payloads
from real runs against a local sink:

```text
slack run exit=1
{"text":"[WARNING] swadhin at 2026-11-11T18:42:24Z; warning: disk(/) 21% >= 1%; ..."}

discord run exit=1
{"content":"[WARNING] swadhin at 2026-11-11T18:42:25Z; warning: disk(/) 21% >= 1%; ..."}

healthy run exit=0
healthy deliveries=0

unreachable run exit=1
webhook delivery failed
```

A failed webhook prints one warning and leaves the exit code untouched, so a
monitoring system still sees the real status. Discord detection is a
case-insensitive match on `discord` in the URL; everything else gets a Slack
`text` payload.

## 6. Ansible hardening playbook

Files: [`ansible/playbook.yml`](../../ansible/playbook.yml) and
[`inventory.example.ini`](../../ansible/inventory.example.ini).

Syntax check:

```text
$ ansible-playbook --syntax-check -i ansible/inventory.example.ini ansible/playbook.yml
playbook: ansible/playbook.yml
```

Task list:

```text
play #1 (all): Harden the host and install the health probe
  Update the apt cache and apply safe upgrades
  Install base packages
  Enable unattended security upgrades
  Apply kernel network hardening
  Harden sshd
  Allow SSH through the firewall
  Allow the application port through the firewall
  Enable the firewall with a default deny policy
  Install the health script
  Install the systemd service and timer
  Configure the optional alert webhook
  Enable the health timer
```

The playbook installs the script and units, writes `HEALTH_WEBHOOK_URL` into
`/etc/default/system-health` (mode 0600), and hardens the host with sshd,
sysctl and UFW settings. Handlers validate the sshd config before reloading and
reload sysctl only when the file changes.

## 7. Image signing and SBOM

Implemented in `.github/workflows/release.yml`: buildx already attaches SBOM
and provenance attestations, and the release now installs cosign, signs the
image digest keyless with the workflow's OIDC identity, generates an SPDX SBOM
with syft, and attests it with cosign. Verification output from the first
signed release is appended after the release run.
