#!/usr/bin/env bash
# Weekly system updater — applies apt updates, runs health check
set -euo pipefail
echo "=== System Updater $(date) ==="
sudo apt-get update -qq
UPGRADES=$(apt list --upgradable 2>/dev/null | wc -l)
if [[ $UPGRADES -gt 1 ]]; then
    echo "📦 $((UPGRADES-1)) packages to upgrade"
    sudo apt-get upgrade -y -qq
    echo "✅ Upgrades applied"
else
    echo "✅ System up to date"
fi
# Check if reboot needed
if [[ -f /var/run/reboot-required ]]; then
    echo "⚠️  Reboot required"
fi
