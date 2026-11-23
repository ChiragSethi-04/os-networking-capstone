"""Build slides/deck.pptx: ~14 slides, diagram/chart-led, speaker notes with
timing, for a 30-minute presentation slot. Figures must already exist
(run `make figures` first) - this script embeds them, it does not generate
data.
"""
import sys
from pathlib import Path

from pptx import Presentation
from pptx.util import Inches, Pt
from pptx.dml.color import RGBColor

ROOT = Path(__file__).resolve().parents[1]
FIG = ROOT / "figures"
OUT = ROOT / "slides" / "deck.pptx"

NAVY = RGBColor(0x0F, 0x2A, 0x43)
TEAL = RGBColor(0x0F, 0x6E, 0x56)
INK = RGBColor(0x0B, 0x0B, 0x0B)

SLIDES = [
    # (title, bullets, image_path_or_None, speaker_notes, minutes)
    ("Deploying a Secure Web Server and Hosting a Company Website",
     ["OS & Networking Capstone, Project 2", "Group 6: Chirag Sethi, Shree Iyengar, Hardik Sharma, Mehul Nagarkoti"],
     None, "Introduce the team and the one-sentence goal. 1 minute.", 1),
    ("Problem and goals",
     ["Default web deployments over-expose services and leak plaintext traffic",
      "Five measurable objectives (throughput, attack surface, ban time, recovery time, TLS grade)",
      "See report Section 1.3 for exact targets"],
     None, "State the problem and read the five objectives. 1-2 minutes.", 2),
    ("Architecture",
     ["Three Multipass VMs: web, db, attacker", "Mac as admin workstation, SSH key only"],
     str(FIG / "F1_architecture.png"), "Walk the diagram left to right. 2 minutes.", 2),
    ("Request flow and OSI mapping",
     ["Client -> Nginx (TLS, L6/L4/L3) -> app (L7) -> MariaDB"],
     str(FIG / "F2_request_flow.png"), "Trace one request end to end, naming the OSI layer at each hop. 2 minutes.", 2),
    ("Design decisions",
     ["Nginx chosen over Apache/Lighttpd/IIS (benchmarked, not assumed)",
      "Separate web/db VMs; db reachable only from web's IP",
      "Local CA instead of Let's Encrypt (no public domain in this lab)"],
     None, "Name each decision and its one-line reason; full reasoning in report 3.1. 2 minutes.", 2),
    ("TLS handshake and firewall",
     ["TLS 1.2/1.3 only, HSTS, HTTP/2", "ufw: default deny, only 22/80/443 open on web"],
     str(FIG / "F3_tls_handshake.png"), "Point out where the handshake ends and the firewall rule starts. 2 minutes.", 2),
    ("Hardening results: attack surface",
     ["nmap before vs after hardening"],
     str(FIG / "F9_e4_open_ports.png"), "Before: many ports. After: exactly 3 on web, 0 directly on db. 1-2 minutes.", 2),
    ("Benchmarks: throughput and latency",
     ["Apache vs Nginx, concurrency 10-200"],
     str(FIG / "F4_e1_throughput.png"), "Read the headline numbers; explain briefly via the event-driven model. 2 minutes.", 2),
    ("Benchmarks: latency and transport cost",
     ["Mean/p95 latency per server; HTTP vs HTTPS cost"],
     str(FIG / "F5_e1_latency.png"), "Latency story, then transition to TLS cost. 2 minutes.", 2),
    ("Brute-force defence",
     ["hydra before/after Fail2Ban, SSH and admin path"],
     str(FIG / "F10_e5_bruteforce_timeline.png"), "Unprotected: guessed. Protected: banned first. 2 minutes.", 2),
    ("Resilience and monitoring",
     ["systemd + 30s monitor: kill nginx, watch it recover"],
     str(FIG / "F13_e8_resilience_timeline.png"), "This is also shown live in the demo. 1-2 minutes.", 2),
    ("Live demo",
     ["See docs/demo_script.md", "Checklist: VMs up, snapshot fresh, fallback clips ready"],
     None, "Switch to the terminal/browser now. Demo budget: 10-12 minutes (see docs/demo_script.md).", 11),
    ("Challenges and trade-offs",
     ["Shared hypervisor limits absolute throughput numbers",
      "ufw host firewalls, not true VLAN segmentation",
      "E5 required throwaway demo credentials (see report 3.3)"],
     None, "Be honest about limits; this is rewarded by the rubric. 2 minutes.", 2),
    ("Conclusions and future work",
     ["4 of 5 objectives met: throughput (43,258 req/s), attack surface (3/0 ports), recovery (3s), TLS grade B",
      "Partially met: Fail2Ban stops SSH brute-force but not the Nginx basic-auth path - honest gap, fix proposed",
      "Future: HA, WAF, central logging, ACME certs, IDS"],
     None, "State pass/fail against each objective with the actual number; be upfront about the Fail2Ban gap. 1-2 minutes.", 2),
    ("Questions and discussion",
     ["Thank you - happy to go deeper on any design choice or number"],
     None, "Open floor. Budget whatever remains of the 30 minutes.", 3),
]


def add_slide(prs, title, bullets, image_path, notes):
    layout = prs.slide_layouts[5]  # title only
    slide = prs.slides.add_slide(layout)
    slide.shapes.title.text = title
    slide.shapes.title.text_frame.paragraphs[0].font.size = Pt(28)
    slide.shapes.title.text_frame.paragraphs[0].font.color.rgb = NAVY

    top = Inches(1.3)
    if image_path and Path(image_path).exists():
        pic = slide.shapes.add_picture(image_path, Inches(0.6), top, width=Inches(6.0))
        text_left = Inches(6.8)
        text_width = Inches(6.0)
    else:
        text_left = Inches(0.8)
        text_width = Inches(11.5)

    box = slide.shapes.add_textbox(text_left, top, text_width, Inches(5))
    tf = box.text_frame
    tf.word_wrap = True
    for i, bullet in enumerate(bullets):
        p = tf.paragraphs[0] if i == 0 else tf.add_paragraph()
        p.text = f"• {bullet}"
        p.font.size = Pt(18)
        p.font.color.rgb = INK

    slide.notes_slide.notes_text_frame.text = notes


def main():
    prs = Presentation()
    prs.slide_width = Inches(13.333)
    prs.slide_height = Inches(7.5)

    for title, bullets, image_path, notes, minutes in SLIDES:
        add_slide(prs, title, bullets, image_path, f"[{minutes} min] {notes}")

    OUT.parent.mkdir(parents=True, exist_ok=True)
    prs.save(OUT)
    print(f"Wrote {OUT} ({len(SLIDES)} slides)")
    missing = [t for t, _, img, _, _ in SLIDES if img and not Path(img).exists()]
    if missing:
        print("NOTE: some slides reference figures that do not exist yet "
              "(run `make figures` first):", missing)


if __name__ == "__main__":
    main()
