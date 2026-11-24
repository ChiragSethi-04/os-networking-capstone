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

# The WITH-limit_req flood below deliberately exceeds the rate limit by
# design - that's the point of the experiment. Now that the nginx-limit-req
# Fail2Ban jail's backend bug is fixed (see docs/decisions.md), this
# legitimately looks like a real attack to Fail2Ban, which bans the
# attacker VM's own IP on ports 80/443 within the first second or so of
# the 20s flood: wrk's remaining 200 connections then hang against a
# silent ufw DROP for the rest of the window ("0 requests" completed) and
# the status-code sample right after gets 504s (a handful of requests get
# through before the ban lands and queue up a backend backlog that takes
# a moment to drain), not the clean 429/200 mix this experiment needs.
# `ignoreip` is Fail2Ban's own mechanism for "this source is not an
# attacker, never ban it" - exactly our own benchmark traffic's situation
# - so the attacker's IP is temporarily whitelisted for this one jail
# around the deliberate flood, then removed again immediately after. This
# does not hide or weaken the finding: `nginx-limit-req` banning a real,
# unlisted attacker mid-flood was independently confirmed working by hand
# before this script was patched (see docs/decisions.md), and the jail is
# fully active again for every other experiment and for the live demo.
mp_retry multipass exec web -- sudo fail2ban-client set nginx-limit-req addignoreip "${ATT_IP}"

echo "--- WITH limit_req (current hardened config) ---" >> "$OUT"
mp_retry multipass exec web -- bash -c "nohup pidstat -u 1 5 > /tmp/pidstat_e6_with.txt 2>&1 &" || true
mp_retry multipass exec attacker -- bash -c "wrk -t4 -c200 -d20s https://${WEB_IP}/api/health" >> "$OUT" 2>&1
mp_retry multipass exec web -- cat /tmp/pidstat_e6_with.txt >> "$OUT"

echo "--- status code mix (sampled requests, limit_req active) ---" >> "$OUT"
mp_retry multipass exec attacker -- bash -c "for i in \$(seq 1 60); do curl -sk -o /dev/null -w '%{http_code}\n' https://${WEB_IP}/api/health & done; wait" >> "$OUT" 2>&1

# The flood above writes tens of thousands of matching log lines in a few
# seconds; Fail2Ban's file-polling backend processes its backlog with a
# lag, not instantly. Removing the ignoreip entry right away was found
# (by direct testing) to race that backlog: Fail2Ban was still catching up
# on log lines written *while* the IP was ignored, but by the time it
# actually evaluated them the entry was already gone, so it banned the
# attacker anyway for violations that happened during the whitelisted
# window. Giving the poller time to fully drain first avoids this.
sleep 15
mp_retry multipass exec web -- sudo fail2ban-client set nginx-limit-req delignoreip "${ATT_IP}"

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
mp_retry multipass exec web -- sudo fail2ban-client set nginx-limit-req unbanip "${ATT_IP}" || true

echo "E6 raw output: $OUT"
