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
  # On this Multipass/QEMU/Ubuntu-26.04-image combination, `multipass launch`
  # itself can hang indefinitely: it waits for cloud-init to reach a CLEAN
  # "done" status, but cloud-init here always ends "degraded done" because
  # of a harmless NIC-rename race (enp0s1 -> eth0, "[busy]") that never
  # resolves differently. Launching in the background and polling `multipass
  # list` + `cloud-init status` ourselves avoids depending on the launch
  # command's own (unreliable, on this setup) completion signal. See
  # docs/decisions.md.
  local name="$1" cpus="$2" mem="$3" disk="$4" cloudinit="$5"
  if multipass info "$name" 2>&1 | cat >/dev/null; then
    echo "[$name] already exists, skipping launch"
    return
  fi

  echo "[$name] launching (backgrounded, polling instead of trusting launch's own wait)..."
  multipass launch lts --name "$name" --cpus "$cpus" --memory "$mem" --disk "$disk" \
    --cloud-init "$cloudinit" >/tmp/multipass_launch_${name}.log 2>&1 &
  local launch_pid=$!

  local waited=0 state=""
  while (( waited < 600 )); do
    state=$(multipass info "$name" --format csv 2>/dev/null | tail -1 | cut -d',' -f2)
    [[ "$state" == "Running" ]] && break
    sleep 5
    waited=$(( waited + 5 ))
  done
  if [[ "$state" != "Running" ]]; then
    echo "[$name] ERROR: did not reach Running within ${waited}s (state=$state)" >&2
    exit 1
  fi
  echo "[$name] Running after ${waited}s, waiting for cloud-init to reach a terminal state..."

  waited=0
  while (( waited < 300 )); do
    if multipass exec "$name" -- cloud-init status 2>/dev/null | grep -qE "status: (done|error)"; then
      break
    fi
    sleep 5
    waited=$(( waited + 5 ))
  done
  multipass exec "$name" -- cloud-init status --long 2>&1 || true

  if kill -0 "$launch_pid" 2>/dev/null; then
    echo "[$name] launch command still waiting on its own (unreliable) clean-done check; killing it, the VM itself is fine"
    kill "$launch_pid" 2>/dev/null || true
  fi
}

launch_vm web      2 2G 10G lab/cloud-init/web.yaml
launch_vm db       1 1G 8G  lab/cloud-init/db.yaml
launch_vm attacker 1 1G 8G  lab/cloud-init/attacker.yaml

echo "Waiting for cloud-init to finish on all VMs..."
for name in web db attacker; do
  multipass exec "$name" -- cloud-init status --wait || true
done

# Column position is looked up by header name ("Ipv4"), not a hardcoded
# index: multipass's CSV schema has changed between versions (an extra
# "Zone"/"Zone available" pair was inserted before Ipv4 on this version),
# and a hardcoded `cut -f3` silently grabbed the zone name instead of an IP.
get_ip() {
  multipass info "$1" --format csv | awk -F, '
    NR==1 { for (i=1;i<=NF;i++) if ($i=="Ipv4") col=i }
    NR==2 { print $col }
  ' | cut -d'/' -f1 | tr -d '[:space:]'
}
WEB_IP=$(get_ip web)
DB_IP=$(get_ip db)
ATT_IP=$(get_ip attacker)

for pair in "WEB_IP:$WEB_IP" "DB_IP:$DB_IP" "ATT_IP:$ATT_IP"; do
  name="${pair%%:*}"; value="${pair#*:}"
  if ! [[ "$value" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]; then
    echo "ERROR: $name did not resolve to an IPv4 address (got '$value')" >&2
    exit 1
  fi
done

cat > lab/.env <<EOF
WEB_IP=$WEB_IP
DB_IP=$DB_IP
ATT_IP=$ATT_IP
EOF
echo "Recorded IPs in lab/.env:"
cat lab/.env

# Deployed as a boot-time systemd oneshot, not a one-time `tee -a`: this
# instance's cloud-init `manage_etc_hosts` setting was baked in at first
# launch and re-applies itself on every subsequent boot, which would wipe
# a plain append (see docs/decisions.md and
# lab/configs/systemd/ensure_hosts.sh.template).
sed -e "s/WEB_IP_PLACEHOLDER/${WEB_IP}/" -e "s/DB_IP_PLACEHOLDER/${DB_IP}/" \
    -e "s/ATT_IP_PLACEHOLDER/${ATT_IP}/" \
    lab/configs/systemd/ensure_hosts.sh.template > /tmp/ensure_hosts.sh

for name in web db attacker; do
  echo "[$name] deploying the hosts-entry systemd unit"
  multipass transfer /tmp/ensure_hosts.sh "$name:/tmp/ensure_hosts.sh"
  multipass transfer lab/configs/systemd/capstone-hosts.service "$name:/tmp/capstone-hosts.service"
  multipass exec "$name" -- sudo bash -c '
    set -e
    mv /tmp/ensure_hosts.sh /usr/local/bin/ensure_hosts.sh
    chmod +x /usr/local/bin/ensure_hosts.sh
    mv /tmp/capstone-hosts.service /etc/systemd/system/capstone-hosts.service
    systemctl daemon-reload
    systemctl enable --now capstone-hosts.service
  '
done
rm -f /tmp/ensure_hosts.sh

PUBKEY_CONTENT=$(cat "${SSH_KEY}.pub")
for name in web db attacker; do
  echo "[$name] verifying SSH key login as ubuntu"
  multipass exec "$name" -- bash -c "grep -qxF '$PUBKEY_CONTENT' /home/ubuntu/.ssh/authorized_keys" \
    && echo "[$name] ubuntu authorized_keys OK" \
    || echo "[$name] WARNING: ubuntu authorized_keys missing expected key"
done

echo "Disabling unattended-upgrades (it rebooted the web VM mid-Phase-4 once without warning; see docs/decisions.md)..."
for name in web db attacker; do
  multipass transfer lab/configs/systemd/disable-auto-updates.sh "$name:/tmp/disable-auto-updates.sh"
  multipass exec "$name" -- sudo bash /tmp/disable-auto-updates.sh
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

echo "Ensuring testssl.sh is present on attacker (cloud-init's runcmd clone can race the network at first boot)..."
multipass exec attacker -- bash -c '
  if [[ -x /opt/testssl.sh/testssl.sh ]]; then
    echo "testssl.sh already present"
  else
    sudo rm -rf /opt/testssl.sh
    sudo git clone --depth 1 https://github.com/testssl/testssl.sh.git /opt/testssl.sh
    sudo chmod +x /opt/testssl.sh/testssl.sh
  fi
'

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
