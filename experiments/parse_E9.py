"""Summarise testssl.sh before/after reports (from harden.sh) into
evidence/processed/E9_summary.md."""
import re
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from parse_common import RAW_DIR, PROCESSED_DIR, append_note  # noqa: E402

ANSI_RE = re.compile(r"\x1b\[[0-9;]*m")


def strip_ansi(text):
    # `harden.sh`/`run_E9.sh` now pass `--color 0`, but this stays as a
    # defensive second layer: an earlier run without that flag produced
    # "Grade: [m[0;33mB[m" in E9_summary.md - the raw escape codes leaking
    # straight into report-facing text - because `grade()`'s `\S+` happily
    # swallowed them as part of the "word" it captured.
    return ANSI_RE.sub("", text)


def grade(text):
    m = re.search(r"Overall Grade\s+(\S+)", text)
    return m.group(1) if m else "N/A_no_TLS_listener"


def protocols(text):
    return "\n".join(l for l in text.splitlines() if re.search(r"TLS 1|SSLv", l))


def main():
    before_path = RAW_DIR / "testssl_before.txt"
    after_path = RAW_DIR / "testssl_after.txt"
    before = strip_ansi(before_path.read_text()) if before_path.exists() else ""
    after = strip_ansi(after_path.read_text()) if after_path.exists() else ""

    PROCESSED_DIR.mkdir(parents=True, exist_ok=True)
    summary = PROCESSED_DIR / "E9_summary.md"
    summary.write_text(
        f"# E9 TLS quality (testssl.sh)\n\n"
        f"## Before hardening\nGrade: {grade(before)}\n```\n{protocols(before)}\n```\n\n"
        f"## After hardening\nGrade: {grade(after)}\n```\n{protocols(after)}\n```\n"
    )

    append_note(
        f"## E9: TLS quality\n\nBefore grade: {grade(before)}. After grade: {grade(after)}. "
        f"See `evidence/processed/E9_summary.md`.\n\n"
    )
    print(f"Wrote {summary}")


if __name__ == "__main__":
    main()
