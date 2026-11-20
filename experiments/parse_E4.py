"""Parse nmap before/after files (from harden.sh) and run_E4.sh output into
evidence/processed/E4_ports.csv (open port count per host, before vs after)."""
import csv
import re
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from parse_common import RAW_DIR, PROCESSED_DIR, append_note, latest_raw  # noqa: E402

OUT_CSV = PROCESSED_DIR / "E4_ports.csv"


def open_ports(path):
    if not path.exists():
        return []
    text = path.read_text()
    return re.findall(r"^(\d+)/tcp\s+open", text, re.M)


def main():
    pairs = [
        ("web", RAW_DIR / "nmap_web_before.txt", RAW_DIR / "nmap_web_after.txt"),
        ("db", RAW_DIR / "nmap_db_before.txt", RAW_DIR / "nmap_db_after.txt"),
    ]
    rows = []
    for host, before_path, after_path in pairs:
        before = open_ports(before_path)
        after = open_ports(after_path)
        rows.append({"host": host, "state": "before", "open_port_count": len(before), "ports": ";".join(before)})
        rows.append({"host": host, "state": "after", "open_port_count": len(after), "ports": ";".join(after)})

    PROCESSED_DIR.mkdir(parents=True, exist_ok=True)
    with OUT_CSV.open("w", newline="") as f:
        w = csv.DictWriter(f, fieldnames=["host", "state", "open_port_count", "ports"])
        w.writeheader()
        w.writerows(rows)

    note = "## E4: attack surface\n\n"
    for r in rows:
        note += f"- {r['host']} {r['state']}: {r['open_port_count']} open ports ({r['ports']})\n"
    note += "\n"
    append_note(note)
    print(f"Wrote {OUT_CSV} ({len(rows)} rows)")


if __name__ == "__main__":
    main()
