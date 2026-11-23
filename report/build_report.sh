#!/usr/bin/env bash
# Purpose: build report/Capstone_Report.pdf and .docx from report.md via
# pandoc + XeLaTeX, with an IEEE citation style. Falls back to pandoc's
# HTML -> headless-Chrome PDF path if XeLaTeX is unavailable (Part E of
# the guide's troubleshooting cheat sheet).
# Author: [GROUP MEMBER PLACEHOLDER]
# Date: [DATE PLACEHOLDER]
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR/report"

CSL="ieee.csl"
if [[ ! -f "$CSL" ]]; then
  echo "Fetching IEEE citation style (ieee.csl) from the Zotero styles repository..."
  curl -fsSL -o "$CSL" \
    "https://raw.githubusercontent.com/citation-style-language/styles/master/ieee.csl" \
    || echo "WARNING: could not fetch ieee.csl; citations will use pandoc's default style."
fi

PANDOC_ARGS=(report.md -o Capstone_Report.pdf --from=markdown --pdf-engine=xelatex
             --citeproc --toc -V geometry:margin=2.54cm -V secnumdepth=-2)
[[ -f "$CSL" ]] && PANDOC_ARGS+=(--csl "$CSL")

if command -v xelatex >/dev/null 2>&1; then
  echo "Building PDF with pandoc + XeLaTeX..."
  pandoc "${PANDOC_ARGS[@]}"
else
  echo "xelatex not found, falling back to HTML -> headless Chrome PDF."
  pandoc report.md -o Capstone_Report.html --from=markdown --citeproc --toc \
    $( [[ -f "$CSL" ]] && echo --csl "$CSL" )
  CHROME="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
  if [[ -x "$CHROME" ]]; then
    "$CHROME" --headless --disable-gpu --print-to-pdf=Capstone_Report.pdf Capstone_Report.html
  else
    echo "ERROR: neither xelatex nor Chrome found; PDF not produced." >&2
    exit 1
  fi
fi

echo "Building DOCX..."
pandoc report.md -o Capstone_Report.docx --from=markdown --citeproc --toc \
  $( [[ -f "$CSL" ]] && echo --csl "$CSL" )

echo "Report built: report/Capstone_Report.pdf, report/Capstone_Report.docx"
