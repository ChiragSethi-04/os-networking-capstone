# Browser evidence (Phase 7)

Taken with Claude in Chrome once Phase 3 (TLS) is live, saved under
`evidence/screenshots/` (originals in `evidence/screenshots/original/`,
cropped/annotated copies alongside):

1. `https://<WEB_IP>/` with the padlock visible and the certificate details
   opened (issuer: Capstone Lab Root CA).
2. The browser's certificate-warning / "not private" interstitial, visiting
   the same URL in a profile that has not imported the lab CA.
3. `https://<WEB_IP>/no-index/` returning 403 (directory listing disabled).
4. `https://<WEB_IP>/admin/` showing the basic-auth prompt.
5. A 429 response, triggered by exceeding `limit_req` on `/api/`.

Access `WEB_IP` directly (Multipass VMs are not reachable via the `web`
hostname from the Mac's own browser); `/etc/hosts` on the Mac can map
`web -> WEB_IP` if a hostname in the address bar is preferred, matching the
certificate's SAN.
