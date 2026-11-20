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
