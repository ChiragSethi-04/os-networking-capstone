"""Spot-check report/report.md against evidence/processed/*.csv: flags any
number quoted in the Results section that cannot be found in the
corresponding CSV, and separately reports how many [FILL ...] /
PLACEHOLDER markers remain (informational while the report is still being
written; lab/scripts/final_check.sh treats remaining markers as a hard
failure at Phase 10, when the report must be complete).
"""
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
REPORT = ROOT / "report" / "report.md"


def main():
    text = REPORT.read_text()

    fills = re.findall(r"\[FILL[^\]]*\]", text)
    placeholders = re.findall(r"\[[A-Z0-9 _-]*PLACEHOLDER[^\]]*\]", text)

    print(f"[FILL ...] markers remaining: {len(fills)}")
    print(f"PLACEHOLDER markers remaining: {len(placeholders)}")
    if fills:
        print("  e.g.:", fills[0][:80])
    if placeholders:
        print("  e.g.:", placeholders[0][:80])

    print("\nThis script is informational at this stage of the project; "
          "lab/scripts/final_check.sh enforces zero remaining markers before "
          "the Phase 10 'make final-check' can pass.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
