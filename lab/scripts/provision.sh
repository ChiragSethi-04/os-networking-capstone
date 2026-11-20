#!/usr/bin/env bash
# Purpose: launch the three lab VMs (web, db, attacker), record their IPs,
# add /etc/hosts entries inside each VM, and snapshot a clean baseline.
# Author: [GROUP MEMBER PLACEHOLDER]
# Date: [DATE PLACEHOLDER]
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT_DIR"
mkdir -p evidence/raw lab

SSH_KEY="lab/.secrets/capstone_id_ed25519"
if [[ ! -f "$SSH_KEY" ]]; then
  echo "SSH key $SSH_KEY not found. Run: ssh-keygen -t ed25519 -f $SSH_KEY -N \"\"" >&2
  exit 1
fi

launch_vm() {
  local name="$1" cpus="$2" mem="$3" disk="$4" cloudinit="$5"
  if multipass info "$name" >/dev/null 2>&1; then
    echo "[$name] already exists, skipping launch"
  else
    echo "[$name] launching..."
    multipass launch lts --name "$name" --cpus "$cpus" --memory "$mem" --disk "$disk" \
      --cloud-init "$cloudinit" --timeout 900
  fi
}

launch_vm web      2 2G 10G lab/cloud-init/web.yaml
launch_vm db       1 1G 8G  lab/cloud-init/db.yaml
launch_vm attacker 1 1G 8G  lab/cloud-init/attacker.yaml

echo "Waiting for cloud-init to finish on all VMs..."
for name in web db attacker; do
  multipass exec "$name" -- cloud-init status --wait || true
done

WEB_IP=$(multipass info web --format csv | tail -1 | cut -d',' -f3 | cut -d'/' -f1 | tr -d '[:space:]')
DB_IP=$(multipass info db --format csv | tail -1 | cut -d',' -f3 | cut -d'/' -f1 | tr -d '[:space:]')
ATT_IP=$(multipass info attacker --format csv | tail -1 | cut -d',' -f3 | cut -d'/' -f1 | tr -d '[:space:]')

cat > lab/.env <<EOF
WEB_IP=$WEB_IP
DB_IP=$DB_IP
ATT_IP=$ATT_IP
EOF
echo "Recorded IPs in lab/.env:"
cat lab/.env

HOSTS_BLOCK="$WEB_IP web
$DB_IP db
$ATT_IP attacker"

for name in web db attacker; do
  echo "[$name] writing /etc/hosts entries for web/db/attacker"
  echo "$HOSTS_BLOCK" | multipass exec "$name" -- sudo tee -a /etc/hosts >/dev/null
done

PUBKEY_CONTENT=$(cat "${SSH_KEY}.pub")
for name in web db attacker; do
  echo "[$name] verifying SSH key login as admin"
  multipass exec "$name" -- bash -c "grep -qxF '$PUBKEY_CONTENT' /home/admin/.ssh/authorized_keys" \
    && echo "[$name] admin authorized_keys OK" \
    || echo "[$name] WARNING: admin authorized_keys missing expected key"
done

echo "Installing wrk on web and attacker (not always in Ubuntu apt, build from source if missing)..."
for name in web attacker; do
  multipass exec "$name" -- bash -c '
    set -e
    if command -v wrk >/dev/null 2>&1; then
      echo "wrk already present"
    elif sudo apt-get install -y wrk >/dev/null 2>&1; then
      echo "wrk installed via apt"
    else
      echo "building wrk from source"
      sudo apt-get update -y
      sudo apt-get install -y build-essential libssl-dev git
      cd /tmp && rm -rf wrk && git clone --depth 1 https://github.com/wg/wrk.git
      cd wrk && make -j"$(nproc)"
      sudo cp wrk /usr/local/bin/wrk
    fi
  '
done

echo "Taking clean-baseline snapshots..."
for name in web db attacker; do
  multipass stop "$name"
  multipass snapshot "$name" --name clean-baseline --comment "Post phase-1 provisioning" || true
  multipass start "$name"
done

OUT="evidence/raw/lab_inventory.txt"
{
  echo "=== $(date -u +%FT%TZ) lab inventory ==="
  multipass list
  echo "--- lab/.env ---"
  cat lab/.env
  for name in web db attacker; do
    echo "--- $name: lscpu ---"
    multipass exec "$name" -- lscpu | head -15
    echo "--- $name: free -h ---"
    multipass exec "$name" -- free -h
    echo "--- $name: uname -a ---"
    multipass exec "$name" -- uname -a
  done
} | tee "$OUT"

echo "Phase 1 provisioning complete. Evidence: $OUT"
