# Figure captions

**F1**: Network architecture: Internet/attacker VM, host firewall, web VM (Nginx, Apache baseline, Flask/gunicorn), db VM (MariaDB), and the Mac as admin workstation.

**F2**: Request flow from client to Nginx to the Flask app and MariaDB, with the OSI layer each hop operates at.

**F3**: TLS 1.3 handshake sequence between the attacker VM (as a plain client) and Nginx on the web VM, ending in encrypted application data.

**F4**: E1 throughput vs concurrency, Apache vs Nginx, error bars show 95% CI across repeated runs.

**F5**: E1 mean and 90th-percentile latency (used as a p95 proxy; wrk's default histogram does not expose p95 directly) vs concurrency, one panel per server.

**F6**: E1 CPU usage, Apache vs Nginx, averaged across all concurrency levels and repeats (error bars: 95% CI). Per-process memory was not reliably isolated from pidstat's system-wide sampling; see Discussion 5.3.

**F7**: E2 transport cost: HTTP vs HTTPS throughput (left), and total connection time for TLS 1.2 vs TLS 1.3 (right).

**F8**: E3 reverse proxy overhead: static file throughput vs the same site's /api/health proxied through gunicorn.

**F9**: E4 attack surface: open TCP ports on web and db, before vs after Phase 4 hardening (see Table in Results for the exact port lists).

**F10**: E5 brute-force timeline: time to a successful guess when unprotected (orange) vs time to a Fail2Ban ban when protected (blue), for SSH and the Nginx basic-auth demo path.

**F11**: E6 status code distribution for a burst of sampled requests to /api/health, with vs without Nginx limit_req active. Without the limiter, requests are not rejected outright but queue against the gunicorn backend and mostly time out (504), at far lower throughput than the limiter's quick, cheap 503 rejections - see Discussion 5.3.

**F13**: E8 resilience timeline: seconds between killing Nginx and systemd's Restart=on-failure bringing it back up (measured with host-side timestamps; see Discussion 5.3 for why the custom monitor script could not independently confirm the same event this run).

**F14**: E9 TLS quality: testssl.sh overall grade before vs after Phase 3 TLS hardening.
