#!/usr/bin/env bash
# Daily log inspector — checks auth, syslog, and CrowdSec logs for anomalies
# Silent when no anomalies detected.

set -euo pipefail

ANOMALIES=0

# 1. Check auth.log for brute-force attempts
FAILED_SSH=$(sudo /usr/bin/cat /var/log/auth.log 2>/dev/null | grep "Failed password" | wc -l)
if [[ $FAILED_SSH -gt 10 ]]; then
    echo "⚠️  SSH brute-force: $FAILED_SSH failed attempts since last rotation"
    ANOMALIES=$((ANOMALIES+1))
fi

# 2. Check for sudo failures
SUDO_FAIL=$(sudo /usr/bin/cat /var/log/auth.log 2>/dev/null | grep "sudo.*FAILED" | wc -l)
if [[ $SUDO_FAIL -gt 0 ]]; then
    echo "⚠️  Sudo failures: $SUDO_FAIL attempts"
    ANOMALIES=$((ANOMALIES+1))
fi

# 3. Check syslog for kernel errors
KERN_ERR=$(sudo /usr/bin/cat /var/log/syslog 2>/dev/null | grep -i "error\|fail\|segfault" | wc -l)
if [[ $KERN_ERR -gt 5 ]]; then
    echo "⚠️  System errors: $KERN_ERR kernel/system errors"
    ANOMALIES=$((ANOMALIES+1))
fi

# 4. CrowdSec decisions
if command -v cscli &>/dev/null; then
    BANNED=$(sudo cscli decisions list -o json 2>/dev/null | jq 'length' 2>/dev/null || echo "0")
    if [[ ${BANNED:-0} -gt 0 ]]; then
        echo "🛡️  CrowdSec: $BANNED IPs banned"
    fi
fi

if [[ $ANOMALIES -eq 0 ]]; then
    echo "(no anomalies)"
fi
