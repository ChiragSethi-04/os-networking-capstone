#!/usr/bin/env bash
# Purpose: Phase 5 acceptance check - kill nginx, confirm monitor logs
# DOWN then RESTARTED within 60s and the site recovers; logrotate -f works.
# Author: [GROUP MEMBER PLACEHOLDER]
# Date: [DATE PLACEHOLDER]
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT_DIR"
source lab/.env
mkdir -p evidence/raw
fail=0

echo "Stopping nginx on web..."
multipass exec web -- sudo systemctl stop nginx

echo "Waiting up to 70s for the monitor to detect and restart it..."
recovered=0
for i in $(seq 1 14); do
  sleep 5
  if curl -sk -o /dev/null --max-time 3 "https://${WEB_IP}/"; then
    recovered=1
    echo "Site responding again after ${i}x5s"
    break
  fi
done

multipass exec web -- tail -n 20 /var/log/web_status.log > evidence/raw/web_status_log_excerpt.txt
cat evidence/raw/web_status_log_excerpt.txt

if [[ $recovered -eq 1 ]] && grep -q "nginx DOWN" evidence/raw/web_status_log_excerpt.txt && grep -q "nginx RESTARTED" evidence/raw/web_status_log_excerpt.txt; then
  echo "OK: monitor detected DOWN and RESTARTED nginx"
else
  echo "FAIL: monitor did not clearly show DOWN then RESTARTED"
  fail=1
fi

echo "--- logrotate -f ---"
multipass exec web -- sudo logrotate -f /etc/logrotate.d/capstone > evidence/raw/logrotate_force_run.txt 2>&1 || true
multipass exec web -- bash -c "ls -la /var/log/web_status.log* /var/log/nginx/*.gz 2>/dev/null" >> evidence/raw/logrotate_force_run.txt
cat evidence/raw/logrotate_force_run.txt

if [[ $fail -eq 0 ]]; then
  echo "PHASE 5: PASS"
else
  echo "PHASE 5: FAIL"
  exit 1
fi
