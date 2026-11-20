"""Render captured terminal text (ufw status, fail2ban status, ss, htop,
monitor log, tshark excerpts) into clean monospace PNGs: dark theme,
trimmed, never hand-edited. Used for F12 and the required terminal
screenshots listed in CLAUDE.md section 7.

Usage: python3 figures/render_terminal_evidence.py <input.txt> <output.png> [title]
"""
import sys
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

BG = "#1a1a19"
FG = "#f0efec"
MUTED = "#898781"
FONT_CANDIDATES = [
    "/System/Library/Fonts/SFNSMono.ttf",
    "/System/Library/Fonts/Menlo.ttc",
    "/Library/Fonts/Courier New.ttf",
]


def load_font(size):
    for path in FONT_CANDIDATES:
        if Path(path).exists():
            try:
                return ImageFont.truetype(path, size)
            except OSError:
                continue
    return ImageFont.load_default()


def render(input_path, output_path, title=None):
    text = Path(input_path).read_text().rstrip()
    lines = [l.rstrip() for l in text.splitlines() if l.strip() != ""]
    font = load_font(16)
    title_font = load_font(18)

    pad = 24
    line_h = 22
    char_w = 10
    max_len = max((len(l) for l in lines), default=40)
    width = max(640, pad * 2 + max_len * char_w)
    height = pad * 2 + (len(lines) + (2 if title else 0)) * line_h

    img = Image.new("RGB", (width, height), BG)
    draw = ImageDraw.Draw(img)

    y = pad
    if title:
        draw.text((pad, y), title, font=title_font, fill=MUTED)
        y += line_h * 2

    for line in lines:
        draw.text((pad, y), line, font=font, fill=FG)
        y += line_h

    img.save(output_path)
    print(f"Wrote {output_path}")


if __name__ == "__main__":
    if len(sys.argv) < 3:
        raise SystemExit(__doc__)
    title = sys.argv[3] if len(sys.argv) > 3 else None
    render(sys.argv[1], sys.argv[2], title)
