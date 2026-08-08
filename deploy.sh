#!/bin/bash
set -e

echo "=== Setting up environment variables ==="

# Proxmox API token — read from the environment, or from an untracked file.
# It used to be hardcoded here; that put a root-equivalent credential one
# `git push` away from being public.
#   echo 'root@pam!terraform=YOUR-UUID' > ~/.proxmox_api_token && chmod 600 ~/.proxmox_api_token
PROXMOX_TOKEN_FILE="${PROXMOX_TOKEN_FILE:-$HOME/.proxmox_api_token}"
if [ -z "${PROXMOX_VE_API_TOKEN:-}" ] && [ -f "$PROXMOX_TOKEN_FILE" ]; then
  PROXMOX_VE_API_TOKEN="$(cat "$PROXMOX_TOKEN_FILE")"
fi
if [ -z "${PROXMOX_VE_API_TOKEN:-}" ]; then
  echo "ERROR: PROXMOX_VE_API_TOKEN is not set and $PROXMOX_TOKEN_FILE does not exist." >&2
  echo "       export PROXMOX_VE_API_TOKEN='root@pam!terraform=...'" >&2
  echo "       or write it to $PROXMOX_TOKEN_FILE (chmod 600)." >&2
  exit 1
fi
export PROXMOX_VE_API_TOKEN
export PROXMOX_VE_ENDPOINT="${PROXMOX_VE_ENDPOINT:-https://10.10.10.205:8006/}"
export K3S_SSH_PUBLIC_KEY="$(cat ~/.ssh/id_rsa.pub)"

# สร้าง token ใหม่แค่ครั้งแรก แล้วเก็บไว้ใช้ซ้ำ (กัน token เปลี่ยนทุกรอบรัน)
TOKEN_FILE="$HOME/.k3s_cluster_token"
if [ ! -f "$TOKEN_FILE" ]; then
  openssl rand -hex 32 > "$TOKEN_FILE"
fi
export K3S_CLUSTER_TOKEN="$(cat $TOKEN_FILE)"

echo "TOKEN=[${PROXMOX_VE_API_TOKEN:0:20}...]"
echo "ENDPOINT=[$PROXMOX_VE_ENDPOINT]"
echo "SSH_KEY=[${K3S_SSH_PUBLIC_KEY:0:30}...]"
echo "K3S_TOKEN=[${K3S_CLUSTER_TOKEN:0:10}...]"

cd ~/Documents/k3s-cluster/live/k3s-cluster

echo "=== Destroying existing VMs (if any) ==="
terragrunt destroy -auto-approve || true

echo "=== Cleaning cache ==="
rm -rf .terragrunt-cache

echo "=== Applying new cluster ==="
terragrunt apply -auto-approve

echo "=== Waiting for cloud-init and k3s to finish (90s) ==="
sleep 90

echo "=== Done! Check nodes with: ==="
echo "ssh -J root@10.10.10.205 debian@192.168.1.211 'sudo k3s kubectl get nodes'"