"""Parse the newest run_E1.sh raw log into evidence/processed/E1.csv."""
import csv
import re
import statistics
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from parse_common import RAW_DIR, PROCESSED_DIR, append_note, latest_raw, parse_wrk_block  # noqa: E402

OUT_CSV = PROCESSED_DIR / "E1.csv"


def main():
    raw_path = latest_raw("E1")
    text = raw_path.read_text()
    parts = re.split(r"--- server=(\w+) port=(\d+) concurrency=(\d+) run=(\d+) ---", text)

    rows = []
    for i in range(1, len(parts), 5):
        server, port, conc, run, body = parts[i : i + 5]
        wrk = parse_wrk_block(body)
        cpu_vals = re.findall(r"^\s*\d+:\d+:\d+\s+\S+\s+\d+\s+([\d.]+)\s+[\d.]+\s+[\d.]+", body, re.M)
        rows.append(
            {
                "server": server,
                "concurrency": int(conc),
                "run": int(run),
                "requests_per_sec": wrk["requests_per_sec"] or "",
                "latency_mean_ms": wrk["latency_mean_ms"] or "",
                "latency_p90_ms": wrk["latency_p95_ms"] or "",
                "failed_requests": wrk["failed_requests"],
                "cpu_pct": round(statistics.mean(float(v) for v in cpu_vals), 1) if cpu_vals else "",
            }
        )

    PROCESSED_DIR.mkdir(parents=True, exist_ok=True)
    with OUT_CSV.open("w", newline="") as f:
        w = csv.DictWriter(
            f,
            fieldnames=["server", "concurrency", "run", "requests_per_sec", "latency_mean_ms",
                        "latency_p90_ms", "failed_requests", "cpu_pct"],
        )
        w.writeheader()
        w.writerows(rows)

    by_server = {}
    for r in rows:
        if r["requests_per_sec"] != "":
            by_server.setdefault(r["server"], []).append(r["requests_per_sec"])

    note = f"## E1: server comparison\n\nParsed {len(rows)} runs from `{raw_path.name}`.\n\n"
    for server, vals in by_server.items():
        note += f"- {server}: mean {statistics.mean(vals):.1f} req/s, sd {statistics.pstdev(vals):.1f} (n={len(vals)})\n"
    note += "\nNote: `latency_p90_ms` is wrk's 90th percentile bucket, used as a p95 proxy (wrk's default histogram does not expose p95 directly).\n\n"
    append_note(note)

    print(f"Wrote {OUT_CSV} ({len(rows)} rows)")


if __name__ == "__main__":
    main()
