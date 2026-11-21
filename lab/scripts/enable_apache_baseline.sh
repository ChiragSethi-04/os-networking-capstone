#!/usr/bin/env bash
# Purpose: enable/disable the Apache baseline on port 8080 for E1/E2/E3
# benchmark runs. Usage: enable_apache_baseline.sh {on|off}
#
# Also opens/closes ufw for 8080, scoped to the attacker VM's IP only:
# the hardened state is exactly 3 open ports (22, 80, 443 - see Phase 4 /
# test_phase4.sh), so 8080 is never left open permanently. Without this,
# wrk from attacker got "Connection timed out" against 8080 even though
# Apache itself was running and reachable from web's own loopback - ufw's
# default-deny silently drops rather than rejects, which looks identical
# to a hung connection from the client's side. See docs/decisions.md.
set -euo pipefail
action="${1:?usage: enable_apache_baseline.sh on|off}"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$ROOT_DIR/lab/.env"

# Called many times per E1 run (every concurrency x repeat toggles this);
# see docs/decisions.md on the short, self-clearing SSH blip under host
# memory pressure that makes retrying worthwhile here.
mp_retry() {
  local attempt=1 max=15
  until "$@"; do
    (( attempt >= max )) && return 1
    attempt=$(( attempt + 1 ))
    sleep 10
  done
}

if [[ "$action" == "on" ]]; then
  mp_retry multipass exec web -- sudo systemctl start apache2
  mp_retry multipass exec web -- sudo ufw allow from "${ATT_IP}" to any port 8080 proto tcp comment 'benchmark only, attacker VM'
elif [[ "$action" == "off" ]]; then
  mp_retry multipass exec web -- sudo systemctl stop apache2
  # Not mp_retry'd: this is called once before any "on" ever ran (a
  # clean-state reset at the top of run_E1.sh), when the rule does not
  # exist yet, so "ufw delete" failing here is an expected no-op, not a
  # connectivity problem worth spending mp_retry's whole budget on.
  multipass exec web -- sudo ufw delete allow from "${ATT_IP}" to any port 8080 proto tcp 2>&1 | cat >/dev/null || true
else
  echo "usage: enable_apache_baseline.sh on|off" >&2
  exit 1
fi
