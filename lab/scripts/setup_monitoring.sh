#!/usr/bin/env bash
# Purpose: Phase 5 - deploy the monitoring script + timer, systemd
# Restart=on-failure drop-ins, logrotate config, and enable sysstat.
# Author: [GROUP MEMBER PLACEHOLDER]
# Date: [DATE PLACEHOLDER]
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT_DIR"

echo "--- monitor script + timer on web ---"
multipass transfer lab/configs/systemd/monitor_on_web.sh web:/tmp/web_status_monitor.sh
multipass transfer lab/configs/systemd/capstone-monitor.service web:/tmp/capstone-monitor.service
multipass transfer lab/configs/systemd/capstone-monitor.timer web:/tmp/capstone-monitor.timer
multipass exec web -- sudo bash -c '
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
multipass exec web -- sudo bash -c '
  mkdir -p /etc/systemd/system/nginx.service.d /etc/systemd/system/meridian-app.service.d
'
multipass transfer lab/configs/systemd/nginx-override.conf web:/tmp/nginx-override.conf
multipass exec web -- sudo bash -c '
  mv /tmp/nginx-override.conf /etc/systemd/system/nginx.service.d/override.conf
  cp /etc/systemd/system/nginx.service.d/override.conf /etc/systemd/system/meridian-app.service.d/override.conf
  systemctl daemon-reload
'

echo "--- logrotate ---"
multipass transfer lab/configs/logrotate/capstone web:/tmp/capstone
multipass exec web -- sudo bash -c '
  mv /tmp/capstone /etc/logrotate.d/capstone
  chmod 644 /etc/logrotate.d/capstone
'

echo "--- sysstat (web, db) ---"
for name in web db; do
  multipass exec "$name" -- sudo bash -c '
    apt-get install -y sysstat >/dev/null 2>&1 || true
    sed -i "s/ENABLED=\"false\"/ENABLED=\"true\"/" /etc/default/sysstat || true
    systemctl enable --now sysstat
  '
done

echo "Phase 5 monitoring setup complete."
