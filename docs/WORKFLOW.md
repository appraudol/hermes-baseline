# Hermes Baseline — Implementation Workflow v1.0

**Author:** Hermes / Asesor Personal — Raudol Ruiz (CEH)  
**Date:** 2026-05-30  

---

## Pre-Flight: What You Need Before Starting

| Requirement | Details |
|-------------|---------|
| OVH Dedicated Server | Proxmox VE installed |
| Tailscale on Proxmox host | Subnet router advertising 10.1.1.0/24 |
| Vaultwarden LXC | 10.1.1.10:8443, secrets pre-loaded |
| GitHub repository | For Hermes config backup (optional but recommended) |
| API keys | OpenCode, Telegram, DocuSeal — stored in Vaultwarden |

---

## Phase 1 — Vaultwarden Setup (one time)

### 1.1 Create Vaultwarden LXC on Proxmox

```bash
# On Proxmox host:
bash -c "$(curl -fsSL https://community-scripts.github.io/ProxmoxVE/install/vaultwarden.sh)"
```

### 1.2 Load Secrets

Open Vaultwarden Web UI (`https://10.1.1.10:8443`), create:

| Secret Name | Value | Used By |
|-------------|-------|---------|
| `OPENCODE_GO_API_KEY` | `***` | All LXCs |
| `OPENCODE_ZEN_API_KEY` | `***` | All LXCs |
| `TELEGRAM_DEEPSEC_BOT_TOKEN` | `***` | deepsec-business |
| `TELEGRAM_TRADING_BOT_TOKEN` | `***` | trading-system |
| `DOCUSEAL_API_KEY` | `***` | deepsec-business |
| `GITHUB_TOKEN` | `***` | All LXCs |
| `TAVILY_API_KEY` | `***` | All LXCs |

---

## Phase 2 — Create New Project LXC

### 2.1 Create LXC on Proxmox

```
Proxmox UI → Create LXC
  Template: ubuntu-22.04-standard
  ID: 200 (or next available)
  Hostname: deepsec-business
  Memory: 4096 MB
  Disk: 40 GB
  Network: vmbr0, static IP 10.1.1.20/24
  Gateway: 10.1.1.1 (Proxmox host)
  DNS: 10.1.1.1
  Start at boot: YES
```

### 2.2 Initial Access

```bash
# From Home/Oracle (via Tailscale):
ssh root@10.1.1.20

# Create hermes user
adduser hermes
usermod -aG sudo hermes

# Copy baseline to LXC
scp -r baseline/ hermes@10.1.1.20:~/
```

### 2.3 Run Baseline Deploy

```bash
# On LXC, as root or hermes with sudo:
cd ~/baseline
sudo bash baseline-deploy.sh --profile deepsec
```

### 2.4 What the Script Does

```
[1/9] System update + dependencies ............ ✅
[2/9] Firewall hardening (iptables) ........... ✅
[3/9] SSH hardening ........................... ✅
[4/9] fail2ban + CrowdSec ..................... ✅
[5/9] Netdata (monitoring) .................... ✅
[6/9] Hermes installation ..................... ✅
[7/9] Global config apply ..................... ✅
[8/9] Skills install (20 skills) .............. ✅
[9/9] Profile import (--profile deepsec) ...... ✅
      → deepsec reemplaza a default

Post-deploy verification:
  • iptables INPUT DROP ....................... ✅
  • SSH root login disabled ................... ✅
  • fail2ban sshd active ...................... ✅
  • CrowdSec running .......................... ✅
  • Hermes gateway active ..................... ✅
  • Dashboard :9119 reachable ................. ✅
  • Vaultwarden secrets accessible ............ ✅
  • Cron jobs scheduled ....................... ✅

LXC READY. Profile: deepsec (default).
```

---

## Phase 3 — Post-Deploy Verification

### 3.1 Health Checks

```bash
# Hermes status
hermes profile list
# → ◆ deepsec (default)

# Gateway
systemctl --user status hermes-gateway
# → active (running)

# Dashboard
curl -k https://10.1.1.20:9119
# → HTML response

# Firewall
sudo iptables -L INPUT -n | head -10
# → policy DROP

# SSH
sudo sshd -T | grep -E "permitroot|passwordauth"
# → permitrootlogin no, passwordauthentication no

# Vaultwarden
curl -s https://10.1.1.10:8443/api/config | jq .version
# → version string

# Cron
cronjob action=list
# → 9 jobs scheduled

# Engram
engram doctor
# → all checks pass
```

### 3.2 Telegram Smoke Test

```
DeepSecBot:
  /status → "Pipeline CSPM idle. Sin engagements activos."
  /scout  → "Scout ejecutado. 0 jobs encontrados (sin cron configurado aún)."
```

---

## Phase 4 — Add Service-Specific Configuration

```bash
# On deepsec-business LXC:
# Install CSPM tools
pip install prowler checkov cloudsplaining
git clone https://github.com/nccgroup/ScoutSuite

# Install Terraform
wget -O terraform.zip https://releases.hashicorp.com/terraform/1.x/terraform_1.x_linux_arm64.zip
unzip terraform.zip && mv terraform /usr/local/bin/

# Install Vault (HashiCorp)
# Install DocuSeal (self-hosted)

# Import CSPM-specific skills
hermes profile import cspm-skills.tar.gz
```

---

## Phase 5 — Migrate Profile from Oracle (Dev to Prod)

```bash
# On Oracle (dev):
hermes profile export deepsec --output /tmp/deepsec-prod.tar.gz
scp /tmp/deepsec-prod.tar.gz hermes@10.1.1.20:/tmp/

# On OVH (prod):
hermes profile import /tmp/deepsec-prod.tar.gz --replace
# --replace: overwrites the existing deepsec profile with production-ready version
systemctl --user restart hermes-gateway

# Verify profile loaded correctly
hermes profile use deepsec
hermes session start
```

---

## Recovery Procedures

### If an LXC fails

```bash
# On Proxmox host:
pct restore <lxc-id> /var/lib/vz/dump/backup-<date>.tar.gz

# Re-run baseline to ensure consistency:
ssh hermes@10.1.1.x
cd ~/baseline
sudo bash baseline-deploy.sh --profile deepsec --recover
```

### If Vaultwarden fails

```bash
# Restore from Proxmox backup
pct restore 100 /var/lib/vz/dump/vaultwarden-backup.tar.gz

# Verify LXCs can reach it:
curl -k https://10.1.1.10:8443/api/config
```

---

## Scaling: Adding a New Project

```bash
# 1. Proxmox → Create LXC (new ID, new IP)
# 2. Copy baseline to LXC
scp -r baseline/ hermes@10.1.1.30:~/

# 3. Deploy with new profile
ssh hermes@10.1.1.30
sudo bash baseline-deploy.sh --profile trading

# 4. Import project-specific skills
hermes profile import trading-skills.tar.gz

# 5. Configure Telegram bot token
# (Already in Vaultwarden — Hermes pulls it automatically)

# 6. Ready.
hermes profile list
# → ◆ trading (default)
```
