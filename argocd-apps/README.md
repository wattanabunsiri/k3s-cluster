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
  alertmanager-config.yaml AlertmanagerConfig CR — Discord routing
  loki-datasource.yaml     ConfigMap wiring Loki into Grafana
  seaweedfs.yaml           seaweedfs 4.41.0 — S3 object storage lab (ns: storage)
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
| 4 | seaweedfs | independent of the above; last so it can't delay observability |

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
#    The key MUST be `webhook-url` — stack/alertmanager-config.yaml references
#    it by name+key via discordConfigs[].apiURL (a SecretKeySelector).
kubectl -n monitoring create secret generic alertmanager-discord \
  --from-literal=webhook-url='<YOUR_DISCORD_WEBHOOK_URL>'
```

```bash
# 3. SeaweedFS S3 credentials, in the `storage` namespace.
#    The key MUST be named `seaweedfs_s3_config` — it is mounted at /etc/sw and
#    read via -config=/etc/sw/seaweedfs_s3_config.
#    This generates strong random keys, creates the Secret, and saves a copy
#    locally for the aws CLI — without printing anything to your terminal.
kubectl create namespace storage --dry-run=client -o yaml | kubectl apply -f -

ADMIN_AK=$(openssl rand -hex 10)
ADMIN_SK=$(openssl rand -base64 30 | tr -d '/+=' | cut -c1-40)
READ_AK=$(openssl rand -hex 10)
READ_SK=$(openssl rand -base64 30 | tr -d '/+=' | cut -c1-40)

cat > ~/.seaweedfs-s3-creds <<EOF
AWS_ACCESS_KEY_ID=$ADMIN_AK
AWS_SECRET_ACCESS_KEY=$ADMIN_SK
READONLY_ACCESS_KEY_ID=$READ_AK
READONLY_SECRET_ACCESS_KEY=$READ_SK
EOF
chmod 600 ~/.seaweedfs-s3-creds

kubectl -n storage create secret generic seaweedfs-s3-config \
  --from-literal=seaweedfs_s3_config="{\"identities\":[
    {\"name\":\"admin\",\"credentials\":[{\"accessKey\":\"$ADMIN_AK\",\"secretKey\":\"$ADMIN_SK\"}],
     \"actions\":[\"Admin\",\"Read\",\"Write\",\"List\",\"Tagging\"]},
    {\"name\":\"readonly\",\"credentials\":[{\"accessKey\":\"$READ_AK\",\"secretKey\":\"$READ_SK\"}],
     \"actions\":[\"Read\",\"List\"]}]}"
```

To rotate any of these later, `kubectl delete secret` + recreate. The
prometheus-operator re-reads `alertmanager-discord` and regenerates its config
on its own; Grafana needs a pod restart to re-read its admin env vars; the
SeaweedFS S3 gateway needs a pod restart to re-read its config file.

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
   `undefined receiver 'null'`. In the generated config the operator prefixes
   CR receiver names, so these appear as `monitoring/discord/null`.
5. **Discord uses `discord_configs` + `webhook_url`. Do not use
   `webhook_url_file` in an inline `alertmanager.config`.** Alertmanager v0.27
   supports it, but prometheus-operator v0.77.2 validates the inline config
   *first* and its Discord parser only knows `webhook_url`. It fails with
   `no discord webhook URL provided` and never creates the StatefulSet — so
   Alertmanager silently doesn't exist. To keep the webhook out of Git, use the
   `AlertmanagerConfig` CR (`stack/alertmanager-config.yaml`), whose `apiURL` is
   a SecretKeySelector.
6. **`lokiCanary` is top-level in loki 6.x.** Nesting it under `monitoring:`
   (as the old Terraform module did) is silently ignored, which is why canary
   pods kept running despite being "disabled".
7. **`ServerSideApply=true` is required on the monitoring app — and needs
   ArgoCD ≥ v3.** The chart's 10 CRDs (largest: `prometheuses` at 777KB) blow
   past the 256KB client-side apply annotation limit, so managing them requires
   SSA. On ArgoCD v2.13.2 that was impossible: it predates k8s v1.36 and its
   structured-merge-diff dies on `.status.terminatingReplicas: field not
   declared in schema`, wedging the app at sync status `Unknown` — at which
   point it can no longer apply *anything*. Worked around with `skipCrds: true`
   until ArgoCD was upgraded to v3.5.0, which fixed it properly. **If you ever
   roll ArgoCD back below v3, you must re-add `skipCrds: true` at the same
   time.**
8. A Grafana datasource save can 409-conflict when a browser tab and the
   sidecar ConfigMap watcher write concurrently. That is not DNS — don't chase
   it as one.
9. **Any chart that generates secrets with Helm's `lookup` is unsafe under
   ArgoCD — always pass an `existing*Secret` instead.** SeaweedFS is the live
   example: `seaweedfs.getOrGeneratePassword` (`shared/_helpers.tpl:277`) calls
   `lookup` to reuse the current Secret, but ArgoCD renders with
   `helm template`, which has no cluster access. `lookup` returns nothing, so
   it falls through to `randAlphaNum` and mints new credentials. Worse, the
   Secret is a `pre-install,pre-upgrade` hook, so it is *excluded from the
   diff* — the app still reports Synced/Healthy while your S3 keys silently
   change on every sync. Setting `s3.existingConfigSecret` bypasses the whole
   path. Check any new chart for `lookup` before trusting its secret handling.
10. **SeaweedFS splits data from metadata.** The Volume Server holds the object
   bytes; the Filer holds filenames, paths and bucket contents. Both need their
   own PVC — if only the Volume Server is persisted, the bytes survive a
   restart but nothing can find them, which is indistinguishable from data
   loss.

## Validation

Every PR touching `argocd-apps/**` renders all three charts through
`helm template` in CI (`.github/workflows/validate-argocd-apps.yaml`). Run the
same check locally:

```bash
pip install pyyaml
python3 .github/scripts/validate_argocd_apps.py argocd-apps
```
