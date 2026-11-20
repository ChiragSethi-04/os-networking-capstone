#!/usr/bin/env bash
# Purpose: capture the required terminal evidence (ufw, fail2ban, ss, htop,
# monitor log) as raw text, then render each as a clean monospace PNG via
# figures/render_terminal_evidence.py. Run after Phase 4/5 are both up.
# Author: [GROUP MEMBER PLACEHOLDER]
# Date: [DATE PLACEHOLDER]
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT_DIR"
source lab/.env
mkdir -p evidence/raw evidence/screenshots
VENV_PY=".venv/bin/python3"
[[ -x "$VENV_PY" ]] || VENV_PY="python3"

capture() {
  local name="$1" title="$2"; shift 2
  "$@" > "evidence/raw/${name}.txt" 2>&1 || true
  "$VENV_PY" figures/render_terminal_evidence.py "evidence/raw/${name}.txt" \
    "evidence/screenshots/${name}.png" "$title"
}

capture ufw_status_web   "ufw status verbose (web)"   multipass exec web -- sudo ufw status verbose
capture ufw_status_db    "ufw status verbose (db)"    multipass exec db  -- sudo ufw status verbose
capture fail2ban_status  "fail2ban-client status"     multipass exec web -- sudo fail2ban-client status
capture ss_web           "ss -tulpn (web)"             multipass exec web -- sudo ss -tulpn
capture ss_db            "ss -tulpn (db)"              multipass exec db  -- sudo ss -tulpn
capture monitor_log      "web_status.log (tail)"       multipass exec web -- tail -n 30 /var/log/web_status.log

echo "--- htop: capture requires an interactive terminal, so this records a ---"
echo "--- one-shot 'top -b -n1' equivalent (busybox-free Ubuntu: use top -b) ---"
capture top_web "top -b -n1 (web, during load)" multipass exec web -- bash -c "top -b -n1 | head -20"

echo "Rendered terminal evidence PNGs are in evidence/screenshots/."
echo "Browser screenshots (padlock, cert, warning page, 403, 429) are taken"
echo "separately with Claude in Chrome per lab/scripts/README_browser_evidence.md."
