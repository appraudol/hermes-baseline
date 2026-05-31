#!/usr/bin/env bash
# =============================================================================
# Hermes Baseline Deploy — v1.0
# =============================================================================
# Deploy a production-ready Hermes LXC from bare Ubuntu Server 22.04.
#
# Usage:
#   sudo bash baseline-deploy.sh --profile <name> [--recover] [--skip-verify]
#
# What it does:
#   1. System update + core dependencies
#   2. Firewall hardening (iptables INPUT DROP)
#   3. SSH hardening
#   4. fail2ban + CrowdSec
#   5. Netdata monitoring (bind 127.0.0.1)
#   6. Hermes Agent installation
#   7. Global config (providers, fallback, memory, security)
#   8. 20 baseline skills
#   9. Cron jobs (7 no_agent + 2 LLM)
#  10. systemd services (gateway, dashboard, https proxy)
#  11. Profile import → replaces generic default
#  12. Post-deploy verification
# =============================================================================

set -euo pipefail

# ── Configuration ───────────────────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_DIR="${SCRIPT_DIR}/config"
SYSTEMD_DIR="${SCRIPT_DIR}/systemd"
CRON_DIR="${SCRIPT_DIR}/cron"
LOG_FILE="/var/log/hermes-baseline-deploy.log"

# Defaults
PROFILE_NAME=""
RECOVER_MODE=false
SKIP_VERIFY=false
VAULTWARDEN_URL="https://10.1.1.10:8443"
HERMES_HOME="/home/hermes/.hermes"
HERMES_USER="hermes"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# ── Parse Arguments ─────────────────────────────────────────────────────────
while [[ $# -gt 0 ]]; do
    case "$1" in
        --profile)
            PROFILE_NAME="$2"
            shift 2
            ;;
        --recover)
            RECOVER_MODE=true
            shift
            ;;
        --skip-verify)
            SKIP_VERIFY=true
            shift
            ;;
        *)
            echo "Unknown argument: $1"
            echo "Usage: sudo bash baseline-deploy.sh --profile <name> [--recover] [--skip-verify]"
            exit 1
            ;;
    esac
done

if [[ -z "$PROFILE_NAME" ]]; then
    echo -e "${RED}ERROR: --profile is required${NC}"
    echo "Usage: sudo bash baseline-deploy.sh --profile <name>"
    exit 1
fi

# ── Logging ─────────────────────────────────────────────────────────────────
exec > >(tee -a "$LOG_FILE") 2>&1
echo "=== Hermes Baseline Deploy v1.0 ==="
echo "Profile: $PROFILE_NAME"
echo "Date:    $(date)"
echo "Recover: $RECOVER_MODE"
echo ""

# ── Helper Functions ────────────────────────────────────────────────────────
step() { echo -e "${BLUE}[$1/$TOTAL_STEPS]${NC} $2"; }
ok()   { echo -e "  ${GREEN}✅${NC} $1"; }
warn() { echo -e "  ${YELLOW}⚠️${NC}  $1"; }
fail() { echo -e "  ${RED}❌${NC} $1"; exit 1; }

TOTAL_STEPS=12
CURRENT_STEP=0

next_step() {
    CURRENT_STEP=$((CURRENT_STEP + 1))
    echo ""
}

# ── Root Check ──────────────────────────────────────────────────────────────
if [[ $EUID -ne 0 ]]; then
    echo "ERROR: This script must be run as root (sudo)."
    exit 1
fi

# ── Step 1: System Update + Dependencies ────────────────────────────────────
step 1 "System update + core dependencies"
next_step

apt-get update -qq
apt-get install -y -qq \
    curl wget git unzip jq python3 python3-pip \
    fail2ban netdata \
    ufw 2>/dev/null || true

# Engram CLI
if ! command -v engram &>/dev/null; then
    curl -fsSL https://get.engram.sh | bash
    ok "Engram CLI installed"
else
    ok "Engram CLI already installed"
fi

# Disable UFW (we use raw iptables)
if command -v ufw &>/dev/null; then
    ufw disable 2>/dev/null || true
    ok "UFW disabled (using iptables directly)"
fi

ok "System updated"

# ── Step 2: Firewall (iptables) ─────────────────────────────────────────────
step 2 "Firewall hardening (iptables)"
next_step

if [[ -f "${CONFIG_DIR}/iptables-rules.v4" ]]; then
    cp "${CONFIG_DIR}/iptables-rules.v4" /etc/iptables/rules.v4
    iptables-restore < /etc/iptables/rules.v4
    apt-get install -y -qq iptables-persistent
    netfilter-persistent save
    ok "iptables rules applied"
    
    # Verify
    if iptables -L INPUT -n 2>/dev/null | head -1 | grep -q DROP; then
        ok "iptables INPUT policy = DROP"
    else
        fail "iptables INPUT policy is NOT DROP"
    fi
else
    fail "iptables rules file not found: ${CONFIG_DIR}/iptables-rules.v4"
fi

# ── Step 3: SSH Hardening ───────────────────────────────────────────────────
step 3 "SSH hardening"
next_step

# Backup original
cp /etc/ssh/sshd_config /etc/ssh/sshd_config.bak.$(date +%Y%m%d) 2>/dev/null || true

# Apply hardening
if [[ -f "${CONFIG_DIR}/sshd_config.hardened" ]]; then
    cp "${CONFIG_DIR}/sshd_config.hardened" /etc/ssh/sshd_config.d/99-hardening.conf
else
    # Inline hardening
    cat > /etc/ssh/sshd_config.d/99-hardening.conf << 'SSHEOF'
PermitRootLogin no
PasswordAuthentication no
MaxAuthTries 2
MaxSessions 2
LoginGraceTime 30
X11Forwarding no
AllowTcpForwarding no
AllowAgentForwarding no
ClientAliveInterval 120
ClientAliveCountMax 2
LogLevel VERBOSE
SSHEOF
fi

# Validate and reload
if sshd -t; then
    systemctl reload sshd
    ok "SSH hardened (root=no, password=no, max_auth=2)"
else
    fail "SSH config validation failed"
fi

# ── Step 4: fail2ban + CrowdSec ─────────────────────────────────────────────
step 4 "fail2ban + CrowdSec"
next_step

# fail2ban jail for sshd
if [[ -f "${CONFIG_DIR}/jail.local" ]]; then
    cp "${CONFIG_DIR}/jail.local" /etc/fail2ban/jail.local
else
    cat > /etc/fail2ban/jail.local << 'F2BEOF'
[sshd]
enabled = true
port = 22
filter = sshd
logpath = /var/log/auth.log
maxretry = 3
bantime = 3600
findtime = 600
F2BEOF
fi
systemctl restart fail2ban
ok "fail2ban active (sshd jail)"

# CrowdSec
if ! command -v cscli &>/dev/null; then
    curl -s https://install.crowdsec.net | sh
    apt-get install -y -qq crowdsec-firewall-bouncer-iptables
fi
systemctl enable --now crowdsec
ok "CrowdSec active"

# ── Step 5: Netdata ─────────────────────────────────────────────────────────
step 5 "Netdata monitoring (bind 127.0.0.1)"
next_step

if [[ -f "${CONFIG_DIR}/netdata.conf" ]]; then
    cp "${CONFIG_DIR}/netdata.conf" /etc/netdata/netdata.conf
else
    cat >> /etc/netdata/netdata.conf << 'NDEOF'
[web]
    bind to = 127.0.0.1
NDEOF
fi
systemctl restart netdata
ok "Netdata bound to 127.0.0.1:19999"

# ── Step 6: Hermes Installation ─────────────────────────────────────────────
step 6 "Hermes Agent installation"
next_step

if [[ ! -d "$HERMES_HOME" ]]; then
    # Create hermes user if it doesn't exist
    if ! id "$HERMES_USER" &>/dev/null; then
        useradd -m -s /bin/bash "$HERMES_USER"
        usermod -aG sudo "$HERMES_USER"
        ok "User $HERMES_USER created"
    fi
    
    # Install Hermes
    su - "$HERMES_USER" -c "curl -fsSL https://get.hermes-agent.com | bash"
    ok "Hermes installed"
else
    ok "Hermes already installed"
fi

# ── Step 7: Global Config ──────────────────────────────────────────────────
step 7 "Global config apply"
next_step

if [[ -f "${CONFIG_DIR}/hermes-config.yaml" ]]; then
    # Merge global config sections into Hermes config
    if [[ -f "$HERMES_HOME/config.yaml" ]]; then
        # Backup original
        cp "$HERMES_HOME/config.yaml" "$HERMES_HOME/config.yaml.bak.$(date +%Y%m%d)"
    fi
    cp "${CONFIG_DIR}/hermes-config.yaml" "$HERMES_HOME/config.yaml"
    chown "$HERMES_USER:$HERMES_USER" "$HERMES_HOME/config.yaml"
    ok "Global config applied"
else
    fail "hermes-config.yaml not found in ${CONFIG_DIR}"
fi

# ── Step 8: Skills ──────────────────────────────────────────────────────────
step 8 "Baseline skills (20)"
next_step

if [[ -d "${SCRIPT_DIR}/skills" ]]; then
    mkdir -p "$HERMES_HOME/skills"
    cp -r "${SCRIPT_DIR}/skills/"* "$HERMES_HOME/skills/"
    chown -R "$HERMES_USER:$HERMES_USER" "$HERMES_HOME/skills"
    SKILL_COUNT=$(find "$HERMES_HOME/skills" -name "SKILL.md" | wc -l)
    ok "$SKILL_COUNT skills installed"
else
    warn "No skills directory found — skills must be installed manually"
fi

# ── Step 9: Cron Jobs ───────────────────────────────────────────────────────
step 9 "Cron jobs"
next_step

if [[ -d "$CRON_DIR" ]]; then
    mkdir -p "$HERMES_HOME/scripts"
    cp "$CRON_DIR"/* "$HERMES_HOME/scripts/"
    chmod +x "$HERMES_HOME/scripts/"*.sh
    chown -R "$HERMES_USER:$HERMES_USER" "$HERMES_HOME/scripts"
    
    # Sudoers for audit commands
    cat > /etc/sudoers.d/hermes-audit << 'SUDOEOF'
hermes ALL=(root) NOPASSWD: /usr/sbin/ss, /usr/bin/lsof, /usr/sbin/iptables-save, /usr/sbin/iptables -L -n -v, /usr/bin/cat /var/log/auth.log, /usr/bin/cat /var/log/syslog, /usr/bin/journalctl
SUDOEOF
    chmod 0440 /etc/sudoers.d/hermes-audit
    
    # Cron jobs are created via Hermes cronjob tool after gateway starts
    ok "Cron scripts installed (jobs activated post-deploy)"
else
    warn "No cron scripts directory found"
fi

# ── Step 10: systemd Services ───────────────────────────────────────────────
step 10 "systemd services (gateway, dashboard, https proxy)"
next_step

if [[ -d "$SYSTEMD_DIR" ]]; then
    # User services
    mkdir -p /home/$HERMES_USER/.config/systemd/user
    
    for svc in "$SYSTEMD_DIR"/*.service; do
        cp "$svc" "/home/$HERMES_USER/.config/systemd/user/"
        ok "Installed $(basename $svc)"
    done
    
    chown -R "$HERMES_USER:$HERMES_USER" "/home/$HERMES_USER/.config"
    
    # Enable linger for hermes user (services start at boot)
    loginctl enable-linger "$HERMES_USER"
    
    ok "systemd user services installed"
else
    warn "No systemd directory found"
fi

# ── Step 11: Profile Import ─────────────────────────────────────────────────
step 11 "Profile import → $PROFILE_NAME replaces default"
next_step

PROFILE_TARBALL="${SCRIPT_DIR}/${PROFILE_NAME}.tar.gz"

if [[ -f "$PROFILE_TARBALL" ]]; then
    su - "$HERMES_USER" -c "hermes profile import $PROFILE_TARBALL"
    
    # Verify profile exists
    if su - "$HERMES_USER" -c "hermes profile list" 2>/dev/null | grep -q "$PROFILE_NAME"; then
        ok "Profile '$PROFILE_NAME' imported and set as default"
    else
        warn "Profile import may have failed — verify manually"
    fi
else
    warn "No profile tarball found: $PROFILE_TARBALL"
    warn "Import profile manually: hermes profile import <file>.tar.gz"
fi

# ── Step 12: Post-Deploy Verification ───────────────────────────────────────
step 12 "Post-deploy verification"
next_step

if $SKIP_VERIFY; then
    warn "Verification skipped (--skip-verify)"
else
    ERRORS=0
    
    echo "  Verifying..."
    
    # Firewall
    if iptables -L INPUT -n 2>/dev/null | head -1 | grep -q DROP; then
        ok "iptables INPUT DROP"
    else
        fail "iptables INPUT policy is NOT DROP"; ERRORS=$((ERRORS+1))
    fi
    
    # SSH
    if sshd -T 2>/dev/null | grep -q "permitrootlogin no"; then
        ok "SSH root login disabled"
    else
        warn "SSH root login check failed"; ERRORS=$((ERRORS+1))
    fi
    
    # fail2ban
    if fail2ban-client status sshd 2>/dev/null | grep -q "currently banned"; then
        ok "fail2ban sshd jail active"
    else
        warn "fail2ban check failed"; ERRORS=$((ERRORS+1))
    fi
    
    # Engram
    if engram doctor 2>/dev/null | grep -q "ok"; then
        ok "Engram healthy"
    else
        warn "Engram health check failed"; ERRORS=$((ERRORS+1))
    fi
    
    if [[ $ERRORS -eq 0 ]]; then
        ok "All checks passed"
    else
        warn "$ERRORS verification failures (non-critical)"
    fi
fi

# ── Done ────────────────────────────────────────────────────────────────────
echo ""
echo "=============================================="
echo -e "  ${GREEN}BASELINE DEPLOY COMPLETE${NC}"
echo "=============================================="
echo "  Profile:  $PROFILE_NAME (default)"
echo "  Dashboard: https://$(hostname -I | awk '{print $1}'):9119"
echo "  Log:      $LOG_FILE"
echo ""
echo "  Post-import steps:"
echo "    1. UPDATE TELEGRAM TOKEN (if imported from dev):"
echo -e "       ${CYAN}vim ~/.hermes/profiles/$PROFILE_NAME/.env${NC}"
echo -e "       ${CYAN}# Replace TELEGRAM_BOT_TOKEN with production token${NC}"
echo -e "       ${CYAN}# Token is in Vaultwarden (10.1.1.10:8443)${NC}"
echo ""
echo "    2. Restart gateway with new token:"
echo -e "       ${CYAN}systemctl --user restart hermes-gateway${NC}"
echo ""
echo "    3. Verify:"
echo -e "       ${CYAN}hermes profile list${NC}"
echo -e "       ${CYAN}systemctl --user status hermes-gateway${NC}"
echo ""
echo "    4. Test Telegram bot: /status"
echo "    5. Configure cron jobs via Hermes"
echo ""
echo -e "  ${YELLOW}⚠️  IMPORTANT: If this profile was exported from Oracle,${NC}"
echo -e "  ${YELLOW}   its .env contains the DEV bot token. You MUST${NC}"
echo -e "  ${YELLOW}   replace it with the PROD token before starting.${NC}"
echo -e "  ${YELLOW}   Two Hermes instances with the same token = conflict.${NC}"
echo "=============================================="
