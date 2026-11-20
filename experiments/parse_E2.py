"""Parse the newest run_E2.sh raw log into evidence/processed/E2.csv."""
import csv
import re
import statistics
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from parse_common import PROCESSED_DIR, append_note, latest_raw, parse_wrk_block  # noqa: E402

OUT_CSV = PROCESSED_DIR / "E2.csv"


def main():
    raw_path = latest_raw("E2")
    text = raw_path.read_text()
    run_blocks = re.split(r"--- run=(\d+) mode=(http|https) ---", text)

    rows = []
    for i in range(1, len(run_blocks), 3):
        run, mode, body = run_blocks[i : i + 3]
        next_marker = re.search(r"--- run=\d+ (mode=\w+|curl|openssl)", body)
        body = body[: next_marker.start()] if next_marker else body
        wrk = parse_wrk_block(body)
        rows.append({
            "run": int(run), "mode": mode,
            "requests_per_sec": wrk["requests_per_sec"] or "",
            "latency_mean_ms": wrk["latency_mean_ms"] or "",
        })

    handshake_rows = []
    for m in re.finditer(r"curl handshake timing (tls1\.2|tls1\.3) ---\n.*?connect=([\d.]+) tls=([\d.]+) total=([\d.]+)", text, re.S):
        tls_version, connect, tls, total = m.groups()
        handshake_rows.append({"tls_version": tls_version, "connect_s": connect, "tls_s": tls, "total_s": total})

    PROCESSED_DIR.mkdir(parents=True, exist_ok=True)
    with OUT_CSV.open("w", newline="") as f:
        w = csv.DictWriter(f, fieldnames=["run", "mode", "requests_per_sec", "latency_mean_ms"])
        w.writeheader()
        w.writerows(rows)

    with (PROCESSED_DIR / "E2_handshake.csv").open("w", newline="") as f:
        w = csv.DictWriter(f, fieldnames=["tls_version", "connect_s", "tls_s", "total_s"])
        w.writeheader()
        w.writerows(handshake_rows)

    http_rps = [r["requests_per_sec"] for r in rows if r["mode"] == "http" and r["requests_per_sec"] != ""]
    https_rps = [r["requests_per_sec"] for r in rows if r["mode"] == "https" and r["requests_per_sec"] != ""]
    note = f"## E2: transport cost\n\nParsed {len(rows)} wrk runs and {len(handshake_rows)} handshake timings from `{raw_path.name}`.\n\n"
    if http_rps and https_rps:
        note += (f"- HTTP mean: {statistics.mean(http_rps):.1f} req/s\n"
                 f"- HTTPS mean: {statistics.mean(https_rps):.1f} req/s\n"
                 f"- TLS overhead: {(1 - statistics.mean(https_rps)/statistics.mean(http_rps))*100:.1f}% throughput reduction\n\n")
    append_note(note)
    print(f"Wrote {OUT_CSV} and E2_handshake.csv ({len(rows)} + {len(handshake_rows)} rows)")


if __name__ == "__main__":
    main()
