#!/usr/bin/env bash
# E6: rate limiting and flood - high-rate requests to /api/health with and
# without Nginx limit_req. Metrics: status code mix (200 vs 429/503), CPU.
# Author: [GROUP MEMBER PLACEHOLDER]
# Date: [DATE PLACEHOLDER]
set -euo pipefail
source "$(dirname "$0")/common.sh"

mkdir -p evidence/raw
OUT="evidence/raw/E6_$(date +%Y%m%dT%H%M%S).txt"
raw_header "E6" > "$OUT"

echo "--- WITH limit_req (current hardened config) ---" >> "$OUT"
multipass exec web -- bash -c "nohup pidstat -u 1 5 > /tmp/pidstat_e6_with.txt 2>&1 &" || true
multipass exec attacker -- bash -c "wrk -t4 -c200 -d20s https://${WEB_IP}/api/health" >> "$OUT" 2>&1
multipass exec web -- cat /tmp/pidstat_e6_with.txt >> "$OUT"

echo "--- status code mix (sampled requests, limit_req active) ---" >> "$OUT"
multipass exec attacker -- bash -c "for i in \$(seq 1 60); do curl -sk -o /dev/null -w '%{http_code}\n' https://${WEB_IP}/api/health & done; wait" >> "$OUT" 2>&1

echo "--- temporarily disabling limit_req for comparison ---" >> "$OUT"
multipass exec web -- sudo bash -c "sed -i 's/limit_req zone=api_zone burst=10 nodelay;/# limit_req DISABLED for E6 comparison/' /etc/nginx/sites-available/meridian.conf && nginx -t && systemctl reload nginx"

echo "--- WITHOUT limit_req ---" >> "$OUT"
multipass exec web -- bash -c "nohup pidstat -u 1 5 > /tmp/pidstat_e6_without.txt 2>&1 &" || true
multipass exec attacker -- bash -c "wrk -t4 -c200 -d20s https://${WEB_IP}/api/health" >> "$OUT" 2>&1
multipass exec web -- cat /tmp/pidstat_e6_without.txt >> "$OUT"

echo "--- status code mix (sampled requests, limit_req disabled) ---" >> "$OUT"
multipass exec attacker -- bash -c "for i in \$(seq 1 60); do curl -sk -o /dev/null -w '%{http_code}\n' https://${WEB_IP}/api/health & done; wait" >> "$OUT" 2>&1

echo "--- restoring limit_req ---" >> "$OUT"
multipass exec web -- sudo bash -c "sed -i 's/# limit_req DISABLED for E6 comparison/limit_req zone=api_zone burst=10 nodelay;/' /etc/nginx/sites-available/meridian.conf && nginx -t && systemctl reload nginx"

echo "E6 raw output: $OUT"
