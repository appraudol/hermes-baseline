#!/usr/bin/env bash
# Weekly disk cleaner — removes old logs, caches, temp files
set -euo pipefail
echo "=== Disk Cleaner $(date) ==="
# Clean apt cache
sudo apt-get clean -qq
# Clean journal older than 7 days
sudo journalctl --vacuum-time=7d --quiet
# Clean /tmp files older than 3 days
find /tmp -type f -mtime +3 -delete 2>/dev/null || true
echo "✅ Cleanup complete"
df -h / | awk 'NR==2 {print "Disk: "$3"/"$2" ("$5" used)"}'
