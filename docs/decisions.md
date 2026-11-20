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
