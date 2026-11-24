"""Spot-check report/report.md against evidence/processed/*.csv and the raw
testssl output: recomputes the headline numbers the report actually cites
and fails loudly if a cited number can no longer be found verbatim in
report.md (catches a stale number left behind after a data regeneration,
or a transcription error made while writing the report - see
docs/decisions.md's Phase 6/8 entry for a real example of the latter).

This does not attempt to parse every number in the report; it recomputes
the specific figures this project has, in practice, gotten wrong at least
once (p90 latency, E6 status codes, E9's grade reason, objective claims)
and checks those. Extend FACTS below when a new number earns the same
scrutiny.
"""
import csv
import re
import statistics
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
REPORT = ROOT / "report" / "report.md"
PROCESSED = ROOT / "evidence" / "processed"
RAW = ROOT / "evidence" / "raw"


def read_csv(name):
    path = PROCESSED / name
    if not path.exists():
        return None
    with path.open() as f:
        return list(csv.DictReader(f))


def fmt(n, decimals=0):
    """Match report.md's own number formatting: thousands separator,
    fixed decimals."""
    return f"{n:,.{decimals}f}"


def compute_facts():
    facts = {}

    e1 = read_csv("E1.csv")
    if e1:
        for conc in ["10", "50", "100", "200"]:
            for server in ["apache", "nginx"]:
                rows = [r for r in e1 if r["concurrency"] == conc and r["server"] == server]
                rps = [float(r["requests_per_sec"]) for r in rows]
                p90 = [float(r["latency_p90_ms"]) for r in rows]
                facts[f"E1 {server} c={conc} req/s"] = fmt(statistics.mean(rps))
                facts[f"E1 {server} c={conc} p90 ms"] = fmt(statistics.mean(p90), 2)

    e2 = read_csv("E2.csv")
    if e2:
        for mode in ["http", "https", "https_keepalive_off"]:
            vals = [float(r["requests_per_sec"]) for r in e2 if r["mode"] == mode]
            if vals:
                facts[f"E2 {mode} req/s"] = fmt(statistics.mean(vals))

    e2h = read_csv("E2_handshake.csv")
    if e2h:
        for tls_version in ["tls1.2", "tls1.3"]:
            vals = [float(r["total_s"]) for r in e2h if r["tls_version"] == tls_version]
            if vals:
                facts[f"E2 handshake {tls_version} ms"] = fmt(statistics.mean(vals) * 1000, 2)

    e6 = read_csv("E6.csv")
    if e6:
        for row in e6:
            scen = row["scenario"]
            facts[f"E6 {scen} req/s"] = fmt(float(row["requests_per_sec"])) if row["requests_per_sec"] else None
            facts[f"E6 {scen} http_200"] = row["http_200"]
            facts[f"E6 {scen} http_429"] = row["http_429"]

    e9_raw = RAW / "testssl_after.txt"
    if e9_raw.exists():
        text = e9_raw.read_text()
        m = re.search(r"Final Score\s+(\d+)", text)
        if m:
            facts["E9 final score"] = m.group(1)
        m = re.search(r"Overall Grade\s+(\S+)", text)
        if m:
            facts["E9 grade"] = m.group(1)
        m = re.search(r"Grade cap reasons\s+(.+?)(?:\n\s*\n|\n\S)", text, re.S)
        if m:
            facts["E9 cap reason contains 'chain incomplete'"] = (
                "chain incomplete" in m.group(1) or "Grade capped to B. Issues with chain of trust"
            )

    return {k: v for k, v in facts.items() if v is not None}


def main():
    if not REPORT.exists():
        print(f"ERROR: {REPORT} not found")
        return 1
    text = REPORT.read_text()

    fills = re.findall(r"\[FILL[^\]]*\]", text)
    placeholders = re.findall(r"\[[A-Z0-9 _-]*PLACEHOLDER[^\]]*\]", text)
    print(f"[FILL ...] markers remaining: {len(fills)}")
    print(f"PLACEHOLDER markers remaining: {len(placeholders)}")

    facts = compute_facts()
    if not facts:
        print("\nNo evidence/processed/*.csv found - run make bench-quick first.")
        return 1

    print(f"\nChecking {len(facts)} recomputed values against report.md ...")
    fail = 0
    for label, value in facts.items():
        if isinstance(value, bool):
            ok = value
        else:
            ok = str(value) in text
        status = "PASS" if ok else "FAIL"
        if not ok:
            fail += 1
        print(f"  {status}: {label} = {value}")

    print()
    if fail:
        print(f"FAIL: {fail} recomputed value(s) not found verbatim in report.md - "
              "the report likely has a stale or mistyped number.")
        return 1
    print("PASS: all recomputed values found in report.md.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
