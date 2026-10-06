# GitOps Microservice Demo

A small Python (Flask) service taken all the way from code to a GitOps-managed deployment on a local Kubernetes cluster, with metrics, dashboards, alerts and a runbook.

The goal is to practise the day-to-day loop of operating a containerised service: build, test, scan, deploy from Git, observe, break it on purpose, diagnose, and roll back.

## Architecture

```
 developer ── git push ──► GitHub repo ──► GitHub Actions CI
                              │              (pytest, helm lint, terraform validate,
                              │               docker build, Trivy scan)
                              │
                              ▼  watched by
 ┌──────────────────────── kind cluster "skao-demo" ────────────────────────┐
 │                                                                          │
 │  argocd namespace      Argo CD ── syncs charts/demo-service ──┐          │
 │                                                               ▼          │
 │  demo namespace        Deployment (2 pods) ◄── Service ◄── ServiceMonitor│
 │                         /  /healthz  /readyz  /metrics        │          │
 │                                                               ▼          │
 │  monitoring namespace  Prometheus (scrapes /metrics, evaluates alerts)   │
 │                        Grafana (dashboard loaded from a ConfigMap)       │
 └──────────────────────────────────────────────────────────────────────────┘
        ▲
        │ installed by Terraform (helm provider): kube-prometheus-stack + Argo CD
```

| Layer | Tool | Where |
|---|---|---|
| Application | Python 3.12, Flask, prometheus_client, gunicorn | `app/` |
| Tests | pytest | `tests/` |
| Container | Docker (slim base, non-root user) | `Dockerfile` |
| Packaging | Helm chart | `charts/demo-service/` |
| Platform (IaC) | Terraform with the Helm provider | `terraform/` |
| Delivery (GitOps) | Argo CD Application with auto-sync, prune, self-heal | `argocd/application.yaml` |
| CI | GitHub Actions | `.github/workflows/ci.yml` |
| Observability | Prometheus, Grafana, PrometheusRule alerts | chart templates + `dashboards/` |
| Operations | Incident drills, upgrade and rollback | `RUNBOOK.md` |

## Prerequisites

- Docker Desktop (give it at least 6 GB of memory: the monitoring stack and Argo CD are not tiny)
- `kind`, `kubectl`, `helm`, `terraform` (macOS: `brew install kind kubectl helm` and `brew tap hashicorp/tap && brew install hashicorp/tap/terraform`)
- Python 3.12 for running the tests locally

## Quick start

```bash
# 1. Tests and image
python -m venv .venv && source .venv/bin/activate
pip install -r requirements-dev.txt
make test
make build                      # demo-service:0.1.0

# 2. Cluster and platform
make cluster                    # kind cluster "skao-demo"
export TF_VAR_grafana_admin_password='choose-a-password'
make platform                   # Terraform installs kube-prometheus-stack + Argo CD (5-10 min)

# 3. Deploy through Argo CD
make load                       # copy the image into the kind node
make argocd-app                 # Argo CD now owns the deployment
kubectl -n demo get pods        # two demo-service pods, Running and Ready

# 4. Look at it (each in its own terminal)
make pf-app                     # http://localhost:8081
make pf-grafana                 # http://localhost:3000  -> dashboard "Demo Service (GitOps demo)"
make pf-prometheus              # http://localhost:9090  -> Status > Targets, Alerts
make pf-argocd                  # http://localhost:8080  (password: make argocd-password)
make traffic                    # generate some load so the graphs move
```

## The GitOps loop

Git is the single source of truth for what runs in the cluster. To change the deployment, change the chart in Git, not the cluster:

1. Edit `charts/demo-service/values.yaml` (for example `replicaCount: 3`).
2. Commit and push to `main`.
3. Argo CD detects the new commit (polls every ~3 minutes, or press Refresh) and syncs.
4. `selfHeal` reverts manual `kubectl` edits; `prune` removes resources deleted from Git.

Rolling back is a `git revert` of the bad commit.

**Releasing a new app version.** Bump the code, `make build TAG=0.2.0`, `make load TAG=0.2.0`, then set `image.tag: "0.2.0"` in `values.yaml` and push. The Deployment uses `maxUnavailable: 0` with readiness probes, so the old pods keep serving until the new ones are ready.

## Observability

- **Metrics** (`/metrics`): `http_requests_total{method,endpoint,status}` and `http_request_duration_seconds` (histogram). Labels use the route template, not the raw URL, to keep label cardinality bounded. Probe and scrape requests are excluded.
- **Dashboard**: request rate by status, error ratio, p50/p95 latency, pod restarts and CPU, with a namespace selector. It ships with the chart as a ConfigMap that the Grafana sidecar loads automatically.
- **Alerts** (`PrometheusRule`): `DemoServiceHighErrorRate` (5xx ratio above 5% for 2 minutes) and `DemoServiceDown` (no healthy targets for 2 minutes). Both link to `RUNBOOK.md`.

## Security choices

- Image runs as a non-root user; the pod sets `runAsNonRoot`, drops all Linux capabilities, disallows privilege escalation and uses a read-only root filesystem (with an `emptyDir` for `/tmp`).
- CI scans every image with Trivy and fails on fixable CRITICAL or HIGH vulnerabilities.
- The Grafana password is passed as a sensitive Terraform variable from the environment and never committed. Terraform state and `*.tfvars` are git-ignored.
- CI runs with read-only repository permissions.

## What I would change for production

- CI would push images to a registry and update the image tag in Git automatically (or use Argo CD Image Updater), instead of `kind load`.
- Terraform state in a remote backend with locking; chart versions pinned (the `*_version` variables).
- Secrets from a secrets manager (External Secrets Operator or Sealed Secrets) instead of environment variables.
- Alertmanager routing to a real channel, plus logs (Loki or the Elastic stack) next to the metrics.
- Separate Argo CD projects and RBAC per team, and an ingress with TLS instead of port-forwarding.

## Clean up

```bash
make destroy
```
