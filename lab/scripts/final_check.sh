#!/usr/bin/env bash
# Purpose: Phase 10 final QA. Rebuilds from scratch and checks every
# deliverable exists and is internally consistent. Prints PASS/FAIL per item.
# Author: [GROUP MEMBER PLACEHOLDER]
# Date: [DATE PLACEHOLDER]
set -uo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT_DIR"
fail=0
check() {
  local label="$1"; shift
  if "$@" >/dev/null 2>&1; then
    echo "PASS: $label"
  else
    echo "FAIL: $label"
    fail=1
  fi
}

echo "=== Rebuilding from a clean VM state (this deletes and relaunches all VMs) ==="
read -r -p "Type 'yes' to delete and relaunch web/db/attacker now, anything else to skip the rebuild: " confirm
if [[ "$confirm" == "yes" ]]; then
  multipass delete web db attacker --purge 2>/dev/null || true
  make lab && make test
else
  echo "Skipping full VM rebuild (ran final_check against the current lab state instead)."
fi

check "make bench-quick"        bash -c "make bench-quick"
check "make figures"            bash -c "make figures"
check "make report"             bash -c "make report"
check "report PDF exists"       test -f report/Capstone_Report.pdf
check "report DOCX exists"      test -f report/Capstone_Report.docx

echo "--- no remaining [FILL]/PLACEHOLDER markers in report.md ---"
VENV_PY=".venv/bin/python3"; [[ -x "$VENV_PY" ]] || VENV_PY="python3"
markers=$("$VENV_PY" -c "
import re
text = open('report/report.md').read()
print(len(re.findall(r'\[FILL[^\]]*\]', text)) + len(re.findall(r'\[[A-Z0-9 _-]*PLACEHOLDER[^\]]*\]', text)))
")
if [[ "$markers" == "0" ]]; then
  echo "PASS: report has no remaining FILL/PLACEHOLDER markers"
else
  echo "FAIL: report still has $markers FILL/PLACEHOLDER markers"
  fail=1
fi

check "no em dashes in report"  bash -c '! grep -nP "\x{2014}" report/report.md'
check "slides built"            bash -c "make slides"
check "deck.pptx exists"        test -f slides/deck.pptx
check "demo_script.md exists"   test -f docs/demo_script.md
check "viva_qa.md has >=40 Q"   bash -c 'test $(grep -cE "^[0-9]+\." docs/viva_qa.md) -ge 40'
check "peer_review_given.md exists"    test -f docs/peer_review_given.md
check "peer_review_response.md exists" test -f docs/peer_review_response.md
check "verification_checklist.md exists" test -f docs/verification_checklist.md
check "reproduce.md exists"     test -f docs/reproduce.md
check "rubric_audit.md exists"  test -f docs/rubric_audit.md

echo ""
echo "--- packaging deliverables/ ---"
mkdir -p deliverables
cp -f report/Capstone_Report.pdf report/Capstone_Report.docx deliverables/ 2>/dev/null || true
cp -f slides/deck.pptx deliverables/ 2>/dev/null || true
[[ -f slides/deck.pdf ]] && cp -f slides/deck.pdf deliverables/
cp -rf figures deliverables/figures 2>/dev/null || true
cp -f docs/demo_script.md docs/viva_qa.md deliverables/ 2>/dev/null || true
git archive --format=zip -o deliverables/repository.zip HEAD 2>/dev/null \
  || echo "NOTE: git archive skipped (commit pending changes first for a complete zip)"
check "deliverables/ populated" test -f deliverables/Capstone_Report.pdf

echo ""
if [[ $fail -eq 0 ]]; then
  echo "FINAL CHECK: ALL PASS"
else
  echo "FINAL CHECK: SOME ITEMS FAILED (see above)"
  exit 1
fi
