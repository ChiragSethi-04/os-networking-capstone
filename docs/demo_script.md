# Live demo script (target: 10-12 minutes)

Run `make demo-reset` immediately before presenting (restores the
`clean-baseline` snapshots, then re-applies Phases 2-5 so the lab is in its
final hardened state with no leftover demo-only accounts). Keep this file
open on a second screen or printed.

Fallback: if any live step fails, say so, show the pre-recorded 30-second
clip for that step (recorded during rehearsal, `evidence/screenshots/` or
a `demo_fallback_clips/` folder), and continue. Never silently skip a
step. A fallback clip is used only with the presenting group's own
on-the-spot judgement that the live version is not going to work in the
time available, not pre-planned avoidance.

## Steps

1. **What's running** (1 min)
   - `multipass list` — three VMs, all Running.
   - `multipass exec web -- sudo ss -tulpn` and same on `db` — show nginx
     (80/443), gunicorn (127.0.0.1:8000), mariadb (3306, db VM only).

2. **Browser: HTTPS and the certificate** (1.5 min)
   - Open `https://<WEB_IP>/` — padlock, click it, show the certificate
     (issuer: Capstone Lab Root CA, SAN covering `web`).
   - Open `http://<WEB_IP>/` in the same tab — show the 301 redirect to
     HTTPS.

3. **Firewall and attack surface** (1.5 min)
   - `multipass exec web -- sudo ufw status verbose` — only 22/80/443.
   - From `attacker`: `nmap -p- <WEB_IP>` and `nmap <DB_IP>` — same result
     live, matching the F9 figure.

4. **Directory listing disabled** (0.5 min)
   - `curl -sk -o /dev/null -w '%{http_code}\n' https://<WEB_IP>/no-index/`
     — 403.

5. **Load test with live resource monitoring** (2 min)
   - Split terminal: `multipass exec web -- htop` on one side.
   - From `attacker`: `wrk -t2 -c100 -d20s --latency https://<WEB_IP>/`.
   - Narrate what's happening in htop while it runs.

6. **Brute-force defence** (2 min)
   - `bash lab/scripts/setup_e5_demo_accounts.sh` (if not already left up
     from rehearsal).
   - From `attacker`: `hydra -l admin -P lab/wordlist.txt -t 1
     <WEB_IP> https-get /admin-demo/`.
   - `multipass exec web -- sudo fail2ban-client status nginx-http-auth`
     — show the banned attacker IP.
   - `bash lab/scripts/teardown_e5_demo_accounts.sh` after.

7. **Resilience** (1.5 min)
   - `multipass exec web -- sudo systemctl stop nginx`.
   - `multipass exec web -- tail -f /var/log/web_status.log` — wait for
     `DOWN` then `RESTARTED` (up to 30-60s; narrate while waiting).
   - Reload the browser tab — site is back.

8. **Contact form round-trip** (1 min)
   - Submit the contact form on `https://<WEB_IP>/contact.html`.
   - `multipass exec db -- sudo mysql -e "SELECT * FROM
     meridian.contact_messages ORDER BY id DESC LIMIT 1;"` — show the row.

## Reset between rehearsal and the real run

`make demo-reset` runs `lab/scripts/demo_reset.sh`, which restores each
VM's `clean-baseline` snapshot and re-runs `make lab` so the fresh VMs are
back in the final hardened state (no demo-only accounts, no leftover
Fail2Ban bans, no accumulated log noise) before presenting.
