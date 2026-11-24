#!/usr/bin/env bash
# E1: Apache vs Nginx static throughput/latency, concurrency 10/50/100/200,
# alternated (Apache, Nginx, Apache, Nginx, ...) to average out drift, each
# repeated REPEATS times after one warm-up run. CPU/mem sampled with pidstat
# during each run. Only the server under test is enabled at a time.
# Author: [GROUP MEMBER PLACEHOLDER]
# Date: [DATE PLACEHOLDER]
set -euo pipefail
QUICK=0; for a in "$@"; do [[ "$a" == "--quick" ]] && QUICK=1; done
REPEATS=5; [[ "$QUICK" -eq 1 ]] && REPEATS=2
source "$(dirname "$0")/common.sh"

mkdir -p evidence/raw
OUT="evidence/raw/E1_$(date +%Y%m%dT%H%M%S).txt"
raw_header "E1" > "$OUT"

# Port 80 normally 301-redirects everything to HTTPS (Phase 3 hardening),
# so benchmarking "nginx on port 80" against the real hardened config
# only ever measures the 301's own tiny response, not the real page -
# confirmed directly (a redirect run moved ~336 bytes/request; Apache's
# real-page run on 8080 moved ~1978 bytes/request for the same
# homepage). Swap in a temporary config that serves the real site on
# port 80 for this benchmark's duration, then swap the real hardened
# config straight back. See docs/decisions.md.
echo "--- temporarily serving the real site over plain HTTP for this benchmark ---" >> "$OUT"
mp_retry multipass transfer lab/configs/nginx/meridian-plainhttp.conf.template web:/tmp/meridian-plainhttp.conf
mp_retry multipass exec web -- sudo bash -c 'cp /etc/nginx/sites-available/meridian.conf /tmp/meridian.conf.e1-backup && mv /tmp/meridian-plainhttp.conf /etc/nginx/sites-available/meridian.conf && nginx -t && systemctl reload nginx'
restore_nginx() {
  mp_retry multipass exec web -- sudo bash -c 'mv /tmp/meridian.conf.e1-backup /etc/nginx/sites-available/meridian.conf && nginx -t && systemctl reload nginx'
}
trap restore_nginx EXIT

run_wrk() {
  local server="$1" port="$2" conc="$3" run="$4"
  echo "--- server=$server port=$port concurrency=$conc run=$run ---" >> "$OUT"
  mp_retry multipass exec web -- bash -c "nohup pidstat -u -r 1 5 > /tmp/pidstat_${server}_${conc}_${run}.txt 2>&1 &" || true
  mp_retry multipass exec attacker -- bash -c "wrk -t2 -c${conc} -d15s --latency http://${WEB_IP}:${port}/" >> "$OUT" 2>&1
  sleep 1
  mp_retry multipass exec web -- bash -c "cat /tmp/pidstat_${server}_${conc}_${run}.txt 2>/dev/null || true" >> "$OUT"
}

disable_apache
for conc in 10 50 100 200; do
  echo "== warm-up: nginx c=$conc ==" >> "$OUT"
  mp_retry multipass exec attacker -- bash -c "wrk -t2 -c${conc} -d5s http://${WEB_IP}/" >> "$OUT" 2>&1 || true
done

for conc in 10 50 100 200; do
  for run in $(seq 1 "$REPEATS"); do
    enable_apache
    run_wrk apache 8080 "$conc" "$run"
    disable_apache
    run_wrk nginx 80 "$conc" "$run"
  done
done

# Apache's E1 failed-request counts (Table 4.1) are explained by its
# configured worker/connection ceiling, not guessed at - capture the
# actual error log so Section 4.1 cites real evidence for why failures
# start appearing at higher concurrency.
echo "--- apache2 error log (last 80 lines, for the worker-capacity claim in Section 4.1) ---" >> "$OUT"
enable_apache
mp_retry multipass exec web -- sudo tail -n 80 /var/log/apache2/error.log >> "$OUT" 2>&1 || true
mp_retry multipass exec web -- bash -c "apache2ctl -V 2>&1 | grep -i mpm" >> "$OUT" 2>&1 || true
mp_retry multipass exec web -- bash -c "grep -rn 'MaxRequestWorkers\|ServerLimit\|MaxClients' /etc/apache2/ 2>/dev/null || echo '(no explicit override - package default MPM limits apply)'" >> "$OUT" 2>&1 || true
disable_apache

echo "E1 raw output: $OUT"
