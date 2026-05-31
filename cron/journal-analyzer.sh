#!/usr/bin/env bash
# Daily journal analyzer — checks systemd journal for failures, OOMs, critical errors
# Silent when no issues found.

set -euo pipefail

ISSUES=0

# 1. Service failures in last 24h
FAILED=$(sudo /usr/bin/journalctl --since "24 hours ago" -p err --no-pager 2>/dev/null | grep -c "failed\|error" || echo "0")
if [[ ${FAILED:-0} -gt 0 ]]; then
    echo "⚠️  Systemd errors (24h): $FAILED entries"
    echo "   Sample:"
    sudo /usr/bin/journalctl --since "24 hours ago" -p err --no-pager 2>/dev/null | tail -3
    ISSUES=$((ISSUES+1))
fi

# 2. OOM killer events
OOM=$(sudo /usr/bin/journalctl --since "24 hours ago" --no-pager 2>/dev/null | grep -c "oom-killer\|Out of memory" || echo "0")
if [[ ${OOM:-0} -gt 0 ]]; then
    echo "⚠️  OOM events (24h): $OOM"
    ISSUES=$((ISSUES+1))
fi

# 3. Disk space
DISK_USE=$(df -h / | awk 'NR==2 {print $5}' | sed 's/%//')
if [[ ${DISK_USE:-0} -gt 90 ]]; then
    echo "⚠️  Disk usage: ${DISK_USE}%"
    ISSUES=$((ISSUES+1))
fi

if [[ $ISSUES -eq 0 ]]; then
    echo "(no issues)"
fi
