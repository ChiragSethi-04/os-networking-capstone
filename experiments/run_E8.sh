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

# Each check gets its own short mp_retry (budget 3, not the usual 15 - the
# outer loop already provides 14 rounds of its own repetition over 70s):
# without this, a connection-refused blip on a given round looked
# identical to "nginx is still down" and was never distinguished from it,
# so a run unlucky enough to hit the blip on every single one of its 14
# attempts recorded no detection at all despite nginx having actually
# recovered - see docs/decisions.md.
check_active() {
  local attempt=1
  until multipass exec web -- systemctl is-active --quiet nginx; do
    (( attempt >= 3 )) && return 1
    attempt=$(( attempt + 1 ))
    sleep 3
  done
  return 0
}

for i in $(seq 1 14); do
  sleep 5
  if check_active; then
    echo "detected_active_again_after_seconds=$((i * 5))" >> "$OUT"
    break
  fi
done

mp_retry multipass exec web -- tail -n 15 /var/log/web_status.log >> "$OUT"

echo "--- logrotate -d (dry run) ---" >> "$OUT"
mp_retry multipass exec web -- sudo logrotate -d /etc/logrotate.d/capstone >> "$OUT" 2>&1

echo "--- logrotate -f (forced run) ---" >> "$OUT"
mp_retry multipass exec web -- sudo logrotate -f /etc/logrotate.d/capstone >> "$OUT" 2>&1
# Not mp_retry'd: a non-matching glob makes `ls` exit nonzero too, which
# isn't a connectivity problem retrying would fix. Also lists `*.log.1*`,
# not just `*.gz`: a single forced rotation under `delaycompress` (our
# config) produces an uncompressed `.1` file, never `.gz`, on its first
# rotation - see docs/decisions.md.
multipass exec web -- bash -c "ls -la /var/log/web_status.log* /var/log/nginx/*.log.1* 2>/dev/null" >> "$OUT" || true

echo "E8 raw output: $OUT"
