#!/usr/bin/env bash
# Shared helpers for experiments/run_E*.sh. Sourced, not executed directly.
# Each run_E*.sh parses its own --quick flag into $QUICK and $REPEATS before
# sourcing this (or after; this file only defines functions/paths).

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"
source lab/.env

raw_header() {
  echo "=== $1 raw output ==="
  echo "date_utc=$(date -u +%FT%TZ)"
  echo "repeats=${REPEATS:-5} quick=${QUICK:-0}"
  multipass exec web -- bash -c 'echo web_cpus=$(nproc); echo web_mem=$(free -h | awk "/Mem/{print \$2}")'
  multipass exec attacker -- bash -c 'wrk --version 2>&1 | head -1' | sed 's/^/attacker_/'
  multipass exec web -- bash -c 'nginx -v 2>&1' | sed 's/^/web_/'
  multipass exec web -- bash -c 'apache2 -v 2>&1 | head -1' | sed 's/^/web_/'
}

enable_apache() { bash lab/scripts/enable_apache_baseline.sh on; sleep 1; }
disable_apache() { bash lab/scripts/enable_apache_baseline.sh off; }
