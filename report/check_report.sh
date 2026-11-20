#!/usr/bin/env bash
# Purpose: Phase 8 acceptance check - structure, formatting, citations,
# page count, no em dashes, every figure/table referenced.
# Author: [GROUP MEMBER PLACEHOLDER]
# Date: [DATE PLACEHOLDER]
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"
fail=0

echo "--- em dash check (must be empty) ---"
if grep -nP "\x{2014}" report/report.md; then
  echo "FAIL: em dash found in report.md"
  fail=1
else
  echo "OK: no em dashes"
fi

echo "--- required section headings present ---"
for heading in "# Executive Summary" "# 1. Introduction" "# 2. Literature Review" \
               "# 3. Methodology" "# 4. Results and Findings" "# 5. Discussion and Analysis" \
               "# 6. Conclusion" "# 7. Recommendations" "# References" "# Appendices"; do
  if grep -qF "$heading" report/report.md; then
    echo "OK: found '$heading'"
  else
    echo "FAIL: missing '$heading'"
    fail=1
  fi
done

echo "--- every figure referenced in text ---"
if [[ -f figures/captions.md ]]; then
  for fid in $(grep -oE '^\*\*F[0-9]+\*\*' figures/captions.md | tr -d '*'); do
    if grep -q "Figure $fid\|$fid" report/report.md; then
      echo "OK: $fid referenced"
    else
      echo "FAIL: $fid not referenced in report.md"
      fail=1
    fi
  done
else
  echo "SKIP: figures/captions.md not found yet (run make figures first)"
fi

echo "--- page count (PDF) ---"
if [[ -f report/Capstone_Report.pdf ]] && command -v mdls >/dev/null 2>&1; then
  pages=$(mdls -name kMDItemNumberOfPages -raw report/Capstone_Report.pdf 2>/dev/null || echo "")
  echo "Total PDF pages (including preliminary/appendices): ${pages:-unknown}"
  echo "Note: 10-15 page target is for MAIN BODY ONLY (excludes cover, references, appendices);"
  echo "check manually against the section boundaries."
else
  echo "SKIP: report/Capstone_Report.pdf not found yet (run make report first)"
fi

echo "--- numbers consistency: CSV values appear in report text (spot check) ---"
VENV_PY=".venv/bin/python3"
[[ -x "$VENV_PY" ]] || VENV_PY="python3"
"$VENV_PY" report/check_numbers.py || fail=1

if [[ $fail -eq 0 ]]; then
  echo "REPORT CHECK: PASS"
else
  echo "REPORT CHECK: FAIL"
  exit 1
fi
