#!/usr/bin/env bash
# E9: TLS quality - testssl.sh report. The actual before/after runs happen
# inside lab/scripts/harden.sh (testssl_before.txt / testssl_after.txt),
# since "before" only makes sense prior to the one-way TLS hardening change.
# This script re-runs the AFTER report standalone so E9 can be re-verified
# without re-running all of Phase 3.
# Author: [GROUP MEMBER PLACEHOLDER]
# Date: [DATE PLACEHOLDER]
set -euo pipefail
source "$(dirname "$0")/common.sh"

mkdir -p evidence/raw
OUT="evidence/raw/E9_$(date +%Y%m%dT%H%M%S).txt"
{
  echo "=== E9 raw output ==="
  echo "date_utc=$(date -u +%FT%TZ)"
  mp_retry multipass exec attacker -- bash -c "/opt/testssl.sh/testssl.sh --quiet https://${WEB_IP}"
} > "$OUT" 2>&1 || true

echo "E9 raw output: $OUT"
echo "(Phase 3 before/after pair: evidence/raw/testssl_before.txt, testssl_after.txt)"
