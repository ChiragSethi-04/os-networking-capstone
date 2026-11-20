#!/usr/bin/env bash
# Disables Ubuntu's unattended-upgrades auto-reboot (and the service
# entirely), after it was caught rebooting the web VM mid-Phase-4 without
# warning ("Unattended Upgrades Shutdown" in journalctl) - see
# docs/decisions.md. Deployed to all three VMs: a lab we fully control the
# package set for has no need for background auto-updates, and a surprise
# reboot during a benchmark run or the live demo would be far worse than
# forgoing automatic security patches for the lab's short lifetime.
set -euo pipefail
systemctl stop unattended-upgrades.service 2>/dev/null || true
systemctl disable unattended-upgrades.service 2>/dev/null || true
systemctl stop apt-daily-upgrade.timer apt-daily.timer 2>/dev/null || true
systemctl disable apt-daily-upgrade.timer apt-daily.timer 2>/dev/null || true
echo 'APT::Periodic::Enable "0";' > /etc/apt/apt.conf.d/52-capstone-no-auto-updates
echo 'Unattended-Upgrade::Automatic-Reboot "false";' >> /etc/apt/apt.conf.d/52-capstone-no-auto-updates
rm -f /var/run/reboot-required /var/run/reboot-required.pkgs
