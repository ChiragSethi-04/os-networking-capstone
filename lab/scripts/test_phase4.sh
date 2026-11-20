#!/usr/bin/env bash
# Purpose: Phase 4 acceptance check (hardening).
# Author: [GROUP MEMBER PLACEHOLDER]
# Date: [DATE PLACEHOLDER]
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT_DIR"
source lab/.env
fail=0

echo "--- nmap -p- web (expect only 22,80,443) ---"
ports=$(multipass exec attacker -- nmap -p- "${WEB_IP}" | awk '/\/tcp/ && /open/ {print $1}' | cut -d/ -f1 | sort -n | tr '\n' ',')
echo "open ports: $ports"
if [[ "$ports" == "22,80,443," ]]; then
  echo "OK: only 22, 80, 443 open on web"
else
  echo "FAIL: unexpected port set on web ($ports)"
  fail=1
fi

echo "--- nmap db (expect 3306 filtered/closed from attacker) ---"
multipass exec attacker -- nmap -p 3306 "${DB_IP}"

echo "--- directory listing (expect 403/404) ---"
code=$(curl -sk -o /dev/null -w "%{http_code}" "https://${WEB_IP}/no-index/")
echo "code=$code"
[[ "$code" == "403" || "$code" == "404" ]] || { echo "FAIL: expected 403/404"; fail=1; }

echo "--- SSH key login works, password login refused ---"
ssh -i lab/.secrets/capstone_id_ed25519 -o StrictHostKeyChecking=accept-new \
  -o ConnectTimeout=5 "ubuntu@${WEB_IP}" "echo key login ok" || { echo "FAIL: key login broken"; fail=1; }

if ssh -o PreferredAuthentications=password -o PubkeyAuthentication=no \
    -o ConnectTimeout=5 -o BatchMode=yes "ubuntu@${WEB_IP}" "echo should not happen" 2>&1 | grep -qi "Permission denied\|denied (publickey"; then
  echo "OK: password auth refused"
else
  echo "FAIL: password auth was not clearly refused"
  fail=1
fi

if [[ $fail -eq 0 ]]; then
  echo "PHASE 4: PASS"
else
  echo "PHASE 4: FAIL"
  exit 1
fi
