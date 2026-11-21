#!/usr/bin/env bash
# Shared helpers for experiments/run_E*.sh. Sourced, not executed directly.
# Each run_E*.sh parses its own --quick flag into $QUICK and $REPEATS before
# sourcing this (or after; this file only defines functions/paths).

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"
source lab/.env

# See docs/decisions.md: a multipass exec/transfer call can occasionally
# hit a short, self-clearing "ssh connection failed: Connection refused"
# window under host memory pressure, not a broken VM. Available to every
# experiment script via this shared file; retry rather than abort a run
# that may already be hours into repeated benchmark passes.
mp_retry() {
  local attempt=1 max=15
  until "$@"; do
    if (( attempt >= max )); then
      echo "mp_retry: giving up after $max attempts: $*" >&2
      return 1
    fi
    echo "mp_retry: attempt $attempt failed, retrying in 10s: $*" >&2
    attempt=$(( attempt + 1 ))
    sleep 10
  done
}

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
