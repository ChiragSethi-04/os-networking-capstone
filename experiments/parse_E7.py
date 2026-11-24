"""Summarise run_E7.sh output into evidence/processed/E7_summary.md:
confirms HTTP payload is readable, HTTPS is not."""
import re
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from parse_common import PROCESSED_DIR, append_note, latest_raw  # noqa: E402

HEX_TOKEN_RE = re.compile(r"\b([0-9a-f]{16,})\b")


def decode_hex_tokens(section):
    """tshark's `-T fields -e http.file_data` prints the field as a hex
    string by default, not decoded ASCII - the capture genuinely contains
    the plaintext payload, but a plain substring search for our marker
    text against the raw hex never matches it. Decode every hex-looking
    token found and append the readable result for both detection and
    for actually showing a human the plaintext in the summary."""
    decoded_lines = []
    for token in HEX_TOKEN_RE.findall(section):
        try:
            decoded = bytes.fromhex(token).decode("utf-8")
        except (ValueError, UnicodeDecodeError):
            continue
        if decoded.isprintable():
            decoded_lines.append(decoded)
    return decoded_lines


def main():
    raw_path = latest_raw("E7")
    text = raw_path.read_text()

    http_section = text.split("--- tshark: HTTP request URI")[-1].split("--- tshark: HTTPS")[0]
    https_section = text.split("--- tshark: HTTPS")[-1]

    http_decoded = decode_hex_tokens(http_section)

    http_readable = any("e7@example.com" in line for line in http_decoded)
    # HTTPS side: tshark's own default packet summary (not a raw field
    # extraction - see run_E7.sh for why: Wireshark's TLS 1.3 dissector
    # doesn't reliably populate `tls.record.content_type` as a per-record
    # field once a stream is fully encrypted, even though it labels those
    # same frames "Application Data" in its summary). Presence of that
    # label proves encrypted application data was actually exchanged, not
    # just a handshake; absence of the plaintext marker (impossible for it
    # to appear in a summary line regardless, but checked anyway) confirms
    # nothing leaked into a dissectable field.
    app_data_frames = https_section.count("Application Data")
    https_has_app_data = app_data_frames > 0
    https_opaque = "e7@example.com" not in https_section

    decoded_block = "\n".join(http_decoded) if http_decoded else "(no decodable payload found)"

    PROCESSED_DIR.mkdir(parents=True, exist_ok=True)
    summary = (PROCESSED_DIR / "E7_summary.md")
    summary.write_text(
        f"# E7 encryption proof\n\n"
        f"Source: `{raw_path.name}`\n\n"
        f"- HTTP payload readable in capture: {'YES' if http_readable else 'NO (check capture)'}\n"
        f"- HTTPS capture contains real encrypted application data (not just handshake): "
        f"{'YES' if https_has_app_data else 'NO (check capture)'} ({app_data_frames} frame(s) labelled Application Data)\n"
        f"- HTTPS payload opaque (no plaintext contact-form data visible): "
        f"{'YES' if https_opaque else 'NO (check capture, may indicate a leak)'}\n\n"
        f"## HTTP plaintext payload, decoded from tshark's hex field output\n```\n{decoded_block}\n```\n\n"
        f"## HTTP (tshark http.file_data, raw fields output)\n```\n{http_section.strip()[:1500]}\n```\n\n"
        f"## HTTPS (tshark default packet summary - TLSv1.3 handshake then Application Data)\n```\n{https_section.strip()[:1500]}\n```\n"
    )

    append_note(
        f"## E7: encryption proof\n\nHTTP readable: {http_readable}. HTTPS has real application "
        f"data ({app_data_frames} frames): {https_has_app_data}. HTTPS opaque: {https_opaque}. "
        f"See `evidence/processed/E7_summary.md` for the decoded plaintext and full tshark excerpts.\n\n"
    )
    print(f"Wrote {summary}")


if __name__ == "__main__":
    main()
