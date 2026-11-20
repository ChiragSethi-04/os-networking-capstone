#!/usr/bin/env bash
# E4: attack surface. This script captures the AFTER-hardening state for the
# record; the BEFORE-hardening nmap/nikto evidence is captured by
# lab/scripts/harden.sh itself (nmap_web_before.txt / nmap_db_before.txt),
# run right before ufw/Fail2Ban/SSH hardening is applied, since "before" only
# makes sense prior to that one-way change.
# Author: [GROUP MEMBER PLACEHOLDER]
# Date: [DATE PLACEHOLDER]
set -euo pipefail
source "$(dirname "$0")/common.sh"

mkdir -p evidence/raw
OUT="evidence/raw/E4_$(date +%Y%m%dT%H%M%S).txt"
{
  echo "=== E4 raw output ==="
  echo "date_utc=$(date -u +%FT%TZ)"
  echo "--- nmap -sV -p- web (after hardening) ---"
  multipass exec attacker -- nmap -sV -p- "${WEB_IP}"
  echo "--- nmap -sV -p- db (after hardening) ---"
  multipass exec attacker -- nmap -sV -p- "${DB_IP}"
  echo "--- nikto -h https://web -ssl ---"
  multipass exec attacker -- bash -c "nikto -h https://${WEB_IP} -ssl" || true
} > "$OUT" 2>&1

echo "E4 raw output: $OUT"
echo "(before-hardening nmap files: evidence/raw/nmap_web_before.txt, nmap_db_before.txt)"
