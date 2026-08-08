# argocd-apps

GitOps definitions for the observability stack. ArgoCD watches `stack/` and
reconciles it onto the cluster — **after bootstrap, `git push` is the only
deploy step.** No `kubectl`, no `helm`, no `terragrunt`.

## Layout

```
root.yaml                  app-of-apps parent — apply once, by hand
stack/
  monitoring.yaml          kube-prometheus-stack 65.5.1  (Prometheus/Grafana/Alertmanager)
  loki.yaml                loki 6.18.0                   (log store, SingleBinary)
  alloy.yaml               alloy 1.11.1                  (log collector DaemonSet)
  loki-datasource.yaml     ConfigMap wiring Loki into Grafana
```

`root.yaml` points at `stack/` only, never at itself — so it can't prune its
own definition.

## Sync waves

Children apply in order; each wave waits for the previous to go Healthy.

| Wave | Resource | Why it waits |
|------|----------|--------------|
| 0 | monitoring | creates the `monitoring` namespace everything else needs |
| 1 | loki | must accept pushes before a collector starts sending |
| 2 | alloy | ships to Loki |
| 3 | loki-datasource | needs the `monitoring` namespace *and* a live Loki |

## Required secrets — create these BEFORE bootstrapping

Both are referenced by `stack/monitoring.yaml` and are deliberately **not** in
Git. Without them Grafana and Alertmanager pods sit in
`CreateContainerConfigError` until you create them (they recover on their own
once the secrets exist — it is not fatal, just noisy).

```bash
# Namespace first — the secrets need somewhere to live.
kubectl create namespace monitoring --dry-run=client -o yaml | kubectl apply -f -

# 1. Grafana admin login
kubectl -n monitoring create secret generic grafana-admin \
  --from-literal=admin-user=admin \
  --from-literal=admin-password='<YOUR_PASSWORD>'

# 2. Discord webhook for Alertmanager.
#    The key MUST be `webhook-url` — monitoring.yaml reads it from
#    /etc/alertmanager/secrets/alertmanager-discord/webhook-url
kubectl -n monitoring create secret generic alertmanager-discord \
  --from-literal=webhook-url='<YOUR_DISCORD_WEBHOOK_URL>'
```

To rotate either value later, `kubectl delete secret` + recreate. Alertmanager
picks up `webhook_url_file` changes without a restart; Grafana needs a pod
restart to re-read its admin env vars.

> These replace what used to be inline plaintext in the Terraform Helm values.
> If you want the secrets themselves in Git too, the next step is
> [Sealed Secrets](https://sealed-secrets.netlify.app/) or External Secrets —
> both let ArgoCD manage encrypted material safely. Until then, the two
> commands above are the one manual step that isn't GitOps.

## Chart gotchas encoded here

These are load-bearing. Read before editing values.

1. **`grafana.dnsConfig`, not `grafana.podDnsConfig`.** Grafana's image is
   Alpine/musl; musl walks the full `ndots:5` search path and intermittently
   returns "no such host" for cluster-internal names. `ndots:2` fixes it.
   `podDnsConfig` is not in this chart's schema and is silently ignored.
2. **`chunksCache` and `resultsCache` must stay `enabled: false`.** They are
   memcached subcharts requesting ~9.6GB combined — unschedulable on a 4GB node.
3. **Chart is `loki`, not `loki-stack`.** `loki-stack` is deprecated and pins
   Loki 2.6.1, which fails Grafana's datasource health-check query.
4. **Alertmanager's `receivers:` must declare `name: 'null'`.** The Watchdog
   route targets it; omit it and reconciliation fails with
   `undefined receiver 'null'`.
5. **Discord uses `discord_configs` + `webhook_url`/`webhook_url_file`.**
   `webhook_configs` + `url` is the Slack-compatible shape and will not work.
6. **`lokiCanary` is top-level in loki 6.x.** Nesting it under `monitoring:`
   (as the old Terraform module did) is silently ignored, which is why canary
   pods kept running despite being "disabled".
7. **`ServerSideApply=true` is required on the monitoring app.** The
   `monitoring.coreos.com` CRDs exceed the 256KB `last-applied-configuration`
   annotation limit that client-side apply uses; without it the sync fails with
   `metadata.annotations: Too long`.
8. A Grafana datasource save can 409-conflict when a browser tab and the
   sidecar ConfigMap watcher write concurrently. That is not DNS — don't chase
   it as one.

## Validation

Every PR touching `argocd-apps/**` renders all three charts through
`helm template` in CI (`.github/workflows/validate-argocd-apps.yaml`). Run the
same check locally:

```bash
pip install pyyaml
python3 .github/scripts/validate_argocd_apps.py argocd-apps
```
