"""Parse the newest run_E5.sh raw log into evidence/processed/E5.csv:
attempts-before-success (unprotected) and time-to-ban (protected), per target."""
import csv
import re
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from parse_common import PROCESSED_DIR, append_note, latest_raw  # noqa: E402

OUT_CSV = PROCESSED_DIR / "E5.csv"


def count_attempts(body):
    # Hydra was run with default verbosity (no -v/-V), so it never prints
    # a per-attempt line - there is nothing like "[ATTEMPT]" to count in
    # its output, honestly 0 against this raw log. Fail2Ban's own
    # "Total failed" count (captured separately, see ban_sshd/ban_nginx
    # below) is the real per-scenario attempt count for the *_protected
    # rows; it is folded into those two rows directly in main(), not here.
    return 0


def found_login(body):
    # Real hydra output has an extra "misc: ..." field between host and
    # login for both the ssh and http-get modules (e.g. "host: <ip>
    # misc: (null)   login: bftest   password: Summer2026!"), which the
    # original pattern did not account for, so it never matched at all
    # despite hydra genuinely finding and printing the credential.
    m = re.search(r"\[\d+\]\[\S+\] host: \S+(?:\s+misc: \S+)?\s+login: (\S+)\s+password: (\S+)", body)
    return m.group(2) if m else None


def main():
    raw_path = latest_raw("E5")
    text = raw_path.read_text()

    sections = {
        "ssh_unprotected": r"--- hydra vs SSH \(bftest\), unprotected ---\n(.*?)elapsed_seconds=(\d+)",
        "nginx_unprotected": r"--- hydra vs Nginx basic-auth demo path, unprotected ---\n(.*?)elapsed_seconds=(\d+)",
        "ssh_protected": r"--- hydra vs SSH \(bftest\), protected.*?---\n(.*?)elapsed_seconds=(\d+)",
        "nginx_protected": r"--- hydra vs Nginx basic-auth demo path, protected.*?---\n(.*?)elapsed_seconds=(\d+)",
    }

    # Terminated by the next "--- ...  ---" section marker (or end of
    # file), not a blank line: hydra's own banner output contains blank
    # lines, so a "\n\n" terminator matched far past the intended block
    # and swallowed unrelated later sections into the captured text.
    ban_sshd = re.search(r"fail2ban sshd status after attack ---\n(.*?)(?=\n--- |\Z)", text, re.S)
    ban_nginx = re.search(r"fail2ban nginx-http-auth status after attack ---\n(.*?)(?=\n--- |\Z)", text, re.S)

    def total_failed(ban_match):
        if not ban_match:
            return None
        m = re.search(r"Total failed:\s+(\d+)", ban_match.group(1))
        return int(m.group(1)) if m else None

    rows = []
    for label, pattern in sections.items():
        m = re.search(pattern, text, re.S)
        if not m:
            continue
        body, elapsed = m.group(1), int(m.group(2))
        attempts = count_attempts(body)
        if label == "ssh_protected":
            attempts = total_failed(ban_sshd) or attempts
        elif label == "nginx_protected":
            attempts = total_failed(ban_nginx) or attempts
        rows.append({
            "scenario": label,
            "elapsed_seconds": elapsed,
            "attempts_logged": attempts,
            "credential_found": found_login(body) or "",
        })

    PROCESSED_DIR.mkdir(parents=True, exist_ok=True)
    with OUT_CSV.open("w", newline="") as f:
        w = csv.DictWriter(f, fieldnames=["scenario", "elapsed_seconds", "attempts_logged", "credential_found"])
        w.writeheader()
        w.writerows(rows)

    note = f"## E5: brute-force defence\n\nParsed from `{raw_path.name}`.\n\n"
    for r in rows:
        note += f"- {r['scenario']}: {r['elapsed_seconds']}s, credential_found={r['credential_found'] or 'no'}\n"
    if ban_sshd:
        note += f"\nsshd jail status after attack:\n```\n{ban_sshd.group(1).strip()}\n```\n"
    if ban_nginx:
        note += f"\nnginx-http-auth jail status after attack:\n```\n{ban_nginx.group(1).strip()}\n```\n"
    note += "\n"
    append_note(note)
    print(f"Wrote {OUT_CSV} ({len(rows)} rows)")


if __name__ == "__main__":
    main()
