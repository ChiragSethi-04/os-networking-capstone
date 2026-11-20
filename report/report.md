---
title: "Deploying a Secure Web Server and Hosting a Company Website"
subtitle: "OS & Networking Capstone, Project 2"
author:
  - Chirag Sethi
  - Shree Iyengar
  - Hardik Sharma
  - Mehul Nagarkoti
date: "[SUBMISSION DATE PLACEHOLDER]"
course: "Operating Systems & Networking (Capstone), Group 6"
lecturer: "[LECTURER NAME PLACEHOLDER]"
geometry: "a4paper,margin=2.54cm"
fontsize: 11pt
linestretch: 1.25
toc: true
lof: true
numbersections: true
bibliography: references.bib
link-citations: true
---

# Executive Summary

[WRITTEN LAST, 200-300 WORDS. Draft once Results (Section 4) is final:
problem background, the three measurable objectives from 1.3, the
methodology in one paragraph, three or four quantified findings (E1
throughput/latency numbers, E4 port reduction, E5 ban time, E9 TLS grade),
and the headline recommendation from Section 7.]

\newpage

# 1. Introduction

## 1.1 Background and Context

Small logistics operators increasingly run their own customer-facing web
presence rather than outsourcing it to a managed hosting provider, both to
control cost and to integrate a contact workflow directly with internal
systems. This project builds and evaluates such a deployment for a
fictional company, Meridian Logistics, as a teaching vehicle for the core
operating systems and networking concepts of a production web stack:
process and service management, TCP/IP and the OSI model in a live request
path, transport-layer security, firewalling and defence in depth, and
system monitoring with automatic recovery.

## 1.2 Problem Statement

A web server exposed directly to the internet with default settings
presents a large, often unnecessary attack surface: every installed
service's port is reachable, directory listings leak file structure,
traffic travels in plaintext, and there is no mechanism to notice or react
to either an outage or an attack in progress. This report addresses the
gap between "a web server that works" and "a web server that is
deliberately hardened, monitored, and whose behaviour under load and under
attack has been measured rather than assumed."

## 1.3 Aims and Objectives

The group set the following measurable targets:

1. Serve the Meridian Logistics site over HTTPS at a sustained throughput
   of at least **[TARGET RPS PLACEHOLDER] requests/sec** at 50 concurrent
   connections, with p95 latency under **[TARGET LATENCY PLACEHOLDER] ms**
   (see Table in Section 4, from experiment E1/E2).
2. Reduce the externally visible attack surface to exactly three open TCP
   ports on the web tier (22, 80, 443) and zero directly reachable
   application ports on the database tier, verified by `nmap -p-`
   (experiment E4).
3. Detect and ban a brute-force credential attack against SSH and the
   admin HTTP path within **[TARGET BAN TIME PLACEHOLDER] seconds** of the
   configured retry threshold being exceeded (experiment E5).
4. Detect an unplanned service outage and automatically restore service
   within 60 seconds, with the event timestamped in a monitoring log
   (experiment E8).
5. Achieve a testssl.sh overall grade of **[TARGET TLS GRADE PLACEHOLDER]**
   or better after TLS hardening (experiment E9).

## 1.4 Scope and Limitations

The deployment runs entirely inside three Multipass-managed Ubuntu LTS
virtual machines on a single Apple Silicon Mac (Section 3.2), not on
separate physical hosts or in a cloud provider's network. Consequently:

- Network segmentation between the web and database tiers is enforced by
  host-level firewalls (`ufw`) on each VM rather than by separate VLANs or
  physical network isolation, because Multipass VMs share one virtual
  bridge/NAT network on the host. This is stated here as an explicit,
  honest limitation rather than implied to be a true DMZ.
- TLS uses a locally generated, self-signed certificate authority rather
  than a certificate from a public CA such as Let's Encrypt, because
  Let's Encrypt's HTTP-01/DNS-01 validation requires a publicly resolvable
  domain name, which this lab environment does not have (Section 3.1).
- Load is generated from a second VM on the same physical host and
  hypervisor, not over a wide-area network, so absolute throughput numbers
  should be read as internal, same-host benchmarks, not as an estimate of
  internet-facing capacity (Section 5.3).
- No production customer traffic, real personal data, or public-facing
  exposure is involved; Meridian Logistics is a fictional company created
  for this project.

\newpage

# 2. Literature Review / Theoretical Framework

## 2.1 HTTP and transport

HTTP/1.1 semantics are defined by RFC 9110 [@rfc9110], which separates the
abstract request/response model from any one transport. HTTP/2 (RFC 9113
[@rfc9113]) multiplexes many logical streams over a single TCP connection,
removing head-of-line blocking at the application layer that affected
HTTP/1.1 pipelining; Nginx's `http2 on;` directive (Section 3) enables this
on the TLS listener only, since all mainstream browsers require HTTP/2 to
be negotiated over TLS via ALPN in practice.

## 2.2 Transport Layer Security

TLS 1.3 (RFC 8446 [@rfc8446]) removes legacy cipher suites and static RSA
key exchange, requiring forward secrecy on every handshake and cutting the
handshake to one round trip (zero round trips for a resumed session). This
project pins the server to TLS 1.2 and 1.3 only (Section 3.1), following
NIST SP 800-52 Rev. 2 [@nist80052] and the Mozilla "intermediate"
compatibility guidance [@mozillatls], which is also the direct source for
the cipher list configured in `lab/configs/nginx/`. Certificates are
structured as X.509 (RFC 5280 [@rfc5280]); HSTS (RFC 6797 [@rfc6797])
is used to tell a browser that has already visited the site once to refuse
a future plaintext connection to it.

## 2.3 Web server architectures

Apache's traditional MPMs (prefork, worker) dedicate a process or thread
per connection, which is simple to reason about but scales memory
linearly with concurrent connections. Nginx uses an event-driven,
non-blocking worker model: a small, fixed number of worker processes each
run an event loop (epoll on Linux) handling many connections
concurrently, which is the architectural reason Nginx is widely reported
to hold memory usage flatter under high concurrency. This project measures
that difference directly (experiment E1) rather than citing it as given.
Lighttpd uses a broadly similar event-driven model to Nginx but has a
smaller deployment and module ecosystem; IIS is excluded outright because
the lab VMs run Ubuntu Linux (Section 3.1 documents the selection
reasoning for all four).

## 2.4 Defence in depth: DMZ, firewalls, and brute-force protection

A demilitarized zone (DMZ) places internet-facing services in a network
segment isolated from internal/trusted systems, so that compromising the
public-facing host does not directly expose the database tier. `ufw` is
used here as a host-based packet filter implementing that boundary
(Section 1.4 documents why this is host-based rather than a true separate
network segment in this lab). Fail2Ban [@fail2bandocs] implements
brute-force defence by tailing authentication logs for repeated failures
and inserting a temporary firewall rule once a threshold is crossed; this
is a detection-and-response control, distinct from `limit_req`'s
preventive rate limiting, and the two are evaluated separately
(experiments E5 and E6). General secure-configuration guidance throughout
the hardening phase follows OWASP [@owasptop10] and CIS Benchmarks
[@cisbenchmarks] recommendations for web servers and Linux hosts.

\newpage

# 3. Methodology / System Design

## 3.1 Approach and Design Decisions

**Web server choice.** Nginx was selected as the production web server.

| Web server | Speed (event model) | Ease of configuration | Reverse proxy | Documentation |
|---|---|---|---|---|
| Apache | Process/thread per connection; higher memory under concurrency | Very mature, `.htaccess` flexibility | Possible via `mod_proxy` | Extensive [@apachedocs] |
| Nginx | Event-driven, low memory under concurrency | Declarative, single config tree | Native, first-class | Extensive [@nginxdocs] |
| Lighttpd | Event-driven, similar model to Nginx | Smaller community, fewer guides | Supported, less common | Sparser |
| IIS | Event-driven (IOCP) | Windows-only | Supported via ARR | Good, Windows-specific |

Table: Web server comparison (Task 1.2 of the project brief).

Apache is not discarded: it is deployed identically on port 8080 as a
same-hardware baseline so the Nginx-vs-Apache choice is backed by the
project's own throughput and resource data (experiment E1), not only by
the qualitative comparison above. Lighttpd and IIS are discussed here but
not deployed, for the ecosystem/platform reasons in the table.

**Web/database separation.** The web and database tiers run on separate
VMs (`web`, `db`). This bounds the blast radius of a web-tier compromise:
even full control of the web VM does not grant network access to the
database beyond the single port the firewall allows from that VM's IP
(Section 3.3, Phase 4). The admin workstation (the Mac) is a third
logical role, reachable only via SSH key authentication.

**TLS certificate strategy.** A local root CA was created with `openssl`
and used to sign a server certificate for `web`, with Subject Alternative
Names covering the hostname, the VM's IP, and `localhost`. The alternative,
Let's Encrypt, was considered and rejected for this environment
specifically because its domain-validation challenge types require a
publicly resolvable DNS name pointing at a reachable port 80/443, which a
NAT'd lab VM does not have (Section 1.4). The self-signed/local-CA
approach has the advantage, for a teaching demo, of being able to show a
real browser in both the untrusted (warning) and trusted (CA imported)
states (Section 4, Figure/screenshot evidence).

**Firewall tooling.** `ufw` was used over `nftables` directly: `ufw` is a
thinner, declarative layer over the same packet-filtering subsystem,
reduces the chance of a hand-written rule mistake under time pressure, and
is what the project brief's own Task 3.1 template specifies.

## 3.2 Tools and Technologies

| Component | Tool / version | Role |
|---|---|---|
| Hypervisor | Multipass [@multipassdocs] on macOS (Apple Silicon) | Runs the three lab VMs |
| Guest OS | Ubuntu LTS (`multipass launch lts`) | Web, db, attacker VMs |
| Web server | Nginx | TLS termination, reverse proxy, rate limiting, static files |
| Baseline web server | Apache httpd + `apache2-utils` | Same-hardware comparison (port 8080) |
| Application | Python 3, Flask, gunicorn, PyMySQL | `/api/health`, `/api/contact`, `/api/stats` |
| Database | MariaDB | Contact-form storage |
| TLS | OpenSSL | Local CA, server certificate, protocol/cipher tests |
| Firewall | `ufw` | Host-based packet filtering on web and db |
| Brute-force defence | Fail2Ban [@fail2bandocs] | `sshd`, `nginx-http-auth`, `nginx-limit-req` jails |
| Benchmarking | `wrk` [@wrktool], Apache Bench (`ab`), `curl -w`, `openssl s_time` | E1-E3 throughput/latency/handshake |
| Attack surface | `nmap`, `nikto` | E4 |
| Brute-force tooling | `hydra` | E5, against lab-only throwaway credentials |
| Packet capture | `tcpdump`, `tshark` | E7 |
| TLS grading | `testssl.sh` [@testssl] | E9 |
| Monitoring | Custom bash script + systemd timer, `sysstat` | Phase 5 |
| Diagrams | Graphviz, Matplotlib | Figures F1-F14 |
| Report build | Pandoc + XeLaTeX | This PDF/DOCX |

## 3.3 Implementation and Procedures

Implementation proceeded in the ten phases below; each phase has an
automated acceptance check (`make test-phaseN`) and saves raw evidence
under `evidence/raw/` before the next phase begins (full scripts in
Appendix A, full raw logs in Appendix B).

1. **Preflight and provisioning**: host tool check, three VMs launched
   from cloud-init (`lab/cloud-init/*.yaml`), SSH key distributed, IPs
   recorded, a `clean-baseline` snapshot taken of each VM.
2. **Web tier**: static site and Flask/gunicorn app deployed to `web`;
   Nginx and Apache installed; MariaDB schema and a least-privilege
   application user created on `db`.
3. **TLS**: local CA and server certificate generated and installed;
   Nginx TLS 1.2/1.3 configuration with HSTS and HTTP/2; `testssl.sh`
   run before and after.
4. **Hardening**: `ufw` rules on both VMs; directory listing disabled;
   security headers; SSH key-only login; Fail2Ban; Nginx rate limiting;
   MariaDB anonymous-user/test-database removal.
5. **Monitoring and resilience**: a 30-second systemd timer checks service
   health, TLS expiry, disk, load, and database reachability, restarting
   any service it finds down; `logrotate` configured for all logs.
6. **Experiments E1-E9**: described fully in Section 4 and Appendix B.
7. **Figures and screenshots**: F1-F14 generated programmatically from
   `evidence/processed/` CSVs (Appendix A, `figures/figures.py`); browser
   and terminal screenshots captured and rendered to a consistent style.
8. **This report.**
9. **Slides, demo script, viva sheet, peer review templates.**
10. **Final QA**: full rebuild from a clean VM state, rubric
    self-audit (`docs/rubric_audit.md`), packaging.

A deliberate exception to "configs are the single source of truth,
deployed as-is" is documented here for transparency: experiment E5 (brute
force) cannot demonstrate a successful credential guess against the
project's real admin credentials, because those are randomly generated
24-character strings that a small, honestly self-made wordlist could never
guess. A throwaway SSH user and a throwaway Nginx basic-auth path, both
using one deliberately weak password that also appears in
`lab/wordlist.txt`, are created immediately before E5 and removed
immediately after (`lab/scripts/setup_e5_demo_accounts.sh` /
`teardown_e5_demo_accounts.sh`); the real `admin` account and the real
`/admin/` path are untouched throughout. This is recorded in
`docs/decisions.md` and repeated here because it is a methodological
choice a marker would reasonably ask about in the viva (Section 3c of the
rubric).

\newpage

# 4. Results and Findings

*[This section is populated by `make bench` + `make figures` against the
live lab. Each subsection below names the figure/table it must cite; fill
the prose once `evidence/processed/*.csv` exist. Do not add interpretation
here, only what was measured (Section 5 is where it is explained).]*

## 4.1 E1: Apache vs Nginx static throughput and latency

See Figure F4 (throughput vs concurrency) and Figure F5 (mean and p90/p95
latency vs concurrency), Table [TABLE NUMBER] (full mean/SD/95% CI per
concurrency level), and Figure F6 (CPU usage). [FILL: headline numbers at
c=50 and c=200 for both servers.]

## 4.2 E2: HTTP vs HTTPS, TLS 1.2 vs 1.3, keep-alive

See Figure F7. [FILL: throughput delta HTTP vs HTTPS; handshake time
TLS 1.2 vs 1.3; keep-alive on/off delta.]

## 4.3 E3: reverse proxy overhead

See Figure F8. [FILL: static vs proxied throughput delta.]

## 4.4 E4: attack surface before and after hardening

See Figure F9 and the full port list in Appendix B
(`nmap_web_before.txt`/`_after.txt`, `nmap_db_before.txt`/`_after.txt`).
[FILL: exact port counts and the nikto findings that were and were not
remediated.]

## 4.5 E5: brute-force defence

See Figure F10. [FILL: attempts/time to successful guess when
unprotected; time to Fail2Ban ban when protected; post-ban behaviour for
both SSH and the Nginx basic-auth demo path.]

## 4.6 E6: rate limiting under flood

See Figure F11. [FILL: status code mix with vs without `limit_req`.]

## 4.7 E7: encryption proof

See Figure F12 and `evidence/processed/E7_summary.md`. [FILL: confirm HTTP
payload was plaintext-visible in the capture and HTTPS was not.]

## 4.8 E8: resilience

See Figure F13. [FILL: seconds from `SIGKILL` to detected-and-restarted;
logrotate forced-run result.]

## 4.9 E9: TLS quality

See Figure F14 and `evidence/processed/E9_summary.md`. [FILL: testssl.sh
grade before vs after.]

\newpage

# 5. Discussion and Analysis

## 5.1 Critical Evaluation

[FILL once Section 4 is final: interpret each result against the
objectives in 1.3 — were they met, by how much, and does the Section 4
evidence actually support that.]

## 5.2 Comparison with Baselines

[FILL: Nginx vs Apache result explained via the event-driven vs
process/thread model (Section 2.3); TLS overhead explained via handshake
cost and session resumption/keep-alive amortisation; Fail2Ban ban timing
explained arithmetically from `maxretry`/`findtime`/`bantime`
(Section 3.3's hardening values).]

## 5.3 Challenges and Edge Cases

Documented honestly as they are found, for example:

- Multipass VMs share one host and one virtual network: if E1's results
  show Apache competitive with or faster than Nginx at low concurrency,
  the likely cause is MPM/worker-count tuning or file-system caching
  rather than a flaw in the event-driven argument of Section 2.3; this
  must be investigated (pin worker counts, repeat, inspect `pidstat`) and
  explained here, not hidden (CLAUDE_CODE_GUIDE.md Phase 6 notes).
- pidstat sampling during E1 reports system-wide, not strictly
  per-process, CPU figures when multiple workers are active; Figure F6's
  caption and this subsection should state that precision limit plainly.
- Threats to validity: a shared hypervisor and loopback-like intra-host
  latency between `attacker` and `web` mean absolute throughput numbers do
  not generalise to a real wide-area deployment (Section 1.4).

\newpage

# 6. Conclusion

[FILL, no new data: state plainly, objective by objective from 1.3,
whether each was met, citing the Section 4 number.]

# 7. Recommendations / Future Work

For a production evolution of this deployment, the group recommends:

- **High availability**: a second web node behind a load balancer (Nginx
  upstream or a managed LB), removing the single point of failure that
  Phase 5's resilience test currently only detects and restarts rather
  than avoids.
- **Web Application Firewall (WAF)**: ModSecurity or an equivalent in
  front of Nginx, to catch application-layer attacks that `nmap`/rate
  limiting do not address.
- **Centralised logging**: ship `web_status.log`, Nginx, and Fail2Ban logs
  to a central collector (e.g. Loki, ELK) rather than per-VM files, so a
  real multi-host deployment has one place to look.
- **Automated certificate management**: replace the local CA with
  Let's Encrypt (or an internal ACME server) once a real, publicly
  resolvable domain exists, removing manual certificate renewal.
- **Intrusion detection**: a host or network IDS (e.g. Suricata) alongside
  Fail2Ban's reactive banning, for attack patterns that do not show up as
  simple repeated-failure log lines.
- **Secrets management**: move `lab/.secrets` out of plain files on disk
  and into a secrets manager (Vault, or the cloud provider's native
  equivalent) if this were ever run outside a disposable lab.

# References

::: {#refs}
:::

\newpage

# Appendices

## Appendix A: Source Code and Configuration Files

Full, current versions of every script and config referenced in this
report live in the repository at the paths named throughout Sections 3-4
(`lab/scripts/`, `lab/configs/`, `site/`, `experiments/`, `figures/`).
They are not reproduced in full here to keep the main body within the
10-15 page target; this appendix lists the authoritative path for each
component discussed above.

| Component | Path |
|---|---|
| Cloud-init (VM bootstrap) | `lab/cloud-init/{web,db,attacker}.yaml` |
| Provisioning / deploy / hardening scripts | `lab/scripts/{provision,deploy_site,harden,setup_monitoring}.sh` |
| Nginx / Apache / MariaDB / Fail2Ban / ufw / sshd configs | `lab/configs/` |
| Website and Flask app | `site/` |
| Experiment scripts | `experiments/run_E1.sh` ... `run_E9.sh`, `parse_E1.py` ... `parse_E9.py` |
| Figures | `figures/figures.py` |

## Appendix B: Raw Logs and Extended Tables

Full raw tool output (one timestamped file per run) is under
`evidence/raw/`; parsed CSVs with every individual run (not just the
means reported in Section 4) are under `evidence/processed/`. Referenced
explicitly in Section 4: `nmap_web_before.txt`, `nmap_web_after.txt`,
`nmap_db_before.txt`, `nmap_db_after.txt`, `testssl_before.txt`,
`testssl_after.txt`, `E1.csv` ... `E9.csv` (and `E2_handshake.csv`,
`E4_ports.csv`), `Ex_notes.md`.

## Appendix C: Contribution Statement and Work Breakdown

[WORK BREAKDOWN PLACEHOLDER — see docs/group_info.md. Fill in per-member
responsibility across: lab provisioning/hardening, experiments, figures,
report writing, slides, peer review.]

| Member | Student ID | Primary contribution |
|---|---|---|
| Chirag Sethi | [ID PLACEHOLDER] | [PLACEHOLDER] |
| Shree Iyengar | [ID PLACEHOLDER] | [PLACEHOLDER] |
| Hardik Sharma | [ID PLACEHOLDER] | [PLACEHOLDER] |
| Mehul Nagarkoti | [ID PLACEHOLDER] | [PLACEHOLDER] |
