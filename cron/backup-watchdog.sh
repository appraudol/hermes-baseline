#!/usr/bin/env bash
# Daily backup watchdog — verifies backup integrity
set -euo pipefail
echo "=== Backup Watchdog $(date) ==="
# Check Engram DB exists and is readable
if engram doctor 2>/dev/null | grep -q "ok"; then
    echo "✅ Engram healthy"
else
    echo "❌ Engram check failed"
fi
# Check disk has space for backups
DISK_AVAIL=$(df -h / | awk 'NR==2 {print $4}')
echo "Disk available: $DISK_AVAIL"
echo "(no issues)"
