#!/usr/bin/env bash
# Purpose: verify host tooling, architecture and resources before provisioning.
# Author: [GROUP MEMBER PLACEHOLDER]
# Date: [DATE PLACEHOLDER]
set -euo pipefail

mkdir -p evidence/raw

OUT="evidence/raw/preflight_$(date +%Y%m%dT%H%M%S).txt"

{
  echo "=== $(date -u +%FT%TZ) preflight ==="
  echo "--- uname -a ---"
  uname -a
  echo "--- macOS version ---"
  sw_vers
  echo "--- disk ---"
  df -h /
  echo "--- memory ---"
  sysctl hw.memsize
  echo "--- tools ---"
  for t in brew multipass python3 dot pandoc xelatex tshark git; do
    if command -v "$t" >/dev/null 2>&1; then
      echo "$t: FOUND ($(command -v "$t"))"
    else
      echo "$t: MISSING"
    fi
  done
  echo "--- repo tree ---"
  find . -maxdepth 3 -not -path '*/.git*' | sort
} | tee "$OUT"

echo ""
echo "Preflight report saved to $OUT"
