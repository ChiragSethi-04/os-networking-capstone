#!/usr/bin/env bash
# E8: resilience - kill nginx, show systemd + monitor restarts it and logs
# the event with timestamps; also prove logrotate with a forced run.
# This duplicates lab/scripts/test_phase5.sh's check but is kept as its own
# experiment script per CLAUDE.md section 6/7 (F13 resilience timeline).
# Author: [GROUP MEMBER PLACEHOLDER]
# Date: [DATE PLACEHOLDER]
set -euo pipefail
source "$(dirname "$0")/common.sh"

mkdir -p evidence/raw
OUT="evidence/raw/E8_$(date +%Y%m%dT%H%M%S).txt"
raw_header "E8" > "$OUT"

echo "--- killing nginx ---" >> "$OUT"
echo "kill_time_utc=$(date -u +%FT%TZ)" >> "$OUT"
mp_retry multipass exec web -- sudo systemctl kill -s SIGKILL nginx

for i in $(seq 1 14); do
  sleep 5
  if multipass exec web -- systemctl is-active --quiet nginx; then
    echo "detected_active_again_after_seconds=$((i * 5))" >> "$OUT"
    break
  fi
done

mp_retry multipass exec web -- tail -n 15 /var/log/web_status.log >> "$OUT"

echo "--- logrotate -d (dry run) ---" >> "$OUT"
mp_retry multipass exec web -- sudo logrotate -d /etc/logrotate.d/capstone >> "$OUT" 2>&1

echo "--- logrotate -f (forced run) ---" >> "$OUT"
mp_retry multipass exec web -- sudo logrotate -f /etc/logrotate.d/capstone >> "$OUT" 2>&1
mp_retry multipass exec web -- bash -c "ls -la /var/log/web_status.log* /var/log/nginx/*.gz 2>/dev/null" >> "$OUT"

echo "E8 raw output: $OUT"
