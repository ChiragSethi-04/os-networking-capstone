#!/usr/bin/env bash
# Purpose: Phase 2 acceptance check.
# Author: [GROUP MEMBER PLACEHOLDER]
# Date: [DATE PLACEHOLDER]
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT_DIR"
source lab/.env
mkdir -p evidence/raw
OUT="evidence/raw/phase2_check_$(date +%Y%m%dT%H%M%S).txt"
fail=0

{
  echo "--- curl http://web/ ---"
  curl -s -o /tmp/index.html -w "HTTP %{http_code}\n" "http://${WEB_IP}/" || fail=1
  grep -o "<title>.*</title>" /tmp/index.html || fail=1

  echo "--- /api/health ---"
  curl -s "http://${WEB_IP}/api/health" || fail=1
  echo ""

  echo "--- POST /api/contact ---"
  curl -s -X POST -H 'Content-Type: application/json' \
    -d '{"name":"Phase2 Test","email":"test@example.com","message":"acceptance check"}' \
    "http://${WEB_IP}/api/contact" || fail=1
  echo ""

  echo "--- row visible from db ---"
  multipass exec db -- sudo mysql -N -e \
    "SELECT COUNT(*) FROM meridian.contact_messages WHERE email='test@example.com';" || fail=1

  echo "--- systemctl status (web) ---"
  multipass exec web -- systemctl is-active nginx meridian-app mariadb 2>&1 || true
  multipass exec db -- systemctl is-active mariadb 2>&1 || true

  echo "--- enable Apache baseline and check 8080 ---"
  multipass exec web -- sudo systemctl start apache2
  sleep 1
  curl -s -o /tmp/index8080.html -w "HTTP %{http_code}\n" "http://${WEB_IP}:8080/" || fail=1
  diff -q /tmp/index.html /tmp/index8080.html && echo "Apache 8080 serves identical page" || echo "WARNING: pages differ"
  multipass exec web -- sudo systemctl stop apache2
  multipass exec web -- sudo systemctl disable apache2

  echo "--- ss -tulpn (web, db) ---"
  multipass exec web -- sudo ss -tulpn
  multipass exec db -- sudo ss -tulpn
} | tee "$OUT"

if [[ $fail -eq 0 ]]; then
  echo "PHASE 2: PASS (evidence: $OUT)"
else
  echo "PHASE 2: FAIL (evidence: $OUT)"
  exit 1
fi
