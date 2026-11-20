"""Parse the newest run_E3.sh raw log into evidence/processed/E3.csv."""
import csv
import re
import statistics
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from parse_common import PROCESSED_DIR, append_note, latest_raw, parse_wrk_block  # noqa: E402

OUT_CSV = PROCESSED_DIR / "E3.csv"


def main():
    raw_path = latest_raw("E3")
    text = raw_path.read_text()
    parts = re.split(r"--- run=(\d+) path=(static\(/\)|proxied\(/api/health\)) ---", text)

    rows = []
    for i in range(1, len(parts), 3):
        run, path, body = parts[i : i + 3]
        wrk = parse_wrk_block(body)
        rows.append({
            "run": int(run),
            "path": "static" if path.startswith("static") else "proxied",
            "requests_per_sec": wrk["requests_per_sec"] or "",
            "latency_mean_ms": wrk["latency_mean_ms"] or "",
        })

    PROCESSED_DIR.mkdir(parents=True, exist_ok=True)
    with OUT_CSV.open("w", newline="") as f:
        w = csv.DictWriter(f, fieldnames=["run", "path", "requests_per_sec", "latency_mean_ms"])
        w.writeheader()
        w.writerows(rows)

    static_rps = [r["requests_per_sec"] for r in rows if r["path"] == "static" and r["requests_per_sec"] != ""]
    proxied_rps = [r["requests_per_sec"] for r in rows if r["path"] == "proxied" and r["requests_per_sec"] != ""]
    note = f"## E3: reverse proxy overhead\n\nParsed {len(rows)} runs from `{raw_path.name}`.\n\n"
    if static_rps and proxied_rps:
        note += (f"- Static mean: {statistics.mean(static_rps):.1f} req/s\n"
                 f"- Proxied (gunicorn) mean: {statistics.mean(proxied_rps):.1f} req/s\n\n")
    append_note(note)
    print(f"Wrote {OUT_CSV} ({len(rows)} rows)")


if __name__ == "__main__":
    main()
