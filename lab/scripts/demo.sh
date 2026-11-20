#!/usr/bin/env bash
# Purpose: pre-flight check right before presenting - confirms the lab is
# up and prints the WEB_IP/DB_IP to paste into the browser and terminal
# commands in docs/demo_script.md (the actual demo is driven by hand from
# that script, not by this one, since it is presented live).
# Author: [GROUP MEMBER PLACEHOLDER]
# Date: [DATE PLACEHOLDER]
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT_DIR"
source lab/.env

echo "=== Demo pre-flight ==="
multipass list
echo ""
echo "WEB_IP=${WEB_IP}"
echo "DB_IP=${DB_IP}"
echo "ATT_IP=${ATT_IP}"
echo ""
echo "https://${WEB_IP}/  <- open this in the browser now"
echo ""
echo "Follow docs/demo_script.md step by step from here."
