"""Summarise run_E7.sh output into evidence/processed/E7_summary.md:
confirms HTTP payload is readable, HTTPS is not."""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from parse_common import PROCESSED_DIR, append_note, latest_raw  # noqa: E402


def main():
    raw_path = latest_raw("E7")
    text = raw_path.read_text()

    http_section = text.split("--- tshark: HTTP request URI")[-1].split("--- tshark: HTTPS")[0]
    https_section = text.split("--- tshark: HTTPS")[-1]

    http_readable = "e7@example.com" in http_section or "message" in http_section
    https_opaque = "e7@example.com" not in https_section

    PROCESSED_DIR.mkdir(parents=True, exist_ok=True)
    summary = (PROCESSED_DIR / "E7_summary.md")
    summary.write_text(
        f"# E7 encryption proof\n\n"
        f"Source: `{raw_path.name}`\n\n"
        f"- HTTP payload readable in capture: {'YES' if http_readable else 'NO (check capture)'}\n"
        f"- HTTPS payload opaque (no plaintext contact-form data visible): "
        f"{'YES' if https_opaque else 'NO (check capture, may indicate a leak)'}\n\n"
        f"## HTTP (tshark http.file_data)\n```\n{http_section.strip()[:2000]}\n```\n\n"
        f"## HTTPS (tshark tls.record.content_type)\n```\n{https_section.strip()[:2000]}\n```\n"
    )

    append_note(
        f"## E7: encryption proof\n\nHTTP readable: {http_readable}. HTTPS opaque: {https_opaque}. "
        f"See `evidence/processed/E7_summary.md` for the full tshark excerpts.\n\n"
    )
    print(f"Wrote {summary}")


if __name__ == "__main__":
    main()
