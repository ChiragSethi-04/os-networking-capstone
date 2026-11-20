#!/usr/bin/env bash
# Purpose: remove the E5 demo-only accounts/paths and restore the real
# hardened SSH config (AllowUsers admin, PasswordAuthentication no).
# Author: [GROUP MEMBER PLACEHOLDER]
# Date: [DATE PLACEHOLDER]
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT_DIR"

echo "--- removing bftest user, restoring sshd hardening ---"
multipass exec web -- sudo bash -c '
  userdel -r bftest 2>/dev/null || true
  sed -i "s/^AllowUsers admin bftest$/AllowUsers admin/" /etc/ssh/sshd_config.d/99-capstone-hardening.conf
  sed -i "s/^PasswordAuthentication yes$/PasswordAuthentication no/" /etc/ssh/sshd_config.d/99-capstone-hardening.conf
  sshd -t
  systemctl restart ssh
'

echo "--- removing /admin-demo/ path ---"
multipass exec web -- sudo bash -c '
  python3 - <<"PYEOF"
import re
path = "/etc/nginx/sites-available/meridian.conf"
text = open(path).read()
text = re.sub(
    r"\n# --- E5 demo path.*?^}\n",
    "\n",
    text,
    flags=re.S | re.M,
)
open(path, "w").write(text)
PYEOF
  rm -f /etc/nginx/.htpasswd-demo
  rm -rf /var/www/html/admin-demo
  nginx -t && systemctl reload nginx
'

echo "--- verifying key-only SSH login still works ---"
source lab/.env
ssh -i lab/.secrets/capstone_id_ed25519 -o StrictHostKeyChecking=accept-new \
  -o ConnectTimeout=5 "admin@${WEB_IP}" "echo key login still ok"

echo "E5 demo accounts removed, hardened state restored."
