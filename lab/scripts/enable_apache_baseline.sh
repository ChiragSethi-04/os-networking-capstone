#!/usr/bin/env bash
# Purpose: enable/disable the Apache baseline on port 8080 for E1/E2/E3
# benchmark runs. Usage: enable_apache_baseline.sh {on|off}
set -euo pipefail
action="${1:?usage: enable_apache_baseline.sh on|off}"

if [[ "$action" == "on" ]]; then
  multipass exec web -- sudo systemctl start apache2
elif [[ "$action" == "off" ]]; then
  multipass exec web -- sudo systemctl stop apache2
else
  echo "usage: enable_apache_baseline.sh on|off" >&2
  exit 1
fi
