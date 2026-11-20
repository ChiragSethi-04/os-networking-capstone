# Viva / Q&A sheet

Answers reference the project's own numbers where the number exists;
`[FILL]` marks a spot to complete once `evidence/processed/*.csv` and
Section 4 of the report are final. Read this twice before presenting
(Part D of the guide) and practise saying the architecture and one
benchmark chart out loud.

## Architecture and design choices

1. **Why Nginx over Apache, Lighttpd, or IIS?**
   Nginx's event-driven worker model handles many concurrent connections
   in one process without a thread/process per connection, which our own
   E1 benchmark shows as [FILL: req/s and CPU numbers at c=200]. Lighttpd
   uses a similar model but has a smaller ecosystem; IIS is Windows-only
   and our VMs run Ubuntu.

2. **Why keep Apache at all if Nginx was chosen?**
   To benchmark the choice against real hardware instead of asserting it;
   Apache runs identically on port 8080 for E1-E3, kept stopped otherwise
   so it is not part of the attack surface (Phase 4's `nmap` would catch
   it if it were left running).

3. **What is event-driven I/O and why is it faster under concurrency?**
   One (or a few) worker processes run a non-blocking event loop (epoll
   on Linux) over many sockets, instead of blocking one OS thread/process
   per connection; memory and context-switch overhead per connection stay
   low as concurrency rises.

4. **What is a DMZ, and does this project have a true one?**
   A network segment for internet-facing services, isolated from trusted
   internal systems. Here it is simulated with host-based firewalls
   (`ufw`) rather than a real separate network segment, because the three
   Multipass VMs share one virtual bridge/NAT network on the host - stated
   as an explicit limitation in report Section 1.4.

5. **Why separate web and database VMs?**
   So a web-tier compromise does not automatically grant network reach to
   the database; `db`'s firewall only allows 3306/tcp from the web VM's
   specific IP.

6. **Why a self-signed/local CA instead of Let's Encrypt?**
   Let's Encrypt's HTTP-01/DNS-01 validation needs a publicly resolvable
   domain pointing at a reachable host; a NAT'd lab VM has neither. Using
   our own CA also lets us show the browser in both the warning
   (untrusted) and trusted (CA imported) states for the demo.

7. **Why `ufw` instead of raw `nftables`/`iptables`?**
   Thinner, declarative syntax over the same kernel packet filter, lower
   risk of a hand-written rule mistake under time pressure, and what the
   project brief's own template specifies.

## TLS

8. **What happens in a TLS handshake (at a high level)?**
   ClientHello (supported versions/ciphers/SNI) -> ServerHello + certificate
   + key share -> client verifies the certificate against a trusted CA and
   sends its own key share -> both sides derive session keys -> encrypted
   application data. See report Figure F3.

9. **Why TLS 1.3 over 1.2?**
   Removes legacy ciphers and static RSA key exchange, mandates forward
   secrecy, and completes a full handshake in one round trip instead of
   two, which our E2 handshake-timing numbers show as [FILL].

10. **Why not allow TLS 1.0/1.1?**
    Both have known cryptographic weaknesses (e.g. BEAST, weak hash
    usage) and are excluded by the Mozilla "intermediate" guidance and
    NIST SP 800-52 we followed.

11. **What is a certificate's Subject Alternative Name and why did ours
    need one?**
    The set of names/IPs a certificate is valid for; modern browsers
    ignore the legacy Common Name field. Our cert covers `web`, the web
    VM's IP, and `localhost`.

12. **What does HSTS do and why add it?**
    Tells a browser that has already visited once to refuse a future
    plaintext connection to the same host for the given max-age, even if
    a user types `http://`.

13. **What is OCSP stapling and why did you disable it?**
    A way for the server to proactively prove its certificate is not
    revoked, avoiding a client-side lookup. Disabled here because a
    privately-issued CA has no public OCSP responder to staple from; noted
    explicitly in the Nginx config as a documented limitation, not an
    oversight.

14. **What TLS grade did testssl.sh give before vs after hardening?**
    [FILL from E9/Figure F14].

## Firewall and attack surface

15. **Why exactly ports 22, 80, 443 on web?**
    SSH for administration, HTTP only to redirect to HTTPS, HTTPS for the
    actual site. Anything else running (e.g. a stray dev server) would be
    an unnecessary attack surface.

16. **Why is MariaDB's port not open at all externally?**
    `bind-address` is set to the db VM's own IP (not `0.0.0.0`), and
    `ufw` additionally only allows 3306/tcp from the web VM's specific IP
    - two independent layers, so a misconfiguration in one does not fully
    expose the database (defence in depth).

17. **What did `nmap -p-` show before vs after hardening?**
    [FILL exact port counts/lists from E4/Figure F9].

18. **Why also run `nikto`, if `nmap` already shows open ports?**
    `nmap` finds open ports and services; `nikto` probes the web
    application itself for known-vulnerable paths/misconfigurations that
    port scanning alone would not reveal.

19. **Why disable directory listing, specifically?**
    An exposed directory listing can reveal file names, backup files, or
    structure useful to an attacker, with no legitimate benefit to a site
    visitor; we prove it is off by requesting a directory with no index
    file and getting 403/404 rather than a file list.

## Brute-force defence and rate limiting

20. **How does Fail2Ban actually work?**
    It tails authentication/error logs for a pattern, counts matches per
    source IP within a rolling `findtime` window, and once `maxretry` is
    exceeded within that window, inserts a temporary firewall ban rule for
    `bantime`.

21. **What do `maxretry`, `findtime`, and `bantime` mean, and why these
    values?**
    `maxretry=3`: ban after 3 failures. `findtime=10m`: those failures
    must occur within a rolling 10-minute window. `bantime=10m`: the ban
    itself lasts 10 minutes. Chosen to ban quickly while tolerating one or
    two genuine mistyped-password attempts.

22. **Why does E5 use throwaway accounts instead of the real admin
    credentials?**
    The real credentials are randomly generated 24-character strings that
    a small, honest wordlist could never guess in a reasonable demo; a
    dedicated weak-password SSH user and Nginx path demonstrate the full
    story (a guess succeeding when unprotected, a ban happening first when
    protected) without ever exposing or weakening the real admin path.
    See report Section 3.3 and `docs/decisions.md`.

23. **What's the difference between Fail2Ban and Nginx's `limit_req`?**
    Fail2Ban is reactive: it detects a pattern of failures after the fact
    and bans the source. `limit_req` is preventive: it caps the rate of
    requests per source regardless of whether they are failing, before
    any ban decision is made.

24. **What happened to the status code mix with vs without `limit_req`
    under flood (E6)?**
    [FILL from E6/Figure F11: 200 vs 429/503 counts].

25. **Why did you pick those specific `limit_req` rates?**
    [FILL: state the rate chosen for `/api/` and `/admin/` and the
    reasoning, e.g. expected legitimate client request rate with headroom].

## Monitoring and resilience

26. **How does the monitor script detect and recover from a failure?**
    A systemd timer runs it every 30 seconds; it checks each service with
    `systemctl is-active`, and if a service is down, calls `systemctl
    restart` on it and logs both the DOWN and RESTARTED events with a
    timestamp to `/var/log/web_status.log`.

27. **Why not just rely on `systemd`'s own `Restart=on-failure`?**
    Both are used together: `Restart=on-failure` is systemd's own fast
    first line of defence; the monitor script adds an independent,
    logged, human-readable record of the event and also checks things
    systemd alone does not (TLS cert expiry, database reachability, disk
    usage).

28. **How long did it take to detect and restart nginx after a SIGKILL
    (E8)?**
    [FILL from E8/Figure F13].

29. **Why `logrotate` at all?**
    Unbounded log growth can eventually fill the disk; `logrotate`
    rotates, compresses, and caps retained history (`rotate 8`) so logs
    stay useful without unbounded growth.

30. **What does `logrotate -d` vs `-f` do, and why run both?**
    `-d` is a dry run (shows what would happen without changing
    anything); `-f` forces an actual rotation regardless of the normal
    schedule/size trigger, used here to prove the config works without
    waiting a full week.

## Benchmarking and methodology

31. **Why run each experiment at least 5 times?**
    A single run can be skewed by transient host noise; repeats let us
    report a mean, standard deviation, and 95% confidence interval instead
    of one possibly-unrepresentative number.

32. **Why alternate Apache/Nginx run order instead of running all of one
    then all of the other?**
    To average out any slow drift in host conditions over the course of
    the benchmark session, rather than having that drift bias one server
    more than the other.

33. **What did pidstat/sar actually measure, and what's the limitation?**
    CPU utilisation sampled during each run; the limitation documented in
    report 5.3 is that the sampling is closer to system-wide than
    strictly per-process when multiple workers are active, so Figure F6
    is read as a comparison, not an absolute per-request CPU cost.

34. **What is a threat to validity in this benchmark, and why does it
    matter?**
    The load generator (`attacker` VM) and the server (`web` VM) share one
    physical host and hypervisor, so network latency is closer to
    loopback than to a real wide-area path; absolute throughput numbers
    should not be read as an internet-facing capacity estimate.

35. **If Apache was ever faster than Nginx at low concurrency, what would
    you check before accepting that at face value?**
    Worker/MPM and `worker_processes` tuning on both sides, keep-alive
    settings, and file-system/page caching effects - investigate and
    explain rather than hide an inconvenient result (CLAUDE_CODE_GUIDE.md
    Phase 6 guidance).

36. **Why measure reverse-proxy overhead (E3) separately from raw Nginx
    throughput (E1)?**
    To isolate the specific cost of the `proxy_pass` hop to gunicorn from
    Nginx's own static-file serving, so the two costs are not conflated
    in Section 4's numbers.

## General OS/networking

37. **What OSI layers appear in this project's own request path, and
    where?**
    L3 (IP) and L4 (TCP) at the firewall and socket level; L6
    (TLS/presentation) at the Nginx TLS listener; L7 (HTTP/application) at
    both Nginx's routing and the Flask app. See report Figure F2.

38. **What permissions did you set on the web root, and why those
    specific values?**
    Directories 755, files 644, owned by `root:www-data`: the web server
    needs to read and list directories but nothing besides the owning
    user should be able to write to site content, following the project
    brief's own Task 2.2 template.

39. **Why `AllowUsers ubuntu` and `PermitRootLogin no` together?**
    Defence in depth again: even if root's password were somehow known,
    direct root login over SSH is refused outright, and only the named
    `ubuntu` account (key-only) is permitted to authenticate at all. This
    is Multipass's own default account rather than a custom one we
    created, because adding a custom user via cloud-init's `users:`
    module hung every VM on this setup (see `docs/decisions.md`).

40. **What would you change first if this had to serve real production
    traffic at scale?**
    High availability behind a load balancer (report Section 7) - the
    current single `web` VM is a single point of failure that Phase 5
    detects and recovers from but does not prevent.

41. **How do you reproduce every number in this report from scratch?**
    `docs/reproduce.md`: `make lab && make test && make bench && make
    figures && make report` rebuilds the lab and regenerates every
    artifact from the committed scripts and configs.

42. **What's the difference between the `/admin/` path and the
    `/admin-demo/` path shown in E5, and why does that distinction
    matter?**
    `/admin/` is the real, production-intent basic-auth path with a
    strong random password, never targeted by the brute-force demo.
    `/admin-demo/` is a throwaway path created only for E5 and torn down
    immediately after, so the demo never touches or weakens the real
    credential.
