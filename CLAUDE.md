# K3s GitOps + CI/CD — Project Context

## Infrastructure (already provisioned, do not recreate)
- Proxmox host reachable via SSH jump: `root@10.10.10.205`
- K3s cluster: 1 master (192.168.1.211) + 2 workers (192.168.1.212, .213)
- kubectl commands go through jump host:
  `ssh -J root@10.10.10.205 debian@192.168.1.211 'sudo k3s kubectl ...'`
- Terraform (this repo, live/k3s-cluster) provisions the VMs via Proxmox provider
- ArgoCD is already installed on the cluster and running

## Goal for this task
Consolidate everything into THIS single repo. Set up:
1. `argocd-apps/` folder — ArgoCD app-of-apps manifests for:
   - Prometheus + Grafana (kube-prometheus-stack, version 65.5.1 — proven stable)
   - Loki (chart "loki", version 6.18.0 — proven stable, NOT "loki-stack")
   - Grafana Alloy (log collector, verify latest chart version on ArtifactHub)
2. GitHub Actions workflow that:
   - Validates argocd-apps/*.yaml on every PR (helm template dry-run / kubeval)
   - On merge to main, does nothing else manually — ArgoCD auto-syncs from Git
3. One-time bootstrap: after pushing, I will manually run
   `kubectl apply -f argocd-apps/root.yaml` once. After that everything
   syncs from git push alone — no more manual kubectl/helm commands.

## Known chart gotchas — avoid repeating these
1. Grafana's Alpine/musl DNS resolver bug with default `ndots:5` causes
   intermittent "no such host" errors on cluster-internal service names.
   Fix: `grafana.dnsConfig.options` = `[{name: ndots, value: "2"}]`
   (NOT `podDnsConfig` — wrong path for this chart schema).
2. Loki chart's `chunksCache`/`resultsCache` (memcached subcharts) request
   ~9.6GB memory by default — always set both to `enabled: false` for
   homelab-scale clusters.
3. Use chart `loki` (Grafana Labs current chart), NOT `loki-stack`
   (deprecated, pins Loki 2.6.1 which fails Grafana's health-check query).
4. Alertmanager's route config MUST include a `receiver: 'null'` entry
   in receivers, or reconciliation fails with "undefined receiver 'null'".
5. Discord webhooks need `discord_configs` + `webhook_url` key,
   NOT `webhook_configs` + `url` (that's Slack-compatible format only).
6. Grafana data source save can 409-conflict from concurrent updates
   (browser tab + sidecar ConfigMap watcher) — this is not a DNS issue,
   don't misdiagnose it as one.
## Cleanup required BEFORE building the new ArgoCD stack
There is an existing Terraform-managed monitoring/logging stack that must be
torn down first (it will conflict with the new ArgoCD-managed one):

- `live/monitoring/` — Terraform module deploying kube-prometheus-stack
  (Prometheus, Grafana, Alertmanager) via `helm_release`
- `live/logging/` — Terraform module deploying Loki + Promtail via `helm_release`

Steps to remove:
1. `cd live/monitoring && terragrunt destroy` (requires SSH tunnel to
   192.168.1.211:6443 and GRAFANA_ADMIN_PASSWORD + DISCORD_WEBHOOK_URL
   env vars set — check root terragrunt.hcl for how these are read via get_env())
2. `cd live/logging && terragrunt destroy`
3. Confirm namespaces are actually gone:
   `kubectl get pods -n monitoring` and `kubectl get pods -n logging`
   should both return "No resources found" or the namespace should not exist
4. Delete the `live/monitoring/` and `live/logging/` directories entirely
   (and their state files) since they're being replaced by argocd-apps/ —
   keep only `live/k3s-cluster/` (VM provisioning) and `live/argocd/`
   (ArgoCD itself, which stays Terraform-managed since it's the bootstrap tool)
5. Only after cleanup is confirmed, proceed to create the new argocd-apps/ stack
## Repo structure to create
k3s-cluster/
├── argocd-apps/
│   ├── root.yaml              # app-of-apps parent
│   └── stack/
│       ├── monitoring.yaml
│       ├── loki.yaml
│       ├── alloy.yaml
│       └── loki-datasource.yaml
└── .github/
    └── workflows/
        └── validate-argocd-apps.yaml

## Secrets note
Grafana admin password and Discord webhook are currently inline plaintext
in Helm values for testing. Flag this — should move to K8s Secrets or
GitHub encrypted secrets before treating this as production-ready.