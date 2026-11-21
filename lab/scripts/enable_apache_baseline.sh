#!/usr/bin/env bash
# Purpose: enable/disable the Apache baseline on port 8080 for E1/E2/E3
# benchmark runs. Usage: enable_apache_baseline.sh {on|off}
set -euo pipefail
action="${1:?usage: enable_apache_baseline.sh on|off}"

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
elif [[ "$action" == "off" ]]; then
  mp_retry multipass exec web -- sudo systemctl stop apache2
else
  echo "usage: enable_apache_baseline.sh on|off" >&2
  exit 1
fi
