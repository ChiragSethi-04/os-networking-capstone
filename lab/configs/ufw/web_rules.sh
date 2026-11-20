#!/usr/bin/env bash
# Purpose: ufw rules for the web VM. Default deny incoming, allow outgoing,
# SSH rate-limited, HTTP/HTTPS open, logging on.
# Source of truth: this file. Applied by lab/scripts/harden.sh via
# `multipass exec web -- sudo bash -s` < this file.
set -euo pipefail

sudo ufw default deny incoming
sudo ufw default allow outgoing
sudo ufw logging on

sudo ufw limit 22/tcp comment 'SSH, rate-limited by ufw'
sudo ufw allow 80/tcp comment 'HTTP'
sudo ufw allow 443/tcp comment 'HTTPS'

sudo ufw --force enable
sudo ufw status verbose
