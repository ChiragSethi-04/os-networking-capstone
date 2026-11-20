#!/usr/bin/env bash
# Purpose: Phase 1 acceptance check - 3 VMs running, mutual ping, SSH key login,
# tools present.
# Author: [GROUP MEMBER PLACEHOLDER]
# Date: [DATE PLACEHOLDER]
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT_DIR"
source lab/.env

fail=0

echo "--- VM states ---"
multipass list

for name in web db attacker; do
  state=$(multipass info "$name" --format csv | tail -1 | cut -d',' -f2)
  if [[ "$state" != "Running" ]]; then
    echo "FAIL: $name is not Running (state=$state)"
    fail=1
  else
    echo "OK: $name is Running"
  fi
done

echo "--- mutual ping ---"
declare -A IPS=(["web"]=$WEB_IP ["db"]=$DB_IP ["attacker"]=$ATT_IP)
for src in web db attacker; do
  for dst in web db attacker; do
    [[ "$src" == "$dst" ]] && continue
    if multipass exec "$src" -- ping -c1 -W2 "${IPS[$dst]}" >/dev/null 2>&1; then
      echo "OK: $src -> $dst ping"
    else
      echo "FAIL: $src -> $dst ping"
      fail=1
    fi
  done
done

echo "--- SSH key login from Mac ---"
for name in web db attacker; do
  ip="${IPS[$name]}"
  if ssh -i lab/.secrets/capstone_id_ed25519 -o StrictHostKeyChecking=accept-new \
      -o ConnectTimeout=5 "ubuntu@${ip}" "echo ok" 2>/dev/null | grep -q ok; then
    echo "OK: SSH key login to $name"
  else
    echo "FAIL: SSH key login to $name"
    fail=1
  fi
done

echo "--- tool versions ---"
multipass exec web -- bash -c 'wrk --version 2>&1 | head -1; nginx -v 2>&1' || fail=1
multipass exec attacker -- bash -c 'hydra -h 2>&1 | head -1; nmap --version | head -1' || fail=1

if [[ $fail -eq 0 ]]; then
  echo "PHASE 1: PASS"
else
  echo "PHASE 1: FAIL"
  exit 1
fi
