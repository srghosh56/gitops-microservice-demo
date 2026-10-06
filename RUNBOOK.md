# Runbook: demo-service

How to diagnose and fix the two alerts, plus routine upgrade and rollback. Each section is also a drill you can run on purpose.

## First five minutes, for any alert

```bash
kubectl -n demo get pods -o wide              # Running? Ready? Restarts?
kubectl -n demo describe pod <pod>            # Events: probes, image pulls, OOMKilled
kubectl -n demo logs <pod> --tail=100         # Application errors
kubectl -n demo get events --sort-by=.lastTimestamp | tail -20
kubectl -n argocd get applications            # Is Argo CD Synced and Healthy?
```

Then check what changed recently: the Git history of `charts/demo-service/` and the Argo CD app history. Most incidents follow a change.

## Alert: DemoServiceHighErrorRate

**Meaning:** more than 5% of requests to the service returned 5xx for 2 minutes.

**Drill (cause it on purpose):**

1. Set `app.errorRate: "0.3"` in `charts/demo-service/values.yaml`, commit and push.
2. Wait for Argo CD to sync, then run `make pf-app` and `make traffic`.
3. Watch the Grafana error-ratio panel rise; after ~2 minutes the alert fires in Prometheus (Alerts tab).

**Diagnose:**

- Grafana: which status codes and endpoints? Did it start at a deploy?
- `kubectl -n demo logs -l app.kubernetes.io/name=demo-service --tail=50`: here you see `simulated failure returned`.
- `git log -p charts/demo-service/values.yaml`: the change that introduced it.

**Fix:** `git revert <commit>` and push. Argo CD rolls back; the error ratio drops and the alert resolves.

## Alert: DemoServiceDown

**Meaning:** Prometheus has had no healthy demo-service target for 2 minutes.

**Drill:** set `image.tag: "9.9.9"` (an image that does not exist) and push.

**Diagnose:**

- `kubectl -n demo get pods`: new pods in `ErrImagePull` / `ImagePullBackOff`.
- `kubectl -n demo describe pod <pod>`: the Events section names the missing image.
- Because of `maxUnavailable: 0`, the old pods keep running, so the alert may *not* fire. That is the rolling-update strategy doing its job. To see the alert, also scale to zero in Git (`replicaCount: 0`).

**Fix:** revert the commit. Other common causes of this alert: failing readiness probe (check `/readyz`), `CrashLoopBackOff` (check logs and `OOMKilled` in describe), or the ServiceMonitor no longer matching the Service labels (Prometheus > Status > Targets).

## Routine upgrade

1. `make build TAG=0.2.0 && make load TAG=0.2.0`
2. Set `image.tag: "0.2.0"` in `values.yaml`, push.
3. Watch `kubectl -n demo rollout status deploy/demo-service` and the Grafana error ratio.
4. Check `curl localhost:8081/` reports `"version": "0.2.0"`.

## Rollback

Preferred: `git revert` the change and push, so Git keeps describing what runs.
Emergency: roll back in the Argo CD UI (History and Rollback). Auto-sync must be disabled first, then re-enabled after Git has been fixed, otherwise Argo CD syncs straight back to `main`.
