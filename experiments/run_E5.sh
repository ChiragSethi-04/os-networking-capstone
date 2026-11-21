#!/usr/bin/env bash
# E5: brute-force defence. Requires lab/scripts/setup_e5_demo_accounts.sh to
# have been run first (see docs/decisions.md for why dedicated demo
# accounts are used instead of the real admin credentials). This script
# does NOT tear those accounts down; run
# lab/scripts/teardown_e5_demo_accounts.sh afterwards.
# Author: [GROUP MEMBER PLACEHOLDER]
# Date: [DATE PLACEHOLDER]
set -euo pipefail
source "$(dirname "$0")/common.sh"

mkdir -p evidence/raw
OUT="evidence/raw/E5_$(date +%Y%m%dT%H%M%S).txt"
raw_header "E5" > "$OUT"

mp_retry multipass transfer lab/wordlist.txt attacker:/tmp/wordlist.txt

echo "--- BEFORE: stopping fail2ban on web (baseline, unprotected) ---" | tee -a "$OUT"
mp_retry multipass exec web -- sudo systemctl stop fail2ban

echo "--- hydra vs SSH (bftest), unprotected ---" >> "$OUT"
START=$(date +%s)
mp_retry multipass exec attacker -- bash -c "hydra -l bftest -P /tmp/wordlist.txt -t 4 ssh://${WEB_IP} -f" >> "$OUT" 2>&1 || true
END=$(date +%s)
echo "elapsed_seconds=$((END - START))" >> "$OUT"

echo "--- hydra vs Nginx basic-auth demo path, unprotected ---" >> "$OUT"
START=$(date +%s)
mp_retry multipass exec attacker -- bash -c "hydra -l admin -P /tmp/wordlist.txt -t 4 -f ${WEB_IP} https-get /admin-demo/" >> "$OUT" 2>&1 || true
END=$(date +%s)
echo "elapsed_seconds=$((END - START))" >> "$OUT"

echo "--- AFTER: restarting fail2ban on web (protected) ---" | tee -a "$OUT"
mp_retry multipass exec web -- sudo systemctl start fail2ban
sleep 2
mp_retry multipass exec web -- sudo fail2ban-client set sshd unbanip --all 2>&1 | cat >/dev/null || true
mp_retry multipass exec web -- sudo fail2ban-client set nginx-http-auth unbanip --all 2>&1 | cat >/dev/null || true

echo "--- hydra vs SSH (bftest), protected: expect ban partway through ---" >> "$OUT"
START=$(date +%s)
mp_retry multipass exec attacker -- bash -c "hydra -l bftest -P /tmp/wordlist.txt -t 1 ssh://${WEB_IP}" >> "$OUT" 2>&1 || true
END=$(date +%s)
echo "elapsed_seconds=$((END - START))" >> "$OUT"
echo "--- fail2ban sshd status after attack ---" >> "$OUT"
mp_retry multipass exec web -- sudo fail2ban-client status sshd >> "$OUT" 2>&1

echo "--- hydra vs Nginx basic-auth demo path, protected: expect ban partway through ---" >> "$OUT"
START=$(date +%s)
mp_retry multipass exec attacker -- bash -c "hydra -l admin -P /tmp/wordlist.txt -t 1 ${WEB_IP} https-get /admin-demo/" >> "$OUT" 2>&1 || true
END=$(date +%s)
echo "elapsed_seconds=$((END - START))" >> "$OUT"
echo "--- fail2ban nginx-http-auth status after attack ---" >> "$OUT"
mp_retry multipass exec web -- sudo fail2ban-client status nginx-http-auth >> "$OUT" 2>&1

echo "--- post-ban behaviour: attacker tries once more, expect refused/timeout ---" >> "$OUT"
mp_retry multipass exec attacker -- bash -c "timeout 8 ssh -o StrictHostKeyChecking=no -o ConnectTimeout=5 bftest@${WEB_IP} echo should_not_connect" >> "$OUT" 2>&1 || echo "(expected: connection refused/timed out)" >> "$OUT"

echo "E5 raw output: $OUT"
echo "Remember to run lab/scripts/teardown_e5_demo_accounts.sh now."
