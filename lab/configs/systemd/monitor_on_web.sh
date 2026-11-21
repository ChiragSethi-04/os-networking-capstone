#!/usr/bin/env bash
# Deployed to /usr/local/bin/web_status_monitor.sh on the web VM, run every
# 30 seconds by capstone-monitor.timer. Checks nginx, the Flask app via
# gunicorn, TLS certificate expiry, disk, load, /api/health, and DB
# reachability. Logs one timestamped line per run to /var/log/web_status.log
# and restarts a service it finds down, logging that action too.
set -uo pipefail

LOG=/var/log/web_status.log
TS=$(date -u +%FT%TZ)

log() { echo "$TS $*" >> "$LOG"; }

check_and_restart() {
  local unit="$1"
  if systemctl is-active --quiet "$unit"; then
    log "$unit UP"
  else
    log "$unit DOWN"
    systemctl restart "$unit"
    sleep 2
    if systemctl is-active --quiet "$unit"; then
      log "$unit RESTARTED"
    else
      log "$unit RESTART_FAILED"
    fi
  fi
}

check_and_restart nginx
check_and_restart meridian-app

CERT=/etc/ssl/certs/web.crt
if [[ -f "$CERT" ]]; then
  EXP_EPOCH=$(openssl x509 -enddate -noout -in "$CERT" | cut -d= -f2 | xargs -I{} date -d {} +%s 2>/dev/null || echo 0)
  NOW_EPOCH=$(date +%s)
  DAYS_LEFT=$(( (EXP_EPOCH - NOW_EPOCH) / 86400 ))
  log "cert_days_left=$DAYS_LEFT"
fi

DISK_PCT=$(df -h / | awk 'NR==2 {print $5}')
LOAD=$(cut -d' ' -f1-3 /proc/loadavg)
log "disk_used=$DISK_PCT load=$LOAD"

HTTP_CODE=$(curl -sk -o /dev/null -w "%{http_code}" https://127.0.0.1/api/health || echo 000)
log "api_health_http=$HTTP_CODE"

if mysqladmin ping -h db --connect-timeout=3 --skip-ssl >/dev/null 2>&1; then
  log "db_reachable=yes"
else
  log "db_reachable=no"
fi
