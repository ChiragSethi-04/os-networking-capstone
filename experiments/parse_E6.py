"""Parse the newest run_E6.sh raw log into evidence/processed/E6.csv:
status code mix with vs without limit_req."""
import csv
import re
import sys
from collections import Counter
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from parse_common import PROCESSED_DIR, append_note, latest_raw, parse_wrk_block  # noqa: E402

OUT_CSV = PROCESSED_DIR / "E6.csv"


def main():
    raw_path = latest_raw("E6")
    text = raw_path.read_text()

    with_section = re.search(r"--- WITH limit_req.*?---\n(.*?)--- temporarily disabling", text, re.S)
    without_section = re.search(r"--- WITHOUT limit_req ---\n(.*?)--- restoring limit_req", text, re.S)

    rows = []
    for label, section in (("with_limit_req", with_section), ("without_limit_req", without_section)):
        if not section:
            continue
        body = section.group(1)
        wrk = parse_wrk_block(body)
        codes = Counter(re.findall(r"^(\d{3})$", body, re.M))
        rows.append({
            "scenario": label,
            "requests_per_sec": wrk["requests_per_sec"] or "",
            "http_200": codes.get("200", 0),
            "http_429": codes.get("429", 0),
            "http_503": codes.get("503", 0),
            "other_codes": sum(v for k, v in codes.items() if k not in ("200", "429", "503")),
        })

    PROCESSED_DIR.mkdir(parents=True, exist_ok=True)
    with OUT_CSV.open("w", newline="") as f:
        w = csv.DictWriter(f, fieldnames=["scenario", "requests_per_sec", "http_200", "http_429", "http_503", "other_codes"])
        w.writeheader()
        w.writerows(rows)

    note = f"## E6: rate limiting\n\nParsed from `{raw_path.name}`.\n\n"
    for r in rows:
        note += f"- {r['scenario']}: {r['http_200']}x200, {r['http_429']}x429, {r['http_503']}x503\n"
    note += "\n"
    append_note(note)
    print(f"Wrote {OUT_CSV} ({len(rows)} rows)")


if __name__ == "__main__":
    main()
