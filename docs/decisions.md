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
