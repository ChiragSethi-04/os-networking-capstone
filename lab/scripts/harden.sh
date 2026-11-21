#!/usr/bin/env bash
# Purpose: Phase 3 (TLS) and Phase 4 (security hardening) on the web and db
# VMs. Configs in lab/configs/ are the source of truth.
# Author: [GROUP MEMBER PLACEHOLDER]
# Date: [DATE PLACEHOLDER]
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT_DIR"
source lab/.env
mkdir -p evidence/raw lab/.secrets/ca

#######################################
# Phase 3: local CA + server certificate, TLS
#######################################
echo "=== Phase 3: building local CA and server certificate ==="

CA_DIR="lab/.secrets/ca"
if [[ ! -f "$CA_DIR/ca.key" ]]; then
  openssl ecparam -name prime256v1 -genkey -noout -out "$CA_DIR/ca.key"
  openssl req -x509 -new -key "$CA_DIR/ca.key" -sha256 -days 365 \
    -subj "/C=IN/O=Capstone Group 6/CN=Capstone Lab Root CA" \
    -out "$CA_DIR/ca.crt"
  echo "Generated local root CA at $CA_DIR/ca.crt"
fi

cat > /tmp/web_san.cnf <<EOF
[req]
distinguished_name = dn
req_extensions = v3_req
prompt = no
[dn]
C = IN
O = Meridian Logistics
CN = web
[v3_req]
subjectAltName = @alt_names
[alt_names]
DNS.1 = web
DNS.2 = localhost
IP.1 = ${WEB_IP}
EOF

openssl ecparam -name prime256v1 -genkey -noout -out "$CA_DIR/web.key"
openssl req -new -key "$CA_DIR/web.key" -out "$CA_DIR/web.csr" -config /tmp/web_san.cnf
openssl x509 -req -in "$CA_DIR/web.csr" -CA "$CA_DIR/ca.crt" -CAkey "$CA_DIR/ca.key" \
  -CAcreateserial -days 365 -sha256 -extfile /tmp/web_san.cnf -extensions v3_req \
  -out "$CA_DIR/web.crt"
rm -f /tmp/web_san.cnf

multipass transfer "$CA_DIR/web.crt" web:/tmp/web.crt
multipass transfer "$CA_DIR/web.key" web:/tmp/web.key
multipass exec web -- sudo bash -c '
  mv /tmp/web.crt /etc/ssl/certs/web.crt
  mv /tmp/web.key /etc/ssl/private/web.key
  chown root:root /etc/ssl/private/web.key
  chmod 600 /etc/ssl/private/web.key
  chmod 644 /etc/ssl/certs/web.crt
'
echo "Server certificate installed on web VM."

# "Before" state: port 443 is not listening at all yet (TLS is enabled a
# few lines below), so there is no TLS endpoint for testssl.sh to grade -
# pointing it at the plain HTTP port is not just unhelpful but genuinely
# hangs (observed: testssl.sh spins indefinitely retrying a TLS ClientHello
# against a port that will never answer one). The honest "before" proof is
# simply that no TLS connection can be made at all; testssl_after.txt is
# the only real grade, and the report's Discussion explains why there is
# no "before" grade to compare it to.
echo "--- proving no TLS endpoint exists yet (before hardening) ---"
{
  echo "date_utc=$(date -u +%FT%TZ)"
  echo "curl -sk https://${WEB_IP}/ (expect: connection refused, port 443 not listening):"
  multipass exec attacker -- bash -c "curl -sk --max-time 5 https://${WEB_IP}/ 2>&1" || true
} > evidence/raw/testssl_before.txt

echo "--- enabling TLS on Nginx ---"
multipass transfer lab/configs/nginx/meridian-full.conf.template web:/tmp/meridian-full.conf
multipass exec web -- sudo bash -c '
  set -e
  mv /tmp/meridian-full.conf /etc/nginx/sites-available/meridian.conf
  nginx -t
  systemctl reload nginx
'
echo "TLS enabled, HTTP to HTTPS redirect active."

echo "--- testssl.sh AFTER hardening ---"
multipass exec attacker -- bash -c "/opt/testssl.sh/testssl.sh --quiet https://${WEB_IP} 2>&1 || true" \
  > evidence/raw/testssl_after.txt || true

echo "--- certificate text ---"
multipass exec web -- openssl x509 -in /etc/ssl/certs/web.crt -text -noout \
  > evidence/raw/web_cert_text.txt

echo "--- TLS protocol checks ---"
{
  echo "openssl s_client -tls1_1 (expect failure):"
  multipass exec attacker -- bash -c "echo | openssl s_client -connect ${WEB_IP}:443 -tls1_1 2>&1" || true
  echo ""
  echo "openssl s_client -tls1_3 (expect success):"
  multipass exec attacker -- bash -c "echo | openssl s_client -connect ${WEB_IP}:443 -tls1_3 2>&1" || true
} > evidence/raw/tls_protocol_checks.txt

#######################################
# Phase 4: security hardening
#######################################
echo "=== Phase 4: firewall, SSH, Fail2Ban, MariaDB hardening ==="

echo "nmap BEFORE hardening (web)"
multipass exec attacker -- nmap -sV -T4 -p- "${WEB_IP}" > evidence/raw/nmap_web_before.txt || true
echo "nmap BEFORE hardening (db)"
multipass exec attacker -- nmap -sV -T4 -p- "${DB_IP}" > evidence/raw/nmap_db_before.txt || true

echo "--- ufw on web ---"
multipass transfer lab/configs/ufw/web_rules.sh web:/tmp/web_rules.sh
multipass exec web -- bash /tmp/web_rules.sh

MAC_IP=$(multipass exec web -- bash -c "ip route | awk '/default/ {print \$3; exit}'")
echo "Detected Mac/gateway IP on the Multipass network: ${MAC_IP}"
sed -i '' '/^MAC_IP=/d' lab/.env 2>/dev/null || sed -i '/^MAC_IP=/d' lab/.env
echo "MAC_IP=${MAC_IP}" >> lab/.env

echo "--- ufw on db ---"
sed -e "s/WEB_IP/${WEB_IP}/" -e "s/MAC_IP/${MAC_IP}/" lab/configs/ufw/db_rules.sh.template > /tmp/db_rules.sh
multipass transfer /tmp/db_rules.sh db:/tmp/db_rules.sh
rm -f /tmp/db_rules.sh
multipass exec db -- bash /tmp/db_rules.sh

echo "--- SSH hardening (web, db, attacker) ---"
for name in web db attacker; do
  multipass transfer lab/configs/sshd/99-capstone-hardening.conf "$name:/tmp/99-capstone-hardening.conf"
  multipass exec "$name" -- sudo bash -c '
    mv /tmp/99-capstone-hardening.conf /etc/ssh/sshd_config.d/99-capstone-hardening.conf
    sshd -t
    systemctl restart ssh
  '

  # `systemctl restart ssh` was observed, once, to leave sshd not actually
  # accepting connections afterward (port 22 refused outright, breaking
  # both our own key login AND Multipass's own control channel, which also
  # goes over SSH on this setup despite the guide's troubleshooting table
  # claiming `multipass exec` is independent of the guest's sshd - see
  # docs/decisions.md). A `multipass stop && multipass start` resolved it
  # without data loss. Retry the exec-based restart a few times first
  # (cheap, usually enough); fall back to a VM restart only if needed.
  recovered=0
  for attempt in 1 2 3; do
    if multipass exec "$name" -- bash -c 'systemctl is-active ssh' 2>&1 | grep -q '^active$'; then
      recovered=1
      break
    fi
    echo "[$name] sshd not active after restart (attempt $attempt/3), retrying..."
    multipass exec "$name" -- sudo systemctl restart ssh 2>&1 | cat >/dev/null || true
    sleep 3
  done
  if [[ "$recovered" -ne 1 ]]; then
    echo "[$name] sshd still not responding after retries; stopping and starting the VM to recover..."
    multipass stop "$name"
    multipass start "$name"
    multipass exec "$name" -- bash -c 'systemctl is-active ssh' 2>&1 | cat >/dev/null
  fi
done

echo "--- verifying key login still works after sshd hardening ---"
# Not `${name^^}_IP` + `${!ip_var}`: "attacker" maps to ATT_IP, not
# ATTACKER_IP, so that indirect-expansion trick picks the wrong (unset)
# variable name for exactly one of the three VMs. An explicit case
# statement does not depend on the env var names matching the hostnames.
for name in web db attacker; do
  case "$name" in
    web) ip="$WEB_IP" ;;
    db) ip="$DB_IP" ;;
    attacker) ip="$ATT_IP" ;;
  esac
  ssh -i lab/.secrets/capstone_id_ed25519 -o StrictHostKeyChecking=accept-new \
    -o ConnectTimeout=5 "ubuntu@${ip}" "echo key login ok on $name"
done

echo "--- Fail2Ban on web ---"
multipass transfer lab/configs/fail2ban/jail.local web:/tmp/jail.local
multipass transfer lab/configs/fail2ban/filter-nginx-limit-req.conf web:/tmp/filter-nginx-limit-req.conf
multipass exec web -- sudo bash -c '
  mv /tmp/jail.local /etc/fail2ban/jail.local
  mv /tmp/filter-nginx-limit-req.conf /etc/fail2ban/filter.d/nginx-limit-req.conf
  systemctl enable fail2ban
  systemctl restart fail2ban
'

echo "--- directory listing proof (expect 403/404) ---"
mkdir -p /tmp/no_index_test
multipass exec web -- sudo mkdir -p /var/www/html/no-index
{
  echo "HTTP (port 80):"
  curl -s -o /dev/null -w "HTTP %{http_code}\n" "http://${WEB_IP}/no-index/"
  echo "HTTPS (port 443, self-signed, -k):"
  curl -sk -o /dev/null -w "HTTP %{http_code}\n" "https://${WEB_IP}/no-index/"
} > evidence/raw/directory_listing_check.txt

echo "nmap AFTER hardening (web)"
multipass exec attacker -- nmap -sV -T4 -p- "${WEB_IP}" > evidence/raw/nmap_web_after.txt || true
echo "nmap AFTER hardening (db)"
multipass exec attacker -- nmap -sV -T4 -p- "${DB_IP}" > evidence/raw/nmap_db_after.txt || true

echo "--- nikto scan ---"
multipass exec attacker -- bash -c "nikto -h https://${WEB_IP} -ssl 2>&1" > evidence/raw/nikto_web.txt || true

{
  echo "--- ufw status (web) ---"
  multipass exec web -- sudo ufw status verbose
  echo "--- ufw status (db) ---"
  multipass exec db -- sudo ufw status verbose
  echo "--- sshd -T (web) ---"
  multipass exec web -- sudo sshd -T | grep -E 'permitrootlogin|passwordauthentication|maxauthtries|logingraceTime|allowusers' || true
  echo "--- fail2ban-client status ---"
  multipass exec web -- sudo fail2ban-client status
  echo "--- security headers ---"
  curl -sk -I "https://${WEB_IP}/"
} > evidence/raw/phase4_hardening_summary.txt

echo "Phase 3 and Phase 4 hardening complete. Evidence in evidence/raw/."
