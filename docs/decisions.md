# Decision log

Autonomous decisions made while building this project, per CLAUDE.md section 9
("for everything else, decide, note the decision here, and continue").

## Phase 0

- Used the existing `/Users/chiragsethi/Downloads/OS` folder as the repository
  root directly (it already contained `CLAUDE.md` and the guide), instead of
  creating a separate `~/capstone` folder as the guide's Part A suggests.
- Did not nest the repo under an extra `capstone/` subdirectory; `CLAUDE.md`
  section 5's tree is applied directly at the repo root.
- Left the pre-existing unrelated files in this folder in place (the capstone
  brief PDF, the marking rubric PDF, and the two source `CLAUDE`/guide files
  with parenthesized download suffixes). They are not part of the generated
  deliverables.
- Generated a dedicated ed25519 keypair at `lab/.secrets/capstone_id_ed25519`
  for VM admin access, instead of using or creating `~/.ssh/id_ed25519`
  (there was no existing key on this Mac, and keeping it inside the
  gitignored project secrets folder is cleaner to reason about than a
  system-wide key).

## Phase 4/6 (E5 brute-force demo)

- The real `/admin/` Nginx basic-auth password and the `meridian_app`
  database password are randomly generated 24-character strings
  (`lab/.secrets/secrets.env`), which a small, honest, self-made wordlist
  could never guess in a reasonable demo. E5 needs to show both an
  unprotected successful guess AND a Fail2Ban-protected ban, so it cannot
  run against secrets that are uncrackable by design.
- Solution: a throwaway `bftest` SSH user and a throwaway `/admin-demo/`
  Nginx path were added (`lab/scripts/setup_e5_demo_accounts.sh`), both using
  a single deliberately weak `DEMO_WEAK_PASSWORD` that is also present in
  `lab/wordlist.txt`. The real `admin` SSH account and the real `/admin/`
  path and their credentials are never touched or exposed by this.
- These demo accounts are removed again immediately after E5
  (`lab/scripts/teardown_e5_demo_accounts.sh`), which also restores
  `PasswordAuthentication no` and `AllowUsers admin` so the rest of the
  project (and the final `make final-check` rebuild) runs against the real
  hardened configuration, not the temporarily loosened one.
- This whole arrangement, and why it does not weaken the project's actual
  security posture, is written up honestly in the report's Methodology and
  Discussion sections rather than hidden.

## Phase 1 (VM provisioning bug)

- The first two provisioning attempts both failed: `multipass launch`
  reported "timed out waiting for response" and the VM was left in state
  `Unknown` (unreachable even via `multipass exec`), despite a longer
  `--timeout 900`. Isolated the cause by testing progressively: a plain
  `multipass launch` with no cloud-init at all succeeded in ~150s; an
  otherwise-empty `#cloud-config` file also succeeded; but any cloud-init
  file containing a `users:` block (even a minimal one, with or without
  `- default` as the first list entry) hung the VM in `Unknown` state
  every time. A top-level `ssh_authorized_keys:` module (which adds a key
  to Multipass's own pre-existing default user instead of defining a new
  user) worked immediately.
- Conclusion: on this Multipass version (1.17.2, QEMU driver,
  Apple Silicon) and this Ubuntu 26.04 LTS image, the cloud-init `users:`
  module appears to interfere with Multipass's own guest-agent
  provisioning, which depends on its default account.
- Fix: `lab/cloud-init/{web,db,attacker}.yaml` no longer create a separate
  `admin` user. They add the project's SSH key to Multipass's own default
  `ubuntu` account (already a passwordless sudoer) via top-level
  `ssh_authorized_keys` instead. Every script, config, and doc that
  referred to `admin@<ip>`, `/home/admin`, or `AllowUsers admin` was
  updated to `ubuntu` to match (`lab/scripts/*.sh`,
  `lab/configs/sshd/99-capstone-hardening.conf`, `docs/viva_qa.md`,
  `docs/verification_checklist.md`, `report/report.md`).
- This is a deviation from `CLAUDE_CODE_GUIDE.md`'s literal instruction to
  "create a sudo user `admin`"; functionally equivalent (a key-only,
  passwordless-sudo account used for all administration), just under a
  different, pre-existing username. Noted here per CLAUDE.md section 9
  rather than asked about, since it is a mechanical substitution with no
  security or grading impact.

## Phase 1 (launch command hang, separate from the `users:` bug above)

- Even after the `users:` fix above, `multipass launch` itself hung
  indefinitely on the third VM. Diagnosis: all three VMs actually reached
  `Running` with an IP, and `cloud-init status --long` on each showed
  `status: done` / `extended_status: degraded done`, with the only
  recorded issue being a harmless, repeating warning: `Failed to rename
  devices: ... Error renaming mac=... from enp0s1 to eth0 [busy]`. This is
  a cosmetic NIC-naming race on this image/network combination, not a
  failure of anything we configured (all target packages were verified
  present with `dpkg -l` on all three VMs despite it). `multipass launch`
  appears to wait for a CLEAN "done" status before it will return, which
  this setup will never produce, so the command hangs forever even though
  the VM is already fully usable.
- Fix: `lab/scripts/provision.sh`'s `launch_vm` now launches each VM in the
  background and polls `multipass list` (for `Running`) and `cloud-init
  status` (for `done` or `error`, accepting "degraded") itself, then kills
  the still-hanging `multipass launch` process rather than waiting on it.
  This keeps `make lab` (and `make demo-reset`, Phase 10's rebuild)
  reliable from a cold start instead of hanging on every future relaunch.
- One git-clone step in `attacker.yaml`'s `runcmd` (cloning `testssl.sh`)
  did not run before the hang (cloud-init's package stage completed, but
  this `runcmd` step either raced the network or was never reached before
  provisioning was interrupted the first time); it was completed manually
  and `lab/scripts/provision.sh` doesn't change there, since the original
  cloud-init step is correct and this was a one-off side effect of the
  earlier hang, not a repeatable bug.

## Phase 1 (wrong testssl.sh repository)

- `attacker.yaml`'s `runcmd` and `lab/scripts/provision.sh`'s fallback both
  cloned `https://github.com/drwetter/testssl.sh.git`, which `git
  clone`/`git ls-remote` silently returns as an empty repository (no
  error, just "You appear to have cloned an empty repository"), even
  though `curl -I` against the same URL path returns a normal 200 (it's
  GitHub's web UI responding, not the git smart-HTTP backend). The actual
  maintained repository is under the `testssl` organisation, not the
  `drwetter` personal account: `https://github.com/testssl/testssl.sh.git`
  (confirmed with `git ls-remote`, which lists real branches/HEAD for the
  org URL and nothing for the personal-account URL). Fixed both places.

## Phase 1 (bash 3.2 on macOS breaks associative arrays and `${var^^}`)

- `lab/scripts/test_phase1.sh` failed with `web: unbound variable` on a
  `declare -A IPS=(["web"]=$WEB_IP ...)` line, and separately
  `lab/scripts/harden.sh`'s `${name^^}_IP` indirect-variable lookup would
  have failed the same way. Root cause: macOS ships bash 3.2 as `/bin/bash`
  (Apple stopped updating it over the GPLv3 license change), which
  predates associative arrays and `${var^^}` case conversion entirely
  (both are bash 4.0+ features); no newer bash was installed via Homebrew.
  `declare -A` on bash 3.2 does not simply error out, it mis-parses the
  subscript and throws a confusing unrelated-looking "unbound variable"
  error under `set -u`.
- Fixed by installing a modern bash (`brew install bash`, got 5.3.20),
  which Homebrew places at `/opt/homebrew/bin/bash` - already first on
  this Mac's `$PATH` ahead of `/bin/bash`, so plain `bash script.sh`
  invocations and every script's own `#!/usr/bin/env bash` shebang now
  resolve to the modern one without any script changes. Recorded here
  because it is a precondition for `make lab`/`make test` working at all
  on a machine that does not already have a non-system bash, and would be
  worth adding to Part A of the setup guide.

## Phase 1 (Multipass CLI hangs if its own output is bound straight to /dev/null)

- `lab/scripts/test_phase1.sh`'s mutual-ping check hung indefinitely (100%
  CPU on the `multipass exec` process) on every run, reproduced down to a
  single isolated command: `multipass exec web -- ping -c1 -W2 <ip>
  >/dev/null 2>&1` hangs every time, while the exact same command
  redirected to a real file, or piped through `cat >/dev/null`, returns in
  well under a second. The bug needs Multipass's own stdout bound directly
  to the `/dev/null` character device; redirecting only stderr to
  `/dev/null` while stdout goes elsewhere (a pipe or command substitution)
  does not trigger it, and it is not specific to `ping` or to `multipass
  exec` (`multipass info ... >/dev/null 2>&1` reproduces it too). The
  binding does not have to be on the `multipass` line itself: a wrapper
  that redirects a whole wrapped command to `/dev/null` and then has that
  command invoke `multipass exec` internally hangs the same way, because
  the inherited file descriptor is what matters, not which line wrote the
  redirection.
- Fixed every such case (`lab/scripts/provision.sh`,
  `lab/scripts/test_phase1.sh`, `experiments/run_E5.sh`,
  `lab/scripts/final_check.sh`'s `check()` helper) by piping through `cat
  >/dev/null` (relying on `pipefail`, already set in all of these scripts,
  to still surface the real command's exit status) or redirecting to a
  real temp file instead of `/dev/null` directly. General rule applied
  project-wide from here on: never bind a `multipass` command's own
  stdout/stderr straight to `/dev/null`, directly or by inheriting an
  ancestor's redirection; a real file or a `| cat >/dev/null` pipe is used
  instead whenever output needs discarding.

## Phase 3/4 (testssl.sh against a non-TLS port hangs; sshd restart once left the web VM unreachable)

- `harden.sh`'s original "before hardening" TLS grade ran `testssl.sh`
  against the web VM's plain HTTP port (443 did not exist yet at that
  point in the script). Observed result: it hangs indefinitely rather than
  failing - a TLS tool retrying a handshake against a port that will never
  speak TLS has no natural exit. Replaced with a simple proof that no TLS
  endpoint exists yet (`curl -sk https://<ip>/` times out/refuses); the
  real grade is only ever an "after" grade, and the report explains why
  there is no "before" grade to compare it to, rather than inventing one.
- Separately, an indirect-variable bug (`${name^^}_IP` / `${!ip_var}`)
  tried to read `$ATTACKER_IP` for the `attacker` VM, which does not
  exist - the real variable is `ATT_IP`. Fixed with an explicit `case`
  statement instead of relying on the hostname matching the env var name.
- Most seriously: after `systemctl restart ssh` on the web VM, sshd
  stopped accepting connections entirely (`nc -z <ip> 22` got an immediate
  refusal, confirmed with `ping` and `nc` to ports 80/443 still working
  fine from the Mac - only port 22 was affected). This also broke
  Multipass's own control channel (`multipass info web`, `multipass exec
  web`, even `multipass restart web`, all failed with "ssh connection
  failed: Connection refused"), which means `multipass exec` is NOT
  independent of the guest's own sshd on this setup, contradicting
  `CLAUDE_CODE_GUIDE.md`'s Part E troubleshooting table ("multipass exec
  ... always works, even with SSH disabled"). `db` and `attacker` got the
  identical hardening in the same run and were unaffected, so this reads
  as a one-off failure of that specific `systemctl restart ssh` rather
  than a config error repeated on every VM.
- Recovery that worked, in order tried: `multipass restart web` (also
  fails, since it too depends on the SSH channel) did not help;
  `multipass stop web` followed by `multipass start web` did - this uses
  the hypervisor-level control path (visible in the running `qemu-system-
  aarch64` process), not a guest SSH session, so it works even when sshd
  itself is wedged. `harden.sh`'s SSH-hardening step now checks
  `systemctl is-active ssh` after each restart, retries the restart a
  couple of times, and falls back to a `multipass stop && start` cycle
  automatically if sshd still is not answering, instead of silently
  leaving a VM unreachable for the rest of the pipeline.
- Root cause found after it recurred a second time (during the Fail2Ban
  step, unrelated to sshd at all): `journalctl -b -1` on the web VM showed
  a completely orderly `systemd` shutdown sequence ending in
  `unattended-upgrades.service: ... Stopped unattended-upgrades.service -
  Unattended Upgrades Shutdown` and `Reached target poweroff.target`. This
  was never a crash, hang, or misconfiguration of anything we deployed -
  Ubuntu's `unattended-upgrades` package rebooted the VM on its own
  schedule, mid-provisioning, with no warning. This can happen to any of
  the three VMs at any time, including during a benchmark run or the live
  demo, which would be far worse than during Phase 4.
- Fixed in two places: applied live to all three already-running VMs
  (`systemctl disable unattended-upgrades.service apt-daily-upgrade.timer
  apt-daily.timer`, plus `APT::Periodic::Enable "0"` and
  `Unattended-Upgrade::Automatic-Reboot "false"` in
  `/etc/apt/apt.conf.d/52-capstone-no-auto-updates`), and added to every
  `lab/cloud-init/*.yaml`'s `runcmd` and to `lab/scripts/provision.sh`
  (new script: `lab/configs/systemd/disable-auto-updates.sh`), so a fresh
  launch or a re-run against existing VMs both get it, not just the VMs
  that happened to be running when this was found. Disabling background
  auto-updates entirely is deliberate and reasonable for a disposable lab
  whose package set we fully control and script ourselves; the trade-off
  (no automatic security patches) is a non-issue for a short-lived
  teaching environment with no real external exposure.
- The `clean-baseline` snapshots taken at the end of Phase 1 predate this
  fix, so `lab/scripts/demo_reset.sh` (which restores those snapshots)
  will re-apply Phases 2-5 on top of a restored snapshot that still has
  unattended-upgrades enabled; a fresh `clean-baseline` snapshot should be
  retaken once Phase 4 is finalised so the demo-reset path also starts
  from the patched state, and this is tracked as a to-do rather than
  silently assumed.

## Phase 1/3/4 (recurring: `multipass stop` + `start` sometimes wedges a VM at the hypervisor level, not just the guest)

- Beyond the sshd-specific wedge above, `web` and later `db` each hit a
  second, different failure: after a `multipass stop`/`start` cycle (the
  one `clean-baseline` snapshotting itself requires - `multipass snapshot
  --help` confirms it only works on a stopped instance, so this cannot be
  avoided by snapshotting live), the instance stayed in `multipass list`
  state `Unknown` indefinitely. Checked whether this was "just a slow
  boot" by watching the instance's own `qemu-system-aarch64` process's
  accumulated CPU time across several minutes: it stayed essentially flat
  (around 15 seconds of CPU total, unchanged over 3+ minutes of wall
  clock), which is not consistent with an actual Linux boot in progress
  (that consumes CPU continuously for at least the first 30-60 seconds) -
  this is a genuine hypervisor-level stall, not a slow or hung guest OS.
- `multipass restart` does not help (same class of failure as the
  SSH-dependent commands above). The only recovery found: `multipass
  delete <name> --purge` followed by a fresh `multipass launch` (via
  `lab/scripts/provision.sh`, which already skips VMs that still exist and
  launches only the missing one). This loses that VM's disk state, so
  Phase 2 (site/app/db) and Phase 3/4 (TLS/hardening) have to be redone
  for a VM rebuilt this way - costly, but faster than continuing to wait
  on a wedge that polling alone does not resolve.
- `lab/scripts/provision.sh`'s snapshot step was hardened in response:
  it now skips re-snapshotting an instance that already has a
  `clean-baseline` snapshot (`multipass info` reports it; re-running
  `multipass snapshot` on top of the Unknown-state churn this bug causes
  was itself making things worse), uses the same poll-based
  `wait_for_running` helper as `launch_vm` instead of trusting `multipass
  start`'s own wait, and pipes every `multipass stop`/`snapshot`/`start`
  call through `cat >/dev/null` rather than discarding output directly
  (the already-documented /dev/null-hang rule, applied here too since
  these commands were not originally thought to be at risk).
- This is recorded honestly as a genuine limitation of the lab platform on
  this host (report Section 5.3, Challenges and Edge Cases) rather than
  hidden: Multipass's QEMU driver on this Apple Silicon Mac is not fully
  reliable across repeated stop/start cycles, independent of anything
  this project configured inside the guests.
- Separately, a real scripting bug compounded this: `provision.sh`'s
  polling loop read `state=$(multipass info "$name" ...)` with no `||
  true` guard; a single transient nonzero exit from `multipass info`
  while an instance's state was still changing silently killed the whole
  script under `set -e`, with no error message (observed: the script
  printed "[web] launching..." and then simply exited 0). Fixed by adding
  `|| true` to that assignment - the loop already checks the resulting
  `$state` string directly afterward, so a transient empty read just
  means one more polling iteration, not a crash.

## Phase 1 (`pipefail` masked a successful grep match behind an unrelated nonzero exit code)

- `provision.sh`'s cloud-init-terminal-state loop was observed to always
  burn its full 300-second wait, on every VM, every time, even though
  `multipass exec "$name" -- cloud-init status` was confirmed (checked
  directly) to print `status: done` well within a few seconds. Root
  cause: `cloud-init status` itself exits with status 2 for "degraded
  done" (its own documented behaviour, not a bug), and this image's
  cloud-init always ends up "degraded" because of the harmless NIC-rename
  race already documented above. The loop was written as `if multipass
  exec ... | grep -qE "status: (done|error)"; then break; fi` - under
  `pipefail` (set at the top of this script), a pipeline's reported exit
  status is "the last command to exit non-zero," which is `multipass
  exec`'s 2, not `grep`'s 0, even when `grep` genuinely matched. So the
  `if` was always false regardless of the real cloud-init state, and the
  loop only ever exited via its own 300s timeout, not via detecting
  success.
- The identical shape of bug was found by inspection in
  `lab/scripts/test_phase3.sh`'s two `openssl s_client | grep -q` checks:
  `openssl s_client` exits non-zero on a rejected handshake, which is the
  EXPECTED, correct outcome for the TLS 1.1 check, so the same
  pipefail-vs-grep masking would have made that check report FAIL even
  when TLS 1.1 was correctly rejected.
- Fixed both by capturing the command's output into a variable first
  (`output=$(cmd || true)`) and then running `grep` against the variable
  as a separate statement, so `grep`'s own exit status is what the `if`
  sees, completely decoupled from the inner command's unrelated exit
  code. General rule added alongside the existing "never redirect
  multipass output straight to /dev/null" one: never pipe a `multipass`
  (or any command whose own exit code is not a reliable proxy for "did
  grep find what we wanted") call directly into `grep -q` under
  `pipefail` - capture to a variable first.

## Phase 3/4 (the recurring Fail2Ban-step wedge is a short, self-clearing blip, not another hypervisor stall)

- After fixing unattended-upgrades, the exact same "ssh connection failed:
  Connection refused" still recurred at the exact same point - right at
  the Fail2Ban deployment step - on a second full run. This time, instead
  of assuming another permanent wedge, polled raw TCP port 22 directly
  with `nc` every 10 seconds (bypassing Multipass entirely) while leaving
  the VM alone: it recovered on its own within about 10 seconds, with the
  VM's own `qemu-system-aarch64` process's CPU time still climbing
  normally throughout (unlike the earlier genuine hypervisor stalls, where
  CPU time stayed flat for many minutes). So this is a short, self-healing
  disruption - most likely a brief window around a firewall-reloading
  step (`ufw` right before it, `fail2ban` enabling/reloading its own
  jails) where sshd or the port briefly stops accepting new connections -
  not the same failure mode as the stop/start hypervisor wedge documented
  above, and does not need a VM rebuild.
- Fixed with a short retry instead of a VM restart: `harden.sh` now has an
  `mp_retry()` helper (up to 6 attempts, 10s apart) wrapping the
  Fail2Ban-deployment `multipass transfer`/`exec` calls and the
  directory-listing-proof step right after, so a single bad-timing window
  no longer aborts the whole script under `set -e`.

## Phase 5 (host memory pressure returned; stale /etc/hosts entries after a VM rebuild; monitor script missing a DB client)

- The SSH blip above recurred far more persistently during
  `setup_monitoring.sh` - every single call, for several minutes straight,
  not the ~10-30s seen before. Checked `vm_stat`/`top` again: free memory
  had dropped back to ~76MB (from ~157MB after the user closed some apps
  earlier), confirming this is genuinely host memory pressure recurring
  with normal Mac usage, not a one-off. Raised `mp_retry`'s budget from 6
  attempts (max ~1 minute) to 15 (max ~2.5 minutes) in both `harden.sh`
  and `setup_monitoring.sh` to ride out longer pressure spells, rather
  than treating every occurrence as a VM to rebuild.
- `test_phase5.sh` had the same unguarded-`multipass exec` problem (no
  `mp_retry`), which is why the Phase 5 acceptance check itself failed
  with exit code 2 even though the actual resilience behaviour being
  tested (monitor detects nginx down, restarts it) had already passed and
  logged correctly - the failure was purely in capturing evidence
  afterward. Added the same `mp_retry` helper and wrapped the nginx-stop,
  log-tail, and `logrotate -f` calls.
- Found a real, unrelated bug while investigating: the monitor log showed
  `db_reachable=no` on every run. `lab/configs/systemd/monitor_on_web.sh`
  calls `mysqladmin ping -h db`, but `mariadb-client` (which provides
  `mysqladmin`) was never in `web`'s package list - only `db` needs the
  server, but `web` needs the *client* to check it. Added
  `mariadb-client` to `lab/cloud-init/web.yaml` and installed it live on
  the running VM. Once installed, `mysqladmin ping` still failed with a
  TLS error (`self-signed certificate`) because MariaDB now defaults to
  requiring TLS and the client doesn't trust its self-signed cert; added
  `--skip-ssl` (this health check only needs to confirm network/protocol
  reachability, not authenticate as a real app user - app traffic to
  MariaDB was never intended to be TLS-secured in this design, which
  relies on `ufw` + `bind-address` instead, per report Section 3.1).
- Found a second real bug in the same investigation: `/etc/hosts` on all
  three VMs had TWO entries for `db` - the stale `192.168.252.10` from
  before its hypervisor-stall rebuild, alongside the correct current
  `192.168.252.14`. `ensure_hosts.sh.template`'s `grep -qxF "$line" ||
  append` logic only skips adding a line that's an *exact* match; it does
  nothing to remove a now-wrong line for the same hostname at a different
  IP, which is exactly what a VM rebuild produces. Fixed to upsert: delete
  any existing line ending in that hostname first, then append the
  current one. Redeployed live to all three VMs (confirmed clean,
  one line per hostname) and the template fix applies to future rebuilds
  automatically via `provision.sh`.
- Found a third real bug while verifying `logrotate -f` actually produced
  rotated files (it had not - `test_phase5.sh`'s check for `*.gz` was
  simply never finding anything): `logrotate -vf` reported `error:
  Ignoring /etc/logrotate.d/capstone because the file owner is wrong
  (should be root or user with uid 0)`. `multipass transfer` always
  writes as the `ubuntu` user; `setup_monitoring.sh` then did `sudo mv`
  into `/etc/logrotate.d/`, which moves the file but does not change its
  ownership, so our config sat there owned by `ubuntu` and logrotate
  silently refused to load it at all. Fixed by adding `chown root:root`
  after the `mv`.
- With ownership fixed, nginx's logs rotated but `web_status.log`
  specifically still did not, with a second, different logrotate error:
  `skipping "/var/log/web_status.log" because parent directory has
  insecure permissions (It's world writable or writable by group which is
  not "root")`. `/var/log` itself is `drwxrwxr-x root:syslog` (normal
  Ubuntu default); nginx's logs live under the separate `/var/log/nginx/`
  subdirectory so this never applies to them, but `web_status.log` sits
  directly in `/var/log`, and logrotate's security hardening refuses to
  rotate a file there unless the config explicitly states which
  user/group it trusts. Fixed by adding `su root root` to that one
  stanza in `lab/configs/logrotate/capstone`, exactly as logrotate's own
  error message suggests.
- Also note for anyone re-reading this later: a single `logrotate -f` run
  produces `name.1` (or `name.1.gz` only without `delaycompress`), never
  `name.1.gz` on the FIRST forced rotation when `delaycompress` is set
  (ours is, deliberately, per the Phase 5 design) - compression is
  deferred to the NEXT rotation cycle by definition. `test_phase5.sh`'s
  evidence-gathering `ls` was originally written expecting `*.gz` and
  would show nothing from one forced run regardless of whether rotation
  actually worked; it now also lists `*.log.1*` so a passing rotation is
  visible immediately without waiting for a second cycle.

## Phase 6 (E1 could never reach the Apache baseline: ufw never opened 8080)

- E1's Apache runs all failed with `wrk`'s own "Connection timed out"
  against `http://<web>:8080/` - which looks identical to a hung
  connection and took a full TCP-connect-timeout per attempt, so wrapped
  in `mp_retry` it looked like the host-memory-pressure blip (stuck for
  15+ minutes on what should be a 15-second test) rather than a fast,
  clear failure. Checked directly: Apache was running and answered fine
  from `web`'s own loopback (`curl http://127.0.0.1:8080/` worked), so
  the problem was never Apache - it was `ufw`, which (correctly, by
  design) only allows 22/80/443 and silently drops everything else by
  default, including 8080 from the attacker VM. A dropped (not rejected)
  packet is exactly what produces a client-side connect timeout instead
  of an instant refusal, which is why this looked like the unrelated SSH
  blip at first glance.
- This was always going to happen the first time E1 actually ran:
  Phase 4 commits to exactly 3 open ports as the *hardened* state (and
  `test_phase4.sh` asserts exactly that), so 8080 was never going to be
  open permanently - the benchmark design in CLAUDE.md section 6 needs
  Apache reachable from `attacker` for E1/E2/E3, and nothing in Phase 4
  or the experiment scripts had ever actually opened a path for that
  traffic.
- Fixed in `lab/scripts/enable_apache_baseline.sh`, which already toggles
  the `apache2` service on/off around each benchmark run: it now also adds
  (`on`) / removes (`off`) a `ufw allow from <attacker IP> to any port
  8080 proto tcp` rule scoped to just the attacker VM, so the permanent,
  audited state is still exactly 3 ports whenever Apache is stopped (which
  is most of the time - only open during an active benchmark window) and
  nmap run after Phase 4 or after the full experiment suite both still
  see only 22/80/443, matching the design objective.
- One scripting trap avoided while fixing this: `enable_apache_baseline.sh
  off` is called once in `run_E1.sh` *before* `on` has ever run (a
  clean-state reset), so the `ufw delete` in that path will legitimately
  find nothing to delete the first time. Wrapping that specific call in
  the same strict `mp_retry` as everything else would have burned its
  whole retry budget (~2.5 minutes) on an expected no-op, not a real
  connectivity failure; it runs once, un-retried, with `|| true` instead.

## Phase 6 (E1's cpu_pct column showed impossible values over 1000%)

- The first real E1 run produced `cpu_pct` values like 1903.9 and 1541.8
  in `evidence/processed/E1.csv` - impossible on a 2-core VM (max 200%
  summed). `parse_E1.py`'s regex for the `pidstat -u -r` output only
  required 3 trailing decimal fields after the captured number before
  accepting a match, which is enough to match the `-u` table's row
  (`time uid pid %usr %system %guest %wait %CPU CPUid Command`, capturing
  %usr instead of %CPU) but *also* the completely different `-r` memory
  table's row for the same PID (`time uid pid minflt/s majflt/s VSZ RSS
  %MEM Command`), whose `minflt/s` (page faults/sec, routinely in the
  thousands) got averaged in alongside real 0-100 %CPU numbers.
- Fixed by requiring the exact column count of the `-u` table (4 skipped
  decimals, the captured %CPU as the 5th, then the integer CPU-core-id,
  then the literal process name anchored to end of line), which the `-r`
  table's row shape can never satisfy. Re-parsed the already-captured
  `evidence/raw/E1_*.txt` with `python3 experiments/parse_E1.py` (no need
  to re-run the real wrk/pidstat experiment itself) and confirmed
  `cpu_pct` now sits in the sane 0-100 range.

## Phase 6 (E5's SSH brute-force never actually ran: a drop-in filename ordering conflict)

- E5's SSH hydra run failed identically on every one of `mp_retry`'s 15
  attempts with `[ERROR] target ssh://<web>:22/ does not support password
  authentication (method reply 4)` - a real, consistent server-side
  refusal, not a connectivity blip, so `mp_retry` just burned its whole
  budget re-running hydra from scratch 15 times against a server that was
  never going to accept a password login. This is the exact
  failure-mode-to-watch-for noted when `mp_retry` was added: it treats
  "the command returned nonzero" as retriable, but cannot tell a genuine,
  repeatable logic bug apart from a transient one - only a human (or very
  specific error-matching) can.
- Root cause: `setup_e5_demo_accounts.sh` edits
  `/etc/ssh/sshd_config.d/99-capstone-hardening.conf` to flip
  `PasswordAuthentication no` to `yes` for the demo, but
  `sshd -T` showed the effective value was still `no`. Ubuntu's own
  `/etc/ssh/sshd_config.d/60-cloudimg-settings.conf` (shipped by the
  cloud image, not by us) already sets `PasswordAuthentication no`, and
  OpenSSH applies the FIRST occurrence of a directive across
  `Include`-d files in glob order - `60-...` sorts before `99-...`, so
  our file's setting was silently never applied at all, for either the
  real hardened "no" (harmless, since both files agreed there) or the
  demo's "yes" (not harmless - this is what broke E5).
- Fixed by renaming our drop-in from `99-capstone-hardening.conf` to
  `10-capstone-hardening.conf` (sorts before `60-...`), so OUR file's
  directives are always the ones OpenSSH honours, for every value we set
  there, not just the ones that happened to agree with Ubuntu's default.
  Applied live (moved the file, `sshd -t`, `systemctl restart ssh`,
  confirmed `sshd -T` now reports `passwordauthentication yes` during the
  demo window) and updated `lab/scripts/harden.sh`,
  `setup_e5_demo_accounts.sh`, and `teardown_e5_demo_accounts.sh`'s
  filename references for future runs.
- This also means every earlier Phase 4 "SSH hardening" run technically
  never exercised our own `PasswordAuthentication no` setting at all -
  it happened to be correct only because Ubuntu's own default already
  matched it. Worth a line in the report's Discussion: the hardening was
  never actually *tested* for that one directive until this bug surfaced.

## Phase 6 (E6's "without limit_req" scenario was not actually unlimited)

- The first real E6 run showed 503s in BOTH the "with" and "without
  limit_req" scenarios, and zero 429s in either - not the expected
  "mostly 429 with limiting, mostly 200 without" contrast. Cause: the
  `/api/` location has two independent rate-control directives,
  `limit_req` (requests/sec, returns 429 when exceeded) and `limit_conn`
  (concurrent connections per source IP, returns 503 when exceeded).
  `run_E6.sh` only toggled `limit_req`; `limit_conn conn_zone 20` stayed
  active throughout, and `wrk -t4 -c200` opens 200 concurrent connections
  from the single attacker IP - comfortably over that cap regardless of
  `limit_req`'s state, so both runs hit the same `limit_conn` ceiling and
  the comparison never actually reached an unlimited baseline.
- The clean re-run's "without" scenario (both directives genuinely
  disabled this time) still measured a suspiciously low 391 req/s;
  `wrk`'s own output explained it directly: "Socket errors: connect 0,
  read 0, write 0, timeout 111" out of a 20-second run - real network
  timeouts between the VMs, not a config problem (nginx reloaded cleanly,
  no errors), and consistent with the same sustained host memory pressure
  documented elsewhere in this file that was also producing persistent
  SSH connection-refused blips around this same time. `make bench`'s full
  5-repeat run (not just this `--quick` 1-repeat smoke test) should
  average this kind of noise out; flagged here so the report's Discussion
  of threats to validity cites this concrete instance rather than a
  general disclaimer.
- Fixed by having `run_E6.sh` disable and restore `limit_conn` alongside
  `limit_req` for the "without" scenario, so that run is genuinely
  unthrottled and the contrast with "with" (both directives active, the
  real hardened state) is the one the report should discuss. Needs a
  clean re-run once E7-E9 finish (not restarted mid-stream, to avoid
  racing the background experiment run already using the old script).

## Phase 6 (E8: systemd's own Restart=on-failure won the race against our monitor's 30s poll)

- Across two separate E8 runs, `evidence/processed/E8.csv` showed
  `monitor_logged_down=False, monitor_logged_restarted=False,
  detected_active_again_after_seconds` empty - the monitor's own log
  (`/var/log/web_status.log`) never contained a single "DOWN" or
  "RESTARTED" line from either run, despite nginx genuinely having been
  SIGKILLed (`mp_retry` confirmed the kill command itself succeeded, no
  "giving up" message) and genuinely having come back (`systemctl show
  nginx -p NRestarts,ActiveEnterTimestamp` showed `NRestarts=2` and a
  start time ~33 seconds after the recorded `kill_time_utc`).
- This is not a parsing or detection bug: it is systemd's own
  `Restart=on-failure` drop-in (deployed in Phase 5 alongside the custom
  monitor, as a second, faster line of defence) recovering the service on
  its own, independently of and faster than our monitor script's 30-second
  polling interval can observe. By the time the monitor's next scheduled
  run checks `systemctl is-active nginx`, systemd has typically already
  restarted it, so the monitor only ever logs "UP" - it is never polling
  at the moment the service is actually down. The ~33s gap (slower than
  the `RestartSec=2` configured in the drop-in) is itself consistent with
  the host memory pressure documented elsewhere in this file: even a
  normally-fast systemd restart ran slower than configured under load.
- Decided not to force a different test method (e.g. temporarily
  disabling the systemd `Restart=on-failure` drop-in so only the custom
  monitor can perform the recovery) given the time already spent on this
  phase; this is recorded as an honest, reportable finding rather than
  hidden or faked. It is good material for the report's Discussion
  (Section 5.3, "Challenges and Edge Cases" / 5.2 "Comparison with
  Baselines"): the project has two independent resilience layers, and
  this experiment shows the faster one (systemd) working so well that it
  pre-empted observing the slower, more informative one (the custom
  monitor) in action. `logrotate_produced_gz=True` in the same CSV is
  real too, but is evidence of an EARLIER test_phase5.sh forced rotation
  still present on disk, not of this particular E8 run (a single forced
  rotation under `delaycompress` produces `.log.1`, not `.gz`, on its
  first cycle - documented in an earlier Phase 5 entry above).

## Phase 6 (final quick-mode regeneration: web VM clock freeze, oversized
leftover logs, and a manual, clock-independent re-measurement of E8)

- While regenerating the final quick-mode E1-E9 dataset, the web VM (and,
  it turned out, attacker and db too) came back from a multi-day gap
  between sessions with its system clock frozen ~36 hours behind real
  time (`timedatectl` showed `System clock synchronized: no`; the VM's
  own `date -u` read `2026-11-21T14:45Z` while the host read
  `2026-11-23T03:17Z`). All three VMs froze at essentially the same
  instant, consistent with the host Mac sleeping between sessions and
  the guests never getting an NTP step on resume (these VMs have no
  internet egress, so `systemd-timesyncd` reports `NTP service: active`
  but can never actually reach a server to correct it).
- This explains why E8's detection loop (and `capstone-monitor.timer`'s
  own logging) produced an empty/useless result on the first regeneration
  run that day: `tail -n 15 /var/log/web_status.log` kept returning
  stale Nov-21 content, and the 70s polling window saw nothing new.
- Fixed by running `sudo hwclock --hctosys` on all three VMs (the
  hardware clock, backed by the host, was correct throughout - only the
  guest's running system clock had frozen). This is a one-line fix but
  does NOT itself notify already-running systemd timers of the jump:
  `capstone-monitor.timer` kept its pre-jump "next elapse" calculation
  and was observed stuck mid-countdown (`Trigger: ...; 28s left` while
  real time was already 16 minutes past that point). A
  `systemctl restart capstone-monitor.timer` fixed it only briefly before
  it froze again a few minutes later on a second, independent occasion -
  i.e. two different fixes were tried and neither held, which is this
  project's own threshold (CLAUDE.md section 9) for stopping to ask
  rather than continuing to chase it live. Asked the user; decision was
  to accept a manual, clock-independent measurement for E8 rather than
  keep re-running the automated script against unreliable guest-clock
  state. Logged here as a known limitation of this lab environment
  (airgapped VMs + long inter-session gaps can desync the guest clock in
  a way that a single `hwclock` sync does not durably fix), not as a bug
  in the hardening or monitoring design itself.
- Separately, the same session found ~1.7GB of leftover, uncompressed
  `access.log.1` / `error.log.1` files on web (dated from the earlier,
  user-aborted full 5-repeat benchmark run that spiked host load to
  210 - see the quick-mode-vs-full-run decision elsewhere in this log).
  These were pure disk bloat from an already-abandoned run, not
  meaningful evidence; deleted them, which dropped web's disk usage from
  59% to 39% and measurably reduced subsequent SSH flakiness, suggesting
  disk I/O pressure from that oversized log was itself a contributing
  factor to the VM's general unresponsiveness that day (on top of the
  clock issue).
- `evidence/processed/E8.csv` for the final dataset is therefore NOT the
  output of `parse_E8.py` run against an automated `run_E8.sh` pass (both
  attempts that day were defeated by the clock/connectivity issue).
  Instead it was measured directly: `sudo systemctl kill -s SIGKILL
  nginx` issued with a host-side timestamp, then `systemctl is-active
  nginx` polled from the host every 3 seconds - a method immune to the
  guest clock being wrong, since it never reads a VM-side timestamp.
  Result: nginx recovered in 3 seconds (systemd's `Restart=on-failure`,
  consistent with the sub-minute recovery already established in the
  entry above). A forced `logrotate -f` was likewise run and manually
  confirmed to produce a fresh `web_status.log.2.gz` - which also
  surfaced a real, separate bug in `run_E8.sh`: its own final evidence
  `ls` glob is `*.log.1*`, which can never match a `.2.gz` file, so the
  automated script could never have shown `logrotate_produced_gz=True`
  even on a perfectly clean run. `monitor_logged_down`/
  `monitor_logged_restarted` are honestly recorded as unverified this
  run (not as False-meaning-broken) since `capstone-monitor.timer`'s
  stall during the test window prevented capturing it either way -
  `evidence/processed/Ex_notes.md` carries the full explanation for the
  report.

## Phase 6/8 (external accuracy review: Fail2Ban's real root cause, 429
status codes, E1/E2's port-80 bug, E7's dissector artifact, a VM rebuild)

- A thorough external review of the drafted report against its own
  evidence found several real problems, each verified against raw logs
  before accepting the review's claim and fixing it:
  - **Fail2Ban's actual root cause was a backend mismatch, not a regex
    mismatch.** The earlier entry above (Phase 6, E5/nginx-http-auth)
    guessed "a mismatch between the jail's regex and the actual log
    line." Direct testing showed otherwise: `jail.local`'s `[DEFAULT]`
    sets `backend = systemd`, inherited by `nginx-http-auth` and
    `nginx-limit-req`; that backend reads the *systemd journal* via a
    `journalmatch`, not the `logpath` file. Nginx never writes
    per-request errors (including failed basic-auth attempts) to the
    journal - only its master process's own startup/shutdown notices
    reach it (confirmed: `journalctl _COMM=nginx` shows only "signal
    process started"-type lines). `fail2ban-client get nginx-http-auth
    logpath` reported **"No file is currently monitored"** - direct proof
    the jail was reading nothing - while the same test confirmed Nginx's
    `error.log` *did* contain the exact line the filter's regex expects.
    The regex was never the problem. Fixed by overriding both jails to
    `backend = auto` (tails the file directly); a manual wrong-password
    test immediately showed `Total failed` incrementing and a real ban,
    then the real brute-force attack (E5) was re-run and both jails
    (SSH and Nginx basic-auth) banned the attacker before a credential
    was found - the opposite of the original result.
  - **Nginx's `limit_req`/`limit_conn` default to HTTP 503**; RFC 6585's
    429 ("Too Many Requests") is the correct code for rate limiting.
    Added `limit_req_status 429;`/`limit_conn_status 429;` to the
    hardened config, verified live with a burst test (429s then 200s),
    then re-ran E6.
  - **Fixing the `nginx-limit-req` jail created a new, real interaction**:
    E6's own flood deliberately exceeds the rate limit, which now (jail
    actually reading its log) legitimately bans the attacker mid-flood -
    first discovered when the WITH-limiter wrk run returned "0 requests"
    (connections hanging against a silent ufw DROP) and the follow-up
    curl sample returned 504s. A second attempt added mid-script unban
    calls, but the ban re-triggered faster than the flood completed. The
    working fix: Fail2Ban's own `ignoreip` mechanism, adding the
    attacker's IP to just the `nginx-limit-req` jail's ignore list for
    just the duration of the deliberate WITH-limiter flood, removing it
    after. A third attempt still saw a stray re-ban: Fail2Ban's
    file-polling backend was still processing a backlog of tens of
    thousands of matching log lines *after* the ignoreip entry was
    removed, banning retroactively for violations that happened while
    whitelisted. Fixed with a `sleep 15` before removing the ignoreip
    entry, letting the backlog drain first. Confirmed clean on the next
    run: `with_limit_req` showed real throughput and a realistic 429/200
    mix, `without_limit_req` showed the already-known 504-dominated
    overload pattern, and the jail's `ignoreip` list and ban state were
    both empty afterward.
  - **E1 and E2 were benchmarking Nginx's own 301 redirect, not real
    content.** `run_E1.sh`/`run_E2.sh` tested "nginx" on port 80, but
    port 80 unconditionally redirects to HTTPS - confirmed directly by
    bytes-per-request math: the "nginx" run moved ~336 bytes/request
    (matching a 301's `Content-Length: 162` plus headers exactly), while
    Apache's same-test run on port 8080 moved ~1978 bytes/request (the
    real ~1.8KB homepage). This invalidated the headline Nginx-vs-Apache
    comparison and the HTTP-vs-HTTPS transport-cost comparison, both of
    which had been reported as valid findings. Fixed with a new template,
    `lab/configs/nginx/meridian-plainhttp.conf.template` (port 80 serves
    the real site directly, same TLS/443 block as the real hardened
    config), swapped in only for the duration of these two benchmarks
    and swapped back immediately after (same backup/restore pattern
    already used by `run_E7.sh`'s plaintext capture). Re-run and
    reconfirmed against the same byte-per-request check (~2,050-2,060
    bytes on both sides this time, matching the real page). The
    corrected numbers are a real but much more modest Nginx advantage
    (e.g. at c=200: Nginx 34,875 req/s vs Apache 13,708 req/s with
    ~88,500 failed requests/run, vs the old invalid 57,990 vs 10,860).
  - **E7's HTTPS capture looked like it had missed the actual
    application-data exchange** - extracting `tls.record.content_type`
    via `tshark -T fields` showed only handshake-phase values (22, 20),
    never 23 (Application Data), across multiple re-runs with longer
    capture windows (which didn't help, confirming it wasn't a timing
    issue). Root cause found by inspecting the same frames directly
    (`tshark -Y "frame.number==N"`): they were correctly labelled
    `"TLSv1.3 ... Application Data"` (sometimes several per frame) in
    Wireshark's own summary - the dissector simply doesn't always
    populate that one per-record field once a stream is fully encrypted,
    even though it identifies the content correctly. Fixed by reading
    `tshark`'s default packet summary instead of extracting that field;
    the corrected capture shows the full exchange end to end (TCP
    handshake, TLS 1.3 Client/Server Hello, then 42 frames labelled
    Application Data), finally substantiating the "HTTPS is opaque"
    claim the experiment was designed to make.
  - **Other reporting-only fixes** (no new data needed): E9's TLS grade
    cap reason was guessed ("HTTP-01-style self-signed CA", a confused
    reference to an ACME challenge type) rather than read from
    `testssl.sh`'s own output, which states verbatim "Grade capped to B.
    Issues with chain of trust (chain incomplete)" - now quoted directly.
    An unverifiable "~33 seconds" claim about an earlier monitor-script
    detection, not backed by any CSV, was removed from the report body
    (it remains, correctly sourced, in this decisions log's Phase 6
    entry on E8). Appendix B's browser screenshots were mislabelled as
    showing a "CA imported as trusted" state; all five actually show
    Chrome's own untrusted-connection warning (with its banner manually
    dismissed for convenience in two of them) - renamed
    `cert_trusted_*` to `cert_details_*` and recaptioned accurately,
    and the false claim in Section 3.1 that the project demonstrates
    both a trusted and an untrusted browser state was corrected.
- **A hypervisor-level stall of the web VM required a full rebuild**
  mid-session, unrelated to the above: the web VM's QEMU process stopped
  advancing (CPU time flat for several minutes while `attacker`/`db`
  stayed healthy and host load stayed low - the established signature of
  a genuine stall, not the VM's own recurring short SSH-connectivity
  blips). `multipass delete web --purge` followed by a fresh
  `multipass launch` failed twice in a row with "timed out waiting for
  response" during the VM's own start phase; the user restarted the
  `multipassd` host daemon (`sudo launchctl kickstart -k
  system/com.canonical.multipassd`), after which the same launch command
  succeeded normally. The rebuilt VM got a new IP (192.168.252.17, not
  .12), requiring `lab/.env` to be refreshed via `provision.sh` (which
  also completes the rest of first-time setup it would otherwise have
  skipped) before `deploy_site.sh`/`harden.sh`/`setup_monitoring.sh`
  could run; since `lab/configs/`'s source files already had the day's
  Fail2Ban-backend and 429-status fixes applied, the rebuilt VM came up
  with both already correct, confirmed directly before re-running any
  experiments.
- E1/E2/E5/E6/E7's corrected results, and the report prose referencing
  them (Sections 4.1, 4.2, 4.5, 4.6, 4.7, 5.1, 5.2, 5.3, Executive
  Summary, Conclusion, Recommendations), were all updated together in
  the same pass so no stale number or claim was left alongside the
  fix that superseded it; `docs/viva_qa.md` and `slides/build_deck.py`
  were updated the same way. The report's main body was also
  restructured to meet a 10-15 page target: all 14 data figures (F1-F14,
  previously embedded inline in Sections 3-4) were moved to a new
  Appendix C, with in-text "(Appendix C)" pointers in their place, and
  several redundant forced `\newpage` breaks between main-body sections
  were removed (main body: ~27 pages before, 14 after - all from
  relocating figures and trimming forced blank space, not from cutting
  substance).
