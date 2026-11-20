# Verification checklist (10-15 minutes, run before presenting)

Per Part D of the guide: only the group can do this. Run it once, fresh,
after `make demo-reset`.

- [ ] `multipass list` shows `web`, `db`, `attacker` all `Running`.
- [ ] `make demo-reset` completed with no errors (fresh hardened state,
      no leftover E5 demo accounts).
- [ ] Browser: `https://<WEB_IP>/` shows the padlock; clicking it shows a
      certificate issued by "Capstone Lab Root CA" with the right SAN.
- [ ] Browser: `http://<WEB_IP>/` redirects to HTTPS (301).
- [ ] Browser: `https://<WEB_IP>/no-index/` returns 403/404 (no listing).
- [ ] Browser: `https://<WEB_IP>/admin/` prompts for basic auth.
- [ ] Submitting the contact form on `/contact.html` shows the "received"
      confirmation, and the row appears in MariaDB on `db`.
- [ ] `multipass exec web -- sudo ufw status verbose` shows only
      22/80/443 allowed, default deny incoming.
- [ ] `multipass exec attacker -- nmap -p- <WEB_IP>` shows only those
      three ports open.
- [ ] `multipass exec web -- sudo fail2ban-client status` shows the
      `sshd` and `nginx-http-auth` jails active (0 currently banned,
      after a reset).
- [ ] `multipass exec web -- tail -n 5 /var/log/web_status.log` shows
      recent timestamped lines (the monitor timer is running).
- [ ] SSH key login works: `ssh -i lab/.secrets/capstone_id_ed25519
      admin@<WEB_IP> echo ok` prints `ok`.
- [ ] SSH password login is refused for the `admin` account.
- [ ] `report/Capstone_Report.pdf` opens, has a table of contents, and the
      Executive Summary reads correctly.
- [ ] `slides/deck.pptx` (or `deck.pdf`) opens and every content slide has
      a diagram/chart.
- [ ] `docs/viva_qa.md` has been read through at least once by every
      group member.
- [ ] Laptop is plugged into power, Wi-Fi/network stable, unrelated apps
      closed, fallback clips folder is reachable offline if needed.
