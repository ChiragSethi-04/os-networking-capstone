#!/usr/bin/env bash
# Purpose: restore each VM's clean-baseline snapshot, then re-run Phases
# 2-5 so the lab is back in its final hardened, demo-ready state with no
# leftover E5 demo accounts, bans, or log noise.
# Author: [GROUP MEMBER PLACEHOLDER]
# Date: [DATE PLACEHOLDER]
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT_DIR"

for name in web db attacker; do
  echo "[$name] restoring clean-baseline snapshot..."
  multipass stop "$name" || true
  multipass restore "$name".clean-baseline --destructive
  multipass start "$name"
done

echo "Waiting for VMs to settle..."
for name in web db attacker; do
  multipass exec "$name" -- cloud-init status --wait || true
done

bash lab/scripts/deploy_site.sh
bash lab/scripts/harden.sh
bash lab/scripts/setup_monitoring.sh

echo "Demo reset complete. Lab is in its final hardened state."
