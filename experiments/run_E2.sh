#!/usr/bin/env bash
# E2: transport cost - HTTP vs HTTPS, TLS 1.2 vs 1.3, keep-alive on/off.
# Author: [GROUP MEMBER PLACEHOLDER]
# Date: [DATE PLACEHOLDER]
set -euo pipefail
QUICK=0; for a in "$@"; do [[ "$a" == "--quick" ]] && QUICK=1; done
REPEATS=5; [[ "$QUICK" -eq 1 ]] && REPEATS=2
source "$(dirname "$0")/common.sh"

mkdir -p evidence/raw
OUT="evidence/raw/E2_$(date +%Y%m%dT%H%M%S).txt"
raw_header "E2" > "$OUT"

# Same issue as E1 (see docs/decisions.md): port 80 normally 301-redirects
# to HTTPS, so "mode=http" against the real hardened config would only
# ever measure the redirect's own tiny response, not the real page -
# which would also make the HTTP-vs-HTTPS "transport cost" comparison
# below meaningless (comparing a redirect's cost against the real page's
# TLS cost, not TLS's actual cost on the same content). Swap in the real
# site on port 80 for this one mode, then swap back immediately.
echo "--- temporarily serving the real site over plain HTTP for mode=http ---" >> "$OUT"
mp_retry multipass transfer lab/configs/nginx/meridian-plainhttp.conf.template web:/tmp/meridian-plainhttp.conf
mp_retry multipass exec web -- sudo bash -c 'cp /etc/nginx/sites-available/meridian.conf /tmp/meridian.conf.e2-backup && mv /tmp/meridian-plainhttp.conf /etc/nginx/sites-available/meridian.conf && nginx -t && systemctl reload nginx'

for run in $(seq 1 "$REPEATS"); do
  echo "--- run=$run mode=http ---" >> "$OUT"
  mp_retry multipass exec attacker -- bash -c "wrk -t2 -c50 -d15s --latency http://${WEB_IP}/" >> "$OUT" 2>&1
done

echo "--- restoring the real hardened config (301 redirect) ---" >> "$OUT"
mp_retry multipass exec web -- sudo bash -c 'mv /tmp/meridian.conf.e2-backup /etc/nginx/sites-available/meridian.conf && nginx -t && systemctl reload nginx'

for run in $(seq 1 "$REPEATS"); do
  echo "--- run=$run mode=https ---" >> "$OUT"
  mp_retry multipass exec attacker -- bash -c "wrk -t2 -c50 -d15s --latency https://${WEB_IP}/" >> "$OUT" 2>&1

  echo "--- run=$run curl handshake timing tls1.2 ---" >> "$OUT"
  mp_retry multipass exec attacker -- bash -c "curl -sk -o /dev/null -w 'connect=%{time_connect} tls=%{time_appconnect} total=%{time_total}\n' --tlsv1.2 --tls-max 1.2 https://${WEB_IP}/" >> "$OUT" 2>&1

  echo "--- run=$run curl handshake timing tls1.3 ---" >> "$OUT"
  mp_retry multipass exec attacker -- bash -c "curl -sk -o /dev/null -w 'connect=%{time_connect} tls=%{time_appconnect} total=%{time_total}\n' --tlsv1.3 https://${WEB_IP}/" >> "$OUT" 2>&1

  echo "--- run=$run openssl s_time tls1.3 (20s) ---" >> "$OUT"
  mp_retry multipass exec attacker -- bash -c "openssl s_time -connect ${WEB_IP}:443 -new -time 20 -tls1_3" >> "$OUT" 2>&1

  echo "--- run=$run wrk keep-alive off (H: Connection: close) ---" >> "$OUT"
  mp_retry multipass exec attacker -- bash -c "wrk -t2 -c50 -d15s -H 'Connection: close' --latency https://${WEB_IP}/" >> "$OUT" 2>&1
done

echo "E2 raw output: $OUT"
