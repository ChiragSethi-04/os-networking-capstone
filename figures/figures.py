"""Generate figures F1-F14 (CLAUDE.md section 7) from evidence/processed/
CSVs only, as 300 dpi PNGs in figures/. Diagrams (F1-F3) are built with
graphviz/matplotlib directly, not from CSVs, since they describe the fixed
architecture rather than measured data.

Color roles follow the dataviz skill's validated reference palette
(references/palette.md): categorical slot 1 blue #2a78d6 for Nginx, slot 2
orange #eb6834 for Apache, light chart surface #fcfcfb, primary ink #0b0b0b,
secondary ink #52514e, muted axis/label #898781, gridline #e1e0d9.
"""
import csv
import statistics
import subprocess
import sys
from pathlib import Path

import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
import matplotlib.ticker as mticker

ROOT = Path(__file__).resolve().parents[1]
PROCESSED = ROOT / "evidence" / "processed"
RAW = ROOT / "evidence" / "raw"
FIG_DIR = ROOT / "figures"
CAPTIONS = FIG_DIR / "captions.md"

BLUE = "#2a78d6"     # Nginx
ORANGE = "#eb6834"   # Apache
SURFACE = "#fcfcfb"
INK = "#0b0b0b"
INK_SECONDARY = "#52514e"
MUTED = "#898781"
GRID = "#e1e0d9"
BASELINE = "#c3c2b7"

SERVER_COLOR = {"nginx": BLUE, "apache": ORANGE}

plt.rcParams.update({
    "figure.facecolor": SURFACE,
    "axes.facecolor": SURFACE,
    "savefig.facecolor": SURFACE,
    "font.size": 11,
    "font.family": "sans-serif",
    "text.color": INK,
    "axes.labelcolor": INK,
    "axes.edgecolor": BASELINE,
    "xtick.color": MUTED,
    "ytick.color": MUTED,
    "grid.color": GRID,
    "axes.grid": True,
    "axes.axisbelow": True,
    "legend.frameon": False,
})

captions = []


def add_caption(fid, text):
    captions.append(f"**{fid}**: {text}")


def mean_ci95(values):
    """Despite the name (kept to avoid touching every call site), this
    does NOT return a 95% confidence interval. With n=2 repeats per
    configuration (quick mode), a normal-approximation CI using z=1.96 is
    invalid, and the statistically correct fix - the t-distribution's
    critical value at df=1 (t=12.706) - produces error bars many times
    larger than the means themselves, which is accurate but unreadable
    and not informative. Instead this returns the half-range across the
    actual repeats (max-min)/2: an honest visual spread of the real
    observed values, not a claimed statistical interval. Figure captions
    describe it as such, not as a 95% CI. See docs/decisions.md."""
    values = [v for v in values if v not in ("", None)]
    values = [float(v) for v in values]
    if not values:
        return 0.0, 0.0
    m = statistics.mean(values)
    if len(values) < 2:
        return m, 0.0
    half_range = (max(values) - min(values)) / 2
    return m, half_range


def read_csv(name):
    path = PROCESSED / name
    if not path.exists():
        print(f"SKIP {name}: not found (run experiments/run_*.sh + parse_*.py first)")
        return None
    with path.open() as f:
        return list(csv.DictReader(f))


def savefig(fig, fid, filename):
    fig.tight_layout()
    fig.savefig(FIG_DIR / filename, dpi=300)
    plt.close(fig)
    print(f"Wrote figures/{filename}")


# ---------------------------------------------------------------- F1, F2 ----
def f1_architecture():
    dot = """
    digraph F1 {
      rankdir=TB; bgcolor="#fcfcfb";
      node [shape=box, style="rounded,filled", fontname="Helvetica", fontsize=11,
            color="#c3c2b7", fillcolor="#fcfcfb", fontcolor="#0b0b0b"];
      edge [color="#52514e", fontname="Helvetica", fontsize=9, fontcolor="#52514e"];

      internet [label="Internet\\n(clients, attacker VM)"];
      fw [label="Host firewall (ufw)\\non web VM"];
      web [label="web VM\\nNginx + Apache (8080) + gunicorn", fillcolor="#cde2fb"];
      db [label="db VM\\nMariaDB, port 3306", fillcolor="#cde2fb"];
      admin [label="Mac host\\nAdmin workstation, SSH key + browser"];

      internet -> fw [label="80/443"];
      fw -> web;
      web -> db [label="3306, from web IP only"];
      admin -> web [label="SSH key, 22"];
      admin -> db [label="SSH key, 22 (via ufw allow)"];
    }
    """
    (FIG_DIR / "_f1.dot").write_text(dot)
    subprocess.run(["dot", "-Tpng", "-Gdpi=300", str(FIG_DIR / "_f1.dot"),
                    "-o", str(FIG_DIR / "F1_architecture.png")], check=True)
    (FIG_DIR / "_f1.dot").unlink()
    add_caption("F1", "Network architecture: Internet/attacker VM, host firewall, "
                       "web VM (Nginx, Apache baseline, Flask/gunicorn), db VM (MariaDB), "
                       "and the Mac as admin workstation.")
    print("Wrote figures/F1_architecture.png")


def f2_request_flow():
    dot = """
    digraph F2 {
      rankdir=LR; bgcolor="#fcfcfb";
      node [shape=box, style="rounded,filled", fontname="Helvetica", fontsize=10,
            color="#c3c2b7", fillcolor="#fcfcfb", fontcolor="#0b0b0b"];
      edge [color="#52514e", fontname="Helvetica", fontsize=9, fontcolor="#52514e"];

      client [label="Client\\n(L7 HTTP/HTTPS)"];
      nginx [label="Nginx\\nTLS term., reverse proxy,\\nrate limit (L7)", fillcolor="#cde2fb"];
      app [label="gunicorn + Flask\\n/api/* (L7)", fillcolor="#cde2fb"];
      db [label="MariaDB\\n(L7, TCP/3306, L4)", fillcolor="#cde2fb"];
      static [label="Static files\\n/var/www/html (L7)"];

      client -> nginx [label="TLS 1.2/1.3 (L6), TCP (L4), IP (L3)"];
      nginx -> static [label="/ "];
      nginx -> app [label="/api/ (proxy_pass, L7)"];
      app -> db [label="pymysql / TCP (L4)"];
    }
    """
    (FIG_DIR / "_f2.dot").write_text(dot)
    subprocess.run(["dot", "-Tpng", "-Gdpi=300", str(FIG_DIR / "_f2.dot"),
                    "-o", str(FIG_DIR / "F2_request_flow.png")], check=True)
    (FIG_DIR / "_f2.dot").unlink()
    add_caption("F2", "Request flow from client to Nginx to the Flask app and MariaDB, "
                       "with the OSI layer each hop operates at.")
    print("Wrote figures/F2_request_flow.png")


def f3_tls_handshake():
    fig, ax = plt.subplots(figsize=(7.5, 4.2))
    actors = ["Client (attacker VM)", "Nginx (web VM)"]
    x_pos = {actors[0]: 0.15, actors[1]: 0.85}
    for actor in actors:
        ax.axvline(x_pos[actor], color=BASELINE, lw=1, ymin=0.05, ymax=0.95)
        ax.text(x_pos[actor], 1.0, actor, ha="center", va="bottom", fontsize=10, color=INK)

    steps = [
        ("ClientHello (supported versions, ciphers, SNI=web)", "client", "server"),
        ("ServerHello + certificate (web.crt) + key share", "server", "client"),
        ("Client verifies cert against ca.crt, sends key share", "client", "server"),
        ("Finished (both sides derive session keys)", "server", "client"),
        ("Application data, encrypted (HTTP over TLS)", "client", "server"),
    ]
    n = len(steps)
    for i, (label, src, dst) in enumerate(steps):
        y = 0.9 - i * (0.8 / n)
        x0 = x_pos[actors[0]] if src == "client" else x_pos[actors[1]]
        x1 = x_pos[actors[1]] if dst == "server" else x_pos[actors[0]]
        ax.annotate("", xy=(x1, y), xytext=(x0, y),
                    arrowprops=dict(arrowstyle="-|>", color=INK_SECONDARY, lw=1.4))
        ax.text((x0 + x1) / 2, y + 0.03, label, ha="center", va="bottom",
                fontsize=8.5, color=INK)

    ax.set_xlim(0, 1)
    ax.set_ylim(0, 1.08)
    ax.axis("off")
    add_caption("F3", "TLS 1.3 handshake sequence between the attacker VM (as a plain "
                       "client) and Nginx on the web VM, ending in encrypted application data.")
    savefig(fig, "F3", "F3_tls_handshake.png")


# ------------------------------------------------------------------- F4-F6 --
def f4_f5_f6_e1():
    rows = read_csv("E1.csv")
    if rows is None:
        return
    by_server_conc = {}
    for r in rows:
        key = (r["server"], int(r["concurrency"]))
        by_server_conc.setdefault(key, []).append(r)

    concurrencies = sorted({int(r["concurrency"]) for r in rows})
    servers = sorted({r["server"] for r in rows})

    # F4: throughput vs concurrency, error bars
    fig, ax = plt.subplots(figsize=(6.5, 4.2))
    for server in servers:
        means, errs = [], []
        for c in concurrencies:
            vals = [r["requests_per_sec"] for r in by_server_conc.get((server, c), [])]
            m, ci = mean_ci95(vals)
            means.append(m)
            errs.append(ci)
        ax.errorbar(concurrencies, means, yerr=errs, marker="o", lw=2, capsize=4,
                    color=SERVER_COLOR.get(server, MUTED), label=server.capitalize())
    ax.set_xlabel("Concurrency (connections)")
    ax.set_ylabel("Throughput (requests/sec)")
    ax.set_xticks(concurrencies)
    ax.legend()
    add_caption("F4", "E1 throughput vs concurrency, Apache vs Nginx, error bars show "
                       "the full range across both repeats (n=2; not a confidence interval).")
    savefig(fig, "F4", "F4_e1_throughput.png")

    # F5: mean and p90 latency vs concurrency, small multiples per server
    fig, axes = plt.subplots(1, len(servers), figsize=(6.5 * len(servers) / 2, 4.2), sharey=True)
    if len(servers) == 1:
        axes = [axes]
    for ax, server in zip(axes, servers):
        mean_vals, p90_vals = [], []
        for c in concurrencies:
            rs = by_server_conc.get((server, c), [])
            m_mean, _ = mean_ci95([r["latency_mean_ms"] for r in rs])
            m_p90, _ = mean_ci95([r["latency_p90_ms"] for r in rs])
            mean_vals.append(m_mean)
            p90_vals.append(m_p90)
        ax.plot(concurrencies, mean_vals, marker="o", lw=2, color=SERVER_COLOR.get(server, MUTED),
                 label="mean")
        ax.plot(concurrencies, p90_vals, marker="s", lw=2, linestyle="--",
                 color=INK_SECONDARY, label="p90")
        ax.set_title(server.capitalize())
        ax.set_xlabel("Concurrency (connections)")
        ax.set_xticks(concurrencies)
        ax.legend()
    axes[0].set_ylabel("Latency (ms)")
    add_caption("F5", "E1 mean and 90th-percentile latency (wrk's own histogram reports "
                       "p50/p75/p90/p99, not a true p95) vs concurrency, one panel per server.")
    savefig(plt.gcf(), "F5", "F5_e1_latency.png")

    # F6: CPU comparison (memory omitted - see Discussion/limitations)
    fig, ax = plt.subplots(figsize=(5.5, 4.2))
    means, errs = [], []
    for server in servers:
        vals = [r["cpu_pct"] for r in rows if r["server"] == server and r["cpu_pct"] != ""]
        m, ci = mean_ci95(vals)
        means.append(m)
        errs.append(ci)
    ax.bar(servers, means, yerr=errs, color=[SERVER_COLOR.get(s, MUTED) for s in servers],
           capsize=4, width=0.5)
    ax.set_ylabel("CPU usage (%)")
    ax.set_xticklabels([s.capitalize() for s in servers])
    add_caption("F6", "E1 CPU usage, Apache vs Nginx, averaged across all concurrency "
                       "levels and repeats (error bars: full range across the 8 "
                       "concurrency/repeat observations per server, not a confidence "
                       "interval). Per-process memory was not reliably isolated from "
                       "pidstat's system-wide sampling; see Discussion 5.3.")
    savefig(fig, "F6", "F6_e1_cpu.png")


# --------------------------------------------------------------------- F7 ---
def f7_e2():
    rows = read_csv("E2.csv")
    hs_rows = read_csv("E2_handshake.csv")
    if rows is None and hs_rows is None:
        return
    fig, axes = plt.subplots(1, 2, figsize=(9, 4.2))

    if rows is not None:
        modes = ["http", "https"]
        means, errs = [], []
        for mode in modes:
            vals = [r["requests_per_sec"] for r in rows if r["mode"] == mode]
            m, ci = mean_ci95(vals)
            means.append(m)
            errs.append(ci)
        axes[0].bar(modes, means, yerr=errs, color=[BLUE, ORANGE], capsize=4, width=0.5)
        axes[0].set_ylabel("Throughput (requests/sec)")
        axes[0].set_xticklabels(["HTTP", "HTTPS"])

    if hs_rows is not None:
        versions = sorted({r["tls_version"] for r in hs_rows})
        means, errs = [], []
        for v in versions:
            vals = [r["total_s"] for r in hs_rows if r["tls_version"] == v]
            m, ci = mean_ci95(vals)
            means.append(m * 1000)
            errs.append(ci * 1000)
        axes[1].bar(versions, means, yerr=errs, color=[ORANGE, BLUE][: len(versions)], capsize=4, width=0.5)
        axes[1].set_ylabel("Total connect time (ms)")
        axes[1].set_xticklabels([v.upper().replace("TLS", "TLS ") for v in versions])

    add_caption("F7", "E2 transport cost: HTTP vs HTTPS throughput (left), and total "
                       "connection time for TLS 1.2 vs TLS 1.3 (right).")
    savefig(fig, "F7", "F7_e2_transport.png")


# --------------------------------------------------------------------- F8 ---
def f8_e3():
    rows = read_csv("E3.csv")
    if rows is None:
        return
    fig, ax = plt.subplots(figsize=(5.5, 4.2))
    paths = ["static", "proxied"]
    means, errs = [], []
    for p in paths:
        vals = [r["requests_per_sec"] for r in rows if r["path"] == p]
        m, ci = mean_ci95(vals)
        means.append(m)
        errs.append(ci)
    ax.bar(paths, means, yerr=errs, color=[BLUE, ORANGE], capsize=4, width=0.5)
    ax.set_ylabel("Throughput (requests/sec)")
    ax.set_xticklabels(["Static (Nginx)", "Proxied (gunicorn)"])
    add_caption("F8", "E3 reverse proxy overhead: static file throughput vs the same "
                       "site's /api/health proxied through gunicorn.")
    savefig(fig, "F8", "F8_e3_proxy_overhead.png")


# --------------------------------------------------------------------- F9 ---
def f9_e4():
    rows = read_csv("E4_ports.csv")
    if rows is None:
        return
    fig, ax = plt.subplots(figsize=(6, 4.2))
    hosts = sorted({r["host"] for r in rows})
    states = ["before", "after"]
    width = 0.35
    import numpy as np
    x = range(len(hosts))
    for i, state in enumerate(states):
        vals = [int(next(r["open_port_count"] for r in rows if r["host"] == h and r["state"] == state)) for h in hosts]
        offset = (i - 0.5) * width
        ax.bar([xi + offset for xi in x], vals, width=width,
               color=BLUE if state == "before" else ORANGE, label=state.capitalize())
    ax.set_xticks(list(x))
    ax.set_xticklabels([h.capitalize() for h in hosts])
    ax.set_ylabel("Open ports (count)")
    ax.yaxis.set_major_locator(mticker.MaxNLocator(integer=True))
    ax.legend()
    add_caption("F9", "E4 attack surface: open TCP ports on web and db, before vs "
                       "after Phase 4 hardening (see Table in Results for the exact port lists).")
    savefig(fig, "F9", "F9_e4_open_ports.png")


# -------------------------------------------------------------------- F10 ---
def f10_e5():
    rows = read_csv("E5.csv")
    if rows is None:
        return
    fig, ax = plt.subplots(figsize=(7, 4.2))
    labels = [r["scenario"] for r in rows]
    values = [float(r["elapsed_seconds"]) for r in rows]
    colors = [ORANGE if "unprotected" in l else BLUE for l in labels]
    bars = ax.barh(labels, values, color=colors)
    for bar, r in zip(bars, rows):
        label = "credential found" if r["credential_found"] else "banned - no credential found"
        ax.text(bar.get_width() + 0.5, bar.get_y() + bar.get_height() / 2,
                label, va="center", fontsize=8, color=INK_SECONDARY)
    ax.set_xlabel("Elapsed time (seconds) - see caption")
    ax.set_xlim(right=max(values) * 1.35)
    add_caption("F10", "E5 brute-force timeline: orange bars show time to a successful "
                        "guess when unprotected. Blue bars show elapsed time for the "
                        "PROTECTED attack attempt as a whole, not how fast Fail2Ban banned "
                        "the attacker (the ban itself lands within seconds - see Section "
                        "4.5/5.2): the test harness's own connectivity-retry wrapper keeps "
                        "retrying the attack tool against what is, correctly, now a "
                        "permanent block, so this number reflects that retry budget being "
                        "exhausted, not attack resistance. The outcome that matters is the "
                        "label: credential found (orange) vs banned with no credential "
                        "found (blue), for SSH and the Nginx basic-auth demo path.")
    savefig(fig, "F10", "F10_e5_bruteforce_timeline.png")


# -------------------------------------------------------------------- F11 ---
def f11_e6():
    rows = read_csv("E6.csv")
    if rows is None:
        return
    fig, ax = plt.subplots(figsize=(6, 4.2))
    scenarios = [r["scenario"] for r in rows]
    codes = ["http_200", "http_429", "http_503", "other_codes"]
    code_colors = {"http_200": BLUE, "http_429": ORANGE, "http_503": "#e34948",
                   "other_codes": MUTED}
    code_labels = {"http_200": "HTTP 200", "http_429": "HTTP 429", "http_503": "HTTP 503",
                   "other_codes": "Other (504 etc.)"}
    bottoms = [0] * len(scenarios)
    for code in codes:
        vals = [int(r.get(code, 0) or 0) for r in rows]
        if not any(vals):
            continue
        ax.bar(scenarios, vals, bottom=bottoms, color=code_colors[code], label=code_labels[code])
        bottoms = [b + v for b, v in zip(bottoms, vals)]
    ax.set_ylabel("Request count (sample)")
    ax.set_xticklabels(["With limit_req", "Without limit_req"])
    ax.legend()
    add_caption("F11", "E6 status code distribution for a burst of sampled requests to "
                        "/api/health, with vs without Nginx limit_req active (limit_req_status "
                        "429 configured; RFC 6585's 429 is the correct code for rate limiting, "
                        "replacing Nginx's 503 default). Without the limiter, requests are not "
                        "rejected outright but queue against the gunicorn backend and mostly "
                        "time out (504), at far lower throughput than the limiter's quick, "
                        "cheap 429 rejections - see Discussion 5.3.")
    savefig(fig, "F11", "F11_e6_status_codes.png")


# -------------------------------------------------------------------- F13 ---
def f13_e8():
    rows = read_csv("E8.csv")
    if rows is None:
        return
    r = rows[0]
    detected = r["detected_active_again_after_seconds"] or "0"
    fig, ax = plt.subplots(figsize=(7, 2.6))
    ax.barh(["nginx"], [float(detected)], color=BLUE)
    ax.axvline(0, color=INK, lw=1)
    ax.text(0, 1.15, "SIGKILL", color=INK, fontsize=9)
    ax.text(float(detected), 1.15, "detected + restarted", color=INK, fontsize=9, ha="right")
    ax.set_xlabel("Seconds since kill")
    ax.set_yticks([])
    add_caption("F13", "E8 resilience timeline: seconds between killing Nginx and systemd's "
                        "Restart=on-failure bringing it back up (measured with host-side "
                        "timestamps; see Discussion 5.3 for why the custom monitor script "
                        "could not independently confirm the same event this run).")
    savefig(fig, "F13", "F13_e8_resilience_timeline.png")


# -------------------------------------------------------------------- F14 ---
def f14_e9():
    summary_path = PROCESSED / "E9_summary.md"
    if not summary_path.exists():
        print("SKIP F14: evidence/processed/E9_summary.md not found")
        return
    import re
    text = summary_path.read_text()
    before = re.search(r"## Before hardening\nGrade: (\S+)", text)
    after = re.search(r"## After hardening\nGrade: (\S+)", text)
    before_label = (before.group(1) if before else "n/a").replace("_", " ")
    after_label = (after.group(1) if after else "n/a").replace("_", " ")
    rows = [("Before Phase 3 hardening", before_label),
            ("After Phase 3 hardening", after_label)]

    fig, ax = plt.subplots(figsize=(6, 2))
    ax.axis("off")
    table = ax.table(cellText=rows, colLabels=["State", "testssl.sh overall grade"],
                      cellLoc="left", colLoc="left", loc="center")
    table.auto_set_font_size(False)
    table.set_fontsize(10)
    table.scale(1, 1.8)
    add_caption("F14", "E9 TLS quality: testssl.sh overall grade before vs after "
                        "Phase 3 TLS hardening.")
    savefig(fig, "F14", "F14_e9_tls_grade.png")


def main():
    FIG_DIR.mkdir(parents=True, exist_ok=True)
    f1_architecture()
    f2_request_flow()
    f3_tls_handshake()
    f4_f5_f6_e1()
    f7_e2()
    f8_e3()
    f9_e4()
    f10_e5()
    f11_e6()
    f13_e8()
    f14_e9()

    CAPTIONS.write_text("# Figure captions\n\n" + "\n\n".join(captions) + "\n")
    print(f"\nWrote {CAPTIONS} ({len(captions)} captions)")


if __name__ == "__main__":
    main()
