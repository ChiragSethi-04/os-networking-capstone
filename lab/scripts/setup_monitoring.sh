#!/usr/bin/env bash
# Purpose: Phase 5 - deploy the monitoring script + timer, systemd
# Restart=on-failure drop-ins, logrotate config, and enable sysstat.
# Author: [GROUP MEMBER PLACEHOLDER]
# Date: [DATE PLACEHOLDER]
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT_DIR"

# See docs/decisions.md: a multipass exec/transfer call can occasionally
# hit a short (10-30s), self-clearing "ssh connection failed: Connection
# refused" window, most often shortly after another phase's heavy VM
# activity. Retrying beats aborting the whole script under `set -e`.
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

echo "--- monitor script + timer on web ---"
mp_retry multipass transfer lab/configs/systemd/monitor_on_web.sh web:/tmp/web_status_monitor.sh
mp_retry multipass transfer lab/configs/systemd/capstone-monitor.service web:/tmp/capstone-monitor.service
mp_retry multipass transfer lab/configs/systemd/capstone-monitor.timer web:/tmp/capstone-monitor.timer
mp_retry multipass exec web -- sudo bash -c '
  set -e
  mv /tmp/web_status_monitor.sh /usr/local/bin/web_status_monitor.sh
  chmod +x /usr/local/bin/web_status_monitor.sh
  mv /tmp/capstone-monitor.service /etc/systemd/system/capstone-monitor.service
  mv /tmp/capstone-monitor.timer /etc/systemd/system/capstone-monitor.timer
  touch /var/log/web_status.log
  systemctl daemon-reload
  systemctl enable --now capstone-monitor.timer
'

echo "--- Restart=on-failure drop-ins for nginx and meridian-app ---"
mp_retry multipass exec web -- sudo bash -c '
  mkdir -p /etc/systemd/system/nginx.service.d /etc/systemd/system/meridian-app.service.d
'
mp_retry multipass transfer lab/configs/systemd/nginx-override.conf web:/tmp/nginx-override.conf
mp_retry multipass exec web -- sudo bash -c '
  mv /tmp/nginx-override.conf /etc/systemd/system/nginx.service.d/override.conf
  cp /etc/systemd/system/nginx.service.d/override.conf /etc/systemd/system/meridian-app.service.d/override.conf
  systemctl daemon-reload
'

echo "--- logrotate ---"
mp_retry multipass transfer lab/configs/logrotate/capstone web:/tmp/capstone
mp_retry multipass exec web -- sudo bash -c '
  mv /tmp/capstone /etc/logrotate.d/capstone
  chmod 644 /etc/logrotate.d/capstone
'

echo "--- sysstat (web, db) ---"
for name in web db; do
  mp_retry multipass exec "$name" -- sudo bash -c '
    apt-get install -y sysstat >/dev/null 2>&1 || true
    sed -i "s/ENABLED=\"false\"/ENABLED=\"true\"/" /etc/default/sysstat || true
    systemctl enable --now sysstat
  '
done

echo "Phase 5 monitoring setup complete."
