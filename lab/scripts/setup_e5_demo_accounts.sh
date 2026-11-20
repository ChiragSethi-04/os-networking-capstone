#!/usr/bin/env bash
# Purpose: set up throwaway, deliberately-weak-password targets for the E5
# brute-force demo, kept entirely separate from the real admin credentials
# (ADMIN_BASIC_AUTH_PASSWORD, the meridian_app DB password). This is why:
# the real admin password is a random 24-character string, which a small
# self-made wordlist could never guess in a reasonable demo, so it cannot
# show what happens when a weak password IS guessed before Fail2Ban reacts.
# A dedicated bftest SSH user and a dedicated /admin-demo/ Nginx path, both
# using lab/.secrets/secrets.env's DEMO_WEAK_PASSWORD (also present in
# lab/wordlist.txt), let E5 demonstrate the full story: successful guess
# before protection, and a ban before guessing succeeds after protection.
# Removed again by lab/scripts/teardown_e5_demo_accounts.sh.
# Author: [GROUP MEMBER PLACEHOLDER]
# Date: [DATE PLACEHOLDER]
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT_DIR"
source lab/.secrets/secrets.env

echo "--- creating bftest SSH user on web (password auth, demo only) ---"
multipass exec web -- sudo bash -c "
  id -u bftest >/dev/null 2>&1 || useradd -m -s /bin/bash bftest
  echo 'bftest:${DEMO_WEAK_PASSWORD}' | chpasswd
"
multipass exec web -- sudo bash -c '
  sed -i "s/^AllowUsers admin$/AllowUsers admin bftest/" /etc/ssh/sshd_config.d/99-capstone-hardening.conf
  sed -i "s/^PasswordAuthentication no$/PasswordAuthentication yes/" /etc/ssh/sshd_config.d/99-capstone-hardening.conf
  sshd -t
  systemctl restart ssh
'

echo "--- creating /admin-demo/ Nginx path with weak htpasswd (demo only) ---"
multipass exec web -- sudo mkdir -p /var/www/html/admin-demo
multipass exec web -- bash -c "echo '<h1>demo</h1>' | sudo tee /var/www/html/admin-demo/index.html >/dev/null"
multipass exec web -- bash -c "echo '${DEMO_WEAK_PASSWORD}' | sudo tee /tmp/demopw >/dev/null"
multipass exec web -- sudo bash -c '
  htpasswd -b -c /etc/nginx/.htpasswd-demo admin "$(cat /tmp/demopw)"
  rm -f /tmp/demopw
'
multipass exec web -- sudo bash -c "cat >> /etc/nginx/sites-available/meridian.conf <<'EOF'
# --- E5 demo path, added by setup_e5_demo_accounts.sh, removed by teardown ---
server {
    listen 443 ssl;
    server_name web;
    ssl_certificate     /etc/ssl/certs/web.crt;
    ssl_certificate_key /etc/ssl/private/web.key;
    location = /admin-demo/ {
        auth_basic \"Demo\";
        auth_basic_user_file /etc/nginx/.htpasswd-demo;
        root /var/www/html;
    }
}
EOF"
multipass exec web -- sudo bash -c 'nginx -t && systemctl reload nginx'

echo "E5 demo accounts ready. Run experiments/run_E5.sh next, then teardown_e5_demo_accounts.sh."
