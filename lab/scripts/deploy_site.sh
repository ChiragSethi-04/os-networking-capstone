#!/usr/bin/env bash
# Purpose: Phase 2 - deploy the website, Flask app, Nginx, Apache (stopped),
# and MariaDB schema/user onto the web and db VMs. Configs in lab/configs/
# are the source of truth; nothing is hand-edited inside a VM.
# Author: [GROUP MEMBER PLACEHOLDER]
# Date: [DATE PLACEHOLDER]
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT_DIR"
source lab/.env
source lab/.secrets/secrets.env
SSH_KEY="lab/.secrets/capstone_id_ed25519"
SSH="ssh -i $SSH_KEY -o StrictHostKeyChecking=accept-new -o ConnectTimeout=5"

echo "=== db VM: schema + least-privilege user ==="
multipass transfer lab/configs/mariadb/schema.sql db:/tmp/schema.sql
sed -e "s/WEB_IP/${WEB_IP}/" -e "s/APP_DB_PASSWORD/${APP_DB_PASSWORD}/" \
  lab/configs/mariadb/create_user.sql.template > /tmp/create_user.sql
multipass transfer /tmp/create_user.sql db:/tmp/create_user.sql
rm -f /tmp/create_user.sql

sed "s/DB_IP/${DB_IP}/" lab/configs/mariadb/bind-address.cnf.template > /tmp/60-capstone-bind.cnf
multipass transfer /tmp/60-capstone-bind.cnf db:/tmp/60-capstone-bind.cnf
rm -f /tmp/60-capstone-bind.cnf

multipass exec db -- sudo bash -c '
  set -e
  mysql < /tmp/schema.sql
  mysql < /tmp/create_user.sql
  rm -f /tmp/schema.sql /tmp/create_user.sql
  cp /tmp/60-capstone-bind.cnf /etc/mysql/mariadb.conf.d/60-capstone-bind.cnf
  rm -f /tmp/60-capstone-bind.cnf
  systemctl restart mariadb
  systemctl enable mariadb
'
echo "db VM: schema and user deployed."

echo "=== web VM: static site ==="
multipass exec web -- sudo mkdir -p /var/www/html/css /var/www/html/js
for f in index.html about.html services.html contact.html; do
  multipass transfer "site/$f" "web:/tmp/$f"
  multipass exec web -- sudo mv "/tmp/$f" "/var/www/html/$f"
done
multipass transfer site/css/styles.css web:/tmp/styles.css
multipass exec web -- sudo mv /tmp/styles.css /var/www/html/css/styles.css
multipass transfer site/js/script.js web:/tmp/script.js
multipass exec web -- sudo mv /tmp/script.js /var/www/html/js/script.js
multipass exec web -- sudo bash -c '
  chown -R root:www-data /var/www/html
  find /var/www/html -type d -exec chmod 755 {} \;
  find /var/www/html -type f -exec chmod 644 {} \;
'
echo "web VM: static site deployed (644 files, 755 dirs, root:www-data)."

echo "=== web VM: Flask app under gunicorn ==="
multipass exec web -- sudo mkdir -p /var/www/meridian-app
multipass transfer site/app/app.py web:/tmp/app.py
multipass transfer site/app/requirements.txt web:/tmp/requirements.txt
multipass exec web -- sudo bash -c '
  set -e
  mv /tmp/app.py /var/www/meridian-app/app.py
  mv /tmp/requirements.txt /var/www/meridian-app/requirements.txt
  python3 -m venv /var/www/meridian-app/venv
  /var/www/meridian-app/venv/bin/pip install -q --upgrade pip
  /var/www/meridian-app/venv/bin/pip install -q -r /var/www/meridian-app/requirements.txt
  chown -R www-data:www-data /var/www/meridian-app
'

cat > /tmp/meridian-app.env <<EOF
MERIDIAN_DB_HOST=db
MERIDIAN_DB_USER=meridian_app
MERIDIAN_DB_PASSWORD=${APP_DB_PASSWORD}
MERIDIAN_DB_NAME=meridian
EOF
multipass transfer /tmp/meridian-app.env web:/tmp/meridian-app.env
rm -f /tmp/meridian-app.env
multipass exec web -- sudo bash -c '
  mv /tmp/meridian-app.env /etc/meridian-app.env
  chmod 600 /etc/meridian-app.env
  chown www-data:www-data /etc/meridian-app.env
'
multipass transfer lab/configs/systemd/meridian-app.service web:/tmp/meridian-app.service
multipass exec web -- sudo bash -c '
  mv /tmp/meridian-app.service /etc/systemd/system/meridian-app.service
  systemctl daemon-reload
  systemctl enable --now meridian-app
'
echo "web VM: Flask app running under gunicorn as meridian-app.service."

echo "=== web VM: Nginx ==="
multipass transfer lab/configs/nginx/meridian.conf.template web:/tmp/meridian.conf
multipass exec web -- sudo bash -c '
  set -e
  rm -f /etc/nginx/sites-enabled/default
  mv /tmp/meridian.conf /etc/nginx/sites-available/meridian.conf
  ln -sf /etc/nginx/sites-available/meridian.conf /etc/nginx/sites-enabled/meridian.conf
  nginx -t
  systemctl restart nginx
  systemctl enable nginx
'

echo "=== web VM: admin basic-auth htpasswd ==="
multipass exec web -- bash -c "echo '${ADMIN_BASIC_AUTH_PASSWORD}' | sudo tee /tmp/pw >/dev/null"
multipass exec web -- sudo bash -c '
  apt-get install -y apache2-utils >/dev/null 2>&1 || true
  htpasswd -b -c /etc/nginx/.htpasswd admin "$(cat /tmp/pw)"
  rm -f /tmp/pw
  chown root:www-data /etc/nginx/.htpasswd
  chmod 640 /etc/nginx/.htpasswd
'
echo "web VM: Nginx deployed, admin basic auth set."

echo "=== web VM: Apache baseline on 8080 (installed, kept stopped) ==="
multipass transfer lab/configs/apache/meridian-8080.conf web:/tmp/meridian-8080.conf
multipass transfer lab/configs/apache/security-capstone.conf web:/tmp/security-capstone.conf
multipass exec web -- sudo bash -c '
  set -e
  mv /tmp/meridian-8080.conf /etc/apache2/sites-available/meridian-8080.conf
  mv /tmp/security-capstone.conf /etc/apache2/conf-available/security-capstone.conf
  # The default site listens on port 80 via ports.confs own "Listen 80",
  # which Apache tries to bind regardless of which sites are enabled and
  # collides with Nginx already owning 80; disable both the default site
  # and the global Listen 80 so only our own "Listen 8080" (in
  # meridian-8080.conf) applies.
  a2dissite 000-default.conf || true
  sed -i "/^Listen 80$/d" /etc/apache2/ports.conf
  a2ensite meridian-8080.conf
  a2enconf security-capstone
  apache2ctl configtest
  systemctl stop apache2
  systemctl disable apache2
'
echo "Apache baseline installed and disabled by default. Enable with:"
echo "  multipass exec web -- sudo systemctl start apache2"

echo "Phase 2 deploy complete."
