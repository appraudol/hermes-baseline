# Hermes Baseline — Golden Image for Production LXCs

A production-ready baseline that transforms a bare Ubuntu Server 22.04 LXC into a hardened, monitored, fully-configured Hermes Agent node in under 5 minutes.

## Quick Start

```bash
# 1. Create Ubuntu 22.04 LXC on Proxmox
# 2. Copy baseline to LXC
scp -r baseline/ hermes@10.1.1.x:~/

# 3. Deploy
ssh hermes@10.1.1.x
sudo bash baseline/baseline-deploy.sh --profile deepsec
```

## What it Installs

| Category | Count | Details |
|----------|-------|---------|
| **Global Config** | 22 sections | model providers, fallback chain, delegation, memory, security |
| **Infrastructure** | 20 features | iptables (INPUT DROP), SSH hardening, fail2ban, CrowdSec, Netdata, Engram |
| **Cron Jobs** | 9 jobs | security-audit, log-inspector, journal-analyzer, backup, disk-cleaner, updater |
| **Skills** | 20 skills | 4 core + 1 debugging + 10 devops + 5 github |
| **systemd** | 3 services | gateway, dashboard, https proxy |

## Architecture

```
Proxmox OVH
├── LXC: vaultwarden (10.1.1.10) ← secrets
├── LXC: your-project  (10.1.1.x) ← baseline + profile
└── LXC: another       (10.1.1.y) ← baseline + profile

Each LXC = one project = one Hermes profile.
Engram is local (no shared LXC). Vaultwarden is shared.
Tailscale runs on Proxmox host only (subnet router).
```

## Requirements

- Ubuntu Server 22.04 LXC
- 4GB RAM, 20GB disk minimum
- Proxmox bridge network (10.1.1.0/24)
- Vaultwarden LXC (10.1.1.10:8443) with secrets pre-loaded
- Tailscale subnet router on Proxmox host

## Files

```
baseline/
├── baseline-deploy.sh          # Main deployment script
├── config/
│   ├── hermes-config.yaml      # Global Hermes configuration
│   ├── iptables-rules.v4       # Firewall rules
│   ├── sshd_config.hardened    # SSH hardening
│   ├── jail.local              # fail2ban jail
│   └── netdata.conf            # Netdata config
├── systemd/
│   ├── hermes-gateway.service
│   ├── hermes-dashboard.service
│   └── dashboard-https-proxy.service
├── cron/
│   ├── security-audit.sh
│   ├── log-inspector.sh
│   ├── journal-analyzer.sh
│   ├── backup-watchdog.sh
│   ├── disk-cleaner.sh
│   └── system-updater.sh
├── docs/
│   ├── INFRASTRUCTURE.md       # Full architecture reference
│   └── WORKFLOW.md             # Step-by-step implementation
└── README.md
```

## Usage

```bash
# Deploy with a profile
sudo bash baseline-deploy.sh --profile deepsec

# Skip post-deploy verification
sudo bash baseline-deploy.sh --profile deepsec --skip-verify

# Recover mode (re-apply baseline to existing LXC)
sudo bash baseline-deploy.sh --profile deepsec --recover
```

## Post-Deploy

```bash
# Verify
hermes profile list
# → ◆ deepsec (default)

systemctl --user status hermes-gateway
# → active (running)

curl -k https://<lxc-ip>:9119
# → Dashboard HTML

# Configure cron jobs via Hermes
# (Create jobs in Hermes, they auto-register in the scheduler)
```

## Security Model

- SSH: key-only, no root, 2 max auth tries
- Firewall: INPUT DROP, only 10.1.1.0/24 + home subnets + Tailscale
- fail2ban: sshd jail, 3 attempts = 1 hour ban
- CrowdSec: collaborative IPS, auto-blocks known malicious IPs
- Netdata: bound to 127.0.0.1 only
- Dashboard: HTTPS via local proxy, accessible only via Tailscale subnet
- API keys: never on disk, pulled from Vaultwarden at runtime
