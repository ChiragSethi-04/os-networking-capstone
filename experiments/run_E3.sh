#!/usr/bin/env bash
# E3: reverse proxy overhead - static file served directly by Nginx vs
# through the Python app (gunicorn) behind Nginx.
# Author: [GROUP MEMBER PLACEHOLDER]
# Date: [DATE PLACEHOLDER]
set -euo pipefail
QUICK=0; for a in "$@"; do [[ "$a" == "--quick" ]] && QUICK=1; done
REPEATS=5; [[ "$QUICK" -eq 1 ]] && REPEATS=2
source "$(dirname "$0")/common.sh"

mkdir -p evidence/raw
OUT="evidence/raw/E3_$(date +%Y%m%dT%H%M%S).txt"
raw_header "E3" > "$OUT"

for run in $(seq 1 "$REPEATS"); do
  echo "--- run=$run path=static(/) ---" >> "$OUT"
  multipass exec attacker -- bash -c "wrk -t2 -c50 -d15s --latency https://${WEB_IP}/" >> "$OUT" 2>&1

  echo "--- run=$run path=proxied(/api/health) ---" >> "$OUT"
  multipass exec attacker -- bash -c "wrk -t2 -c50 -d15s --latency https://${WEB_IP}/api/health" >> "$OUT" 2>&1
done

echo "E3 raw output: $OUT"
