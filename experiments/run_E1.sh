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

run_wrk() {
  local server="$1" port="$2" conc="$3" run="$4"
  echo "--- server=$server port=$port concurrency=$conc run=$run ---" >> "$OUT"
  multipass exec web -- bash -c "nohup pidstat -u -r 1 5 > /tmp/pidstat_${server}_${conc}_${run}.txt 2>&1 &" || true
  multipass exec attacker -- bash -c "wrk -t2 -c${conc} -d15s --latency http://${WEB_IP}:${port}/" >> "$OUT" 2>&1
  sleep 1
  multipass exec web -- bash -c "cat /tmp/pidstat_${server}_${conc}_${run}.txt 2>/dev/null || true" >> "$OUT"
}

disable_apache
for conc in 10 50 100 200; do
  echo "== warm-up: nginx c=$conc ==" >> "$OUT"
  multipass exec attacker -- bash -c "wrk -t2 -c${conc} -d5s http://${WEB_IP}/" >> "$OUT" 2>&1 || true
done

for conc in 10 50 100 200; do
  for run in $(seq 1 "$REPEATS"); do
    enable_apache
    run_wrk apache 8080 "$conc" "$run"
    disable_apache
    run_wrk nginx 80 "$conc" "$run"
  done
done

echo "E1 raw output: $OUT"
