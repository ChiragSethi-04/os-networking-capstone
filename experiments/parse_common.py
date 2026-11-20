"""Shared parsing helpers for experiments/parse_E*.py."""
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
RAW_DIR = ROOT / "evidence" / "raw"
PROCESSED_DIR = ROOT / "evidence" / "processed"
NOTES = PROCESSED_DIR / "Ex_notes.md"


def latest_raw(prefix):
    files = sorted(RAW_DIR.glob(f"{prefix}_*.txt"))
    if not files:
        raise SystemExit(f"No {prefix} raw files found. Run experiments/run_{prefix}.sh first.")
    return files[-1]


def _to_ms(value, unit):
    value = float(value)
    unit = unit.lower()
    if unit == "us":
        return value / 1000
    if unit == "s":
        return value * 1000
    return value


def parse_wrk_block(text):
    """Pull the headline numbers out of one wrk --latency output block."""
    out = {"requests_per_sec": None, "latency_mean_ms": None, "latency_p95_ms": None,
           "failed_requests": 0, "total_requests": None}

    m = re.search(r"Requests/sec:\s+([\d.]+)", text)
    if m:
        out["requests_per_sec"] = float(m.group(1))

    m = re.search(r"Latency\s+([\d.]+)(us|ms|s)", text)
    if m:
        out["latency_mean_ms"] = _to_ms(m.group(1), m.group(2))

    # wrk --latency prints a distribution table:
    #   50%  ...
    #   75%  ...
    #   90%  ...
    #   99%  ...
    # p95 is not a default bucket; approximate with the 90% line if present,
    # and note the approximation in Ex_notes.md.
    m = re.search(r"90%\s+([\d.]+)(us|ms|s)", text)
    if m:
        out["latency_p95_ms"] = _to_ms(m.group(1), m.group(2))

    m = re.search(r"(\d+)\s+requests in", text)
    if m:
        out["total_requests"] = int(m.group(1))

    m = re.search(r"Non-2xx or 3xx responses:\s+(\d+)", text)
    if m:
        out["failed_requests"] = int(m.group(1))

    m = re.search(r"Socket errors: connect (\d+), read (\d+), write (\d+), timeout (\d+)", text)
    if m:
        out["failed_requests"] += sum(int(g) for g in m.groups())

    return out


def append_note(markdown):
    PROCESSED_DIR.mkdir(parents=True, exist_ok=True)
    with NOTES.open("a") as f:
        f.write(markdown)
