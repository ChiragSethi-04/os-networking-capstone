#!/usr/bin/env bash
# Purpose: Phase 3 acceptance check (TLS).
# Author: [GROUP MEMBER PLACEHOLDER]
# Date: [DATE PLACEHOLDER]
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT_DIR"
source lab/.env
fail=0

echo "--- curl -sI http://web/ (expect 301) ---"
code=$(curl -s -o /dev/null -w "%{http_code}" "http://${WEB_IP}/")
redirect=$(curl -s -o /dev/null -w "%{redirect_url}" "http://${WEB_IP}/")
echo "code=$code redirect=$redirect"
[[ "$code" == "301" ]] || { echo "FAIL: expected 301"; fail=1; }

echo "--- curl --cacert ca.crt https://web/ (expect 200) ---"
code=$(curl -s --cacert lab/.secrets/ca/ca.crt --resolve "web:443:${WEB_IP}" \
  -o /dev/null -w "%{http_code}" "https://web/")
echo "code=$code"
[[ "$code" == "200" ]] || { echo "FAIL: expected 200 with trusted CA"; fail=1; }

echo "--- openssl s_client -tls1_1 from attacker (expect fail) ---"
if multipass exec attacker -- bash -c "echo | openssl s_client -connect ${WEB_IP}:443 -tls1_1" 2>&1 | grep -qi "handshake failure\|wrong version\|no protocols available\|alert"; then
  echo "OK: TLS 1.1 rejected"
else
  echo "FAIL: TLS 1.1 was not rejected"
  fail=1
fi

echo "--- openssl s_client -tls1_3 from attacker (expect success) ---"
if multipass exec attacker -- bash -c "echo | openssl s_client -connect ${WEB_IP}:443 -tls1_3" 2>&1 | grep -q "Verify return code"; then
  echo "OK: TLS 1.3 handshake succeeded"
else
  echo "FAIL: TLS 1.3 handshake did not complete"
  fail=1
fi

if [[ $fail -eq 0 ]]; then
  echo "PHASE 3: PASS"
else
  echo "PHASE 3: FAIL"
  exit 1
fi
