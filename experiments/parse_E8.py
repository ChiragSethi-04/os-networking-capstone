"""Parse the newest run_E8.sh raw log into evidence/processed/E8.csv:
time to detect/restart, and confirm logrotate produced a rotated file."""
import csv
import re
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from parse_common import PROCESSED_DIR, append_note, latest_raw  # noqa: E402

OUT_CSV = PROCESSED_DIR / "E8.csv"


def main():
    raw_path = latest_raw("E8")
    text = raw_path.read_text()

    detect_m = re.search(r"detected_active_again_after_seconds=(\d+)", text)
    down_m = re.search(r"nginx DOWN", text)
    restarted_m = re.search(r"nginx RESTARTED", text)
    rotated = bool(re.search(r"\.gz", text))

    row = {
        "detected_active_again_after_seconds": detect_m.group(1) if detect_m else "",
        "monitor_logged_down": bool(down_m),
        "monitor_logged_restarted": bool(restarted_m),
        "logrotate_produced_gz": rotated,
    }

    PROCESSED_DIR.mkdir(parents=True, exist_ok=True)
    with OUT_CSV.open("w", newline="") as f:
        w = csv.DictWriter(f, fieldnames=list(row.keys()))
        w.writeheader()
        w.writerow(row)

    note = (
        f"## E8: resilience\n\nParsed from `{raw_path.name}`.\n\n"
        f"- Recovery detected after: {row['detected_active_again_after_seconds']}s\n"
        f"- Monitor logged DOWN: {row['monitor_logged_down']}, RESTARTED: {row['monitor_logged_restarted']}\n"
        f"- logrotate produced a compressed rotated file: {row['logrotate_produced_gz']}\n\n"
    )
    append_note(note)
    print(f"Wrote {OUT_CSV}")


if __name__ == "__main__":
    main()
