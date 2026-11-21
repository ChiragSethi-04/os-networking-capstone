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
# -Pn: db's ufw correctly blocks unsolicited traffic (including nmap's own
# ping probe) from the attacker VM, which isn't in its allow-list at all
# (only web's IP and the Mac's are) - without -Pn, nmap's host-discovery
# probe gets no reply and it reports "Host seems down" without ever
# actually checking port 3306, which is not what this check is for.
multipass exec attacker -- nmap -Pn -p 3306 "${DB_IP}"

echo "--- directory listing (expect 403/404) ---"
code=$(curl -sk -o /dev/null -w "%{http_code}" "https://${WEB_IP}/no-index/")
echo "code=$code"
[[ "$code" == "403" || "$code" == "404" ]] || { echo "FAIL: expected 403/404"; fail=1; }

echo "--- SSH key login works, password login refused ---"
ssh -i lab/.secrets/capstone_id_ed25519 -o StrictHostKeyChecking=accept-new \
  -o ConnectTimeout=5 "ubuntu@${WEB_IP}" "echo key login ok" || { echo "FAIL: key login broken"; fail=1; }

# Captured into a variable first, not piped directly into `grep -q`:
# ssh exits 255 on this expected auth failure, and under `pipefail` that
# propagates as the whole pipeline's result regardless of whether grep
# matched - the same masking bug documented in docs/decisions.md for
# provision.sh's cloud-init check and test_phase3.sh's openssl checks.
password_auth_output=$(ssh -o PreferredAuthentications=password -o PubkeyAuthentication=no \
    -o ConnectTimeout=5 -o BatchMode=yes "ubuntu@${WEB_IP}" "echo should not happen" 2>&1 || true)
if echo "$password_auth_output" | grep -qi "Permission denied\|denied (publickey"; then
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
