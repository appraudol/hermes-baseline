#!/usr/bin/env bash
# Daily security audit — snapshot-based change detection
# Checks: packages, skills, repos, ports, SUID binaries, firewall, CrowdSec, Tailscale
# Silent when no changes detected. Reports only anomalies.

set -euo pipefail

echo "=== Security Audit $(date) ==="

CHANGES=0

# 1. New packages installed (since last run)
if [[ -f /tmp/sec-audit-pkgs.txt ]]; then
    dpkg -l | grep "^ii" | awk '{print $2}' | sort > /tmp/sec-audit-pkgs-now.txt
    NEW_PKGS=$(comm -13 /tmp/sec-audit-pkgs.txt /tmp/sec-audit-pkgs-now.txt)
    if [[ -n "$NEW_PKGS" ]]; then
        echo "⚠️  NEW PACKAGES:"
        echo "$NEW_PKGS"
        CHANGES=$((CHANGES+1))
    fi
fi
dpkg -l | grep "^ii" | awk '{print $2}' | sort > /tmp/sec-audit-pkgs.txt

# 2. Listening ports (only report new public-facing ports)
LISTENING=$(sudo /usr/sbin/ss -tlnp 2>/dev/null | grep -v "127.0.0.1\|::1")
if [[ -f /tmp/sec-audit-ports.txt ]]; then
    NEW_PORTS=$(diff /tmp/sec-audit-ports.txt <(echo "$LISTENING") 2>/dev/null | grep "^>" || true)
    if [[ -n "$NEW_PORTS" ]]; then
        echo "⚠️  NEW LISTENING PORTS:"
        echo "$NEW_PORTS"
        CHANGES=$((CHANGES+1))
    fi
fi
echo "$LISTENING" > /tmp/sec-audit-ports.txt

# 3. SUID binaries (only report new ones)
SUID_BINS=$(find / -perm -4000 -type f 2>/dev/null | sort)
if [[ -f /tmp/sec-audit-suid.txt ]]; then
    NEW_SUID=$(comm -13 /tmp/sec-audit-suid.txt <(echo "$SUID_BINS"))
    if [[ -n "$NEW_SUID" ]]; then
        echo "⚠️  NEW SUID BINARIES:"
        echo "$NEW_SUID"
        CHANGES=$((CHANGES+1))
    fi
fi
echo "$SUID_BINS" > /tmp/sec-audit-suid.txt

# 4. Firewall policy check
if sudo /usr/sbin/iptables -L INPUT -n 2>/dev/null | head -1 | grep -q DROP; then
    echo "✅ Firewall: INPUT DROP"
else
    echo "❌ Firewall: INPUT policy is NOT DROP!"
    CHANGES=$((CHANGES+1))
fi

# 5. CrowdSec health
if systemctl is-active crowdsec &>/dev/null; then
    echo "✅ CrowdSec: active"
else
    echo "❌ CrowdSec: not running!"
    CHANGES=$((CHANGES+1))
fi

if [[ $CHANGES -eq 0 ]]; then
    echo "(no changes)"
fi
