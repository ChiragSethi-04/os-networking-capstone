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
mp_retry multipass exec web -- bash -c "nohup pidstat -u 1 5 > /tmp/pidstat_e6_with.txt 2>&1 &" || true
mp_retry multipass exec attacker -- bash -c "wrk -t4 -c200 -d20s https://${WEB_IP}/api/health" >> "$OUT" 2>&1
mp_retry multipass exec web -- cat /tmp/pidstat_e6_with.txt >> "$OUT"

echo "--- status code mix (sampled requests, limit_req active) ---" >> "$OUT"
mp_retry multipass exec attacker -- bash -c "for i in \$(seq 1 60); do curl -sk -o /dev/null -w '%{http_code}\n' https://${WEB_IP}/api/health & done; wait" >> "$OUT" 2>&1

# Also disables `limit_conn` (a separate directive on the same location,
# capping concurrent connections per source IP regardless of request
# rate): leaving it active while only `limit_req` was toggled meant BOTH
# scenarios hit the same connection cap under wrk's 200 concurrent
# connections from one source IP, surfacing as 503s in both runs with
# zero 429s either way - not the clean "no limiting at all" baseline this
# comparison needs. See docs/decisions.md.
echo "--- temporarily disabling limit_req and limit_conn for comparison ---" >> "$OUT"
mp_retry multipass exec web -- sudo bash -c "sed -i 's/limit_req zone=api_zone burst=10 nodelay;/# limit_req DISABLED for E6 comparison/; s/limit_conn conn_zone 20;/# limit_conn DISABLED for E6 comparison/' /etc/nginx/sites-available/meridian.conf && nginx -t && systemctl reload nginx"

echo "--- WITHOUT limit_req ---" >> "$OUT"
mp_retry multipass exec web -- bash -c "nohup pidstat -u 1 5 > /tmp/pidstat_e6_without.txt 2>&1 &" || true
mp_retry multipass exec attacker -- bash -c "wrk -t4 -c200 -d20s https://${WEB_IP}/api/health" >> "$OUT" 2>&1
mp_retry multipass exec web -- cat /tmp/pidstat_e6_without.txt >> "$OUT"

echo "--- status code mix (sampled requests, limit_req disabled) ---" >> "$OUT"
mp_retry multipass exec attacker -- bash -c "for i in \$(seq 1 60); do curl -sk -o /dev/null -w '%{http_code}\n' https://${WEB_IP}/api/health & done; wait" >> "$OUT" 2>&1

echo "--- restoring limit_req and limit_conn ---" >> "$OUT"
mp_retry multipass exec web -- sudo bash -c "sed -i 's/# limit_req DISABLED for E6 comparison/limit_req zone=api_zone burst=10 nodelay;/; s/# limit_conn DISABLED for E6 comparison/limit_conn conn_zone 20;/' /etc/nginx/sites-available/meridian.conf && nginx -t && systemctl reload nginx"

echo "E6 raw output: $OUT"
