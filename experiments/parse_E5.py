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
    return len(re.findall(r"\[ATTEMPT\]|login try", body))


def found_login(body):
    m = re.search(r"\[\d+\]\[\S+\] host: \S+\s+login: (\S+)\s+password: (\S+)", body)
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

    rows = []
    for label, pattern in sections.items():
        m = re.search(pattern, text, re.S)
        if not m:
            continue
        body, elapsed = m.group(1), int(m.group(2))
        rows.append({
            "scenario": label,
            "elapsed_seconds": elapsed,
            "attempts_logged": count_attempts(body),
            "credential_found": found_login(body) or "",
        })

    ban_sshd = re.search(r"fail2ban sshd status after attack ---\n(.*?)\n\n", text, re.S)
    ban_nginx = re.search(r"fail2ban nginx-http-auth status after attack ---\n(.*?)\n\n", text, re.S)

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
