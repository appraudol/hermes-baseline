# Hermes Baseline — Golden Image for Production LXCs

A production-ready baseline that transforms a bare Ubuntu Server 22.04 LXC into a hardened, monitored, fully-configured Hermes Agent node in under 5 minutes.

## The Two-Component Workflow

```
┌──────────────────────────────────────────────────────────────┐
│                    FROM: Oracle VPS (dev)                     │
│                                                              │
│  1. Build & test profile here                                │
│  2. Export: bash export-profile.sh deepsec                   │
│     → ./exports/deepsec-20260531.tar.gz                      │
│                          │                                   │
│                    SCP by Tailscale                          │
│                          ▼                                   │
│                    TO: OVH LXC (prod)                        │
│                                                              │
│  3. Deploy infra: sudo bash baseline-deploy.sh               │
│     → 52 items: firewall + SSH + Hermes + skills + cron      │
│                                                              │
│  4. Import profile: hermes profile import deepsec.tar.gz    │
│     → Profile replaces default, gateway starts               │
│                                                              │
│  ✅ LXC ready for production                                 │
└──────────────────────────────────────────────────────────────┘
```

## Quick Start

```bash
# === ON YOUR DEV MACHINE (Oracle VPS) ===

# 1. Export the profile you want to deploy
cd ~/baseline
bash export-profile.sh deepsec
# → ./exports/deepsec-20260531-120000.tar.gz


# === ON THE TARGET LXC (OVH Proxmox) ===

# 2. Create Ubuntu 22.04 LXC on Proxmox (4GB RAM, 20GB disk, IP 10.1.1.x)

# 3. Copy baseline + profile to LXC
scp -r baseline/ hermes@10.1.1.x:~/
scp exports/deepsec-*.tar.gz hermes@10.1.1.x:/tmp/

# 4. Deploy infrastructure
ssh hermes@10.1.1.x
sudo bash baseline/baseline-deploy.sh

# 5. Import profile
hermes profile import /tmp/deepsec-*.tar.gz

# 6. Verify
hermes profile list
# → ◆ deepsec (default)

systemctl --user restart hermes-gateway
# → active (running)
```

## Scripts

| Script | Purpose |
|--------|---------|
| `baseline-deploy.sh` | Deploy 52 infrastructure items (firewall, SSH, Hermes, skills, cron, systemd) |
| `export-profile.sh` | Interactive profile selector → full .tar.gz export for LXC migration |
| `remove-profile.sh` | Safe profile removal with active profile guard + confirmation |

### export-profile.sh

```bash
bash export-profile.sh              # Interactive: list → select → export
bash export-profile.sh deepsec      # Direct export
bash export-profile.sh --list       # List available profiles
```

### remove-profile.sh

```bash
bash remove-profile.sh              # Interactive: list → select → confirm → delete
bash remove-profile.sh deepsec      # Direct (must type 'DELETE' to confirm)
bash remove-profile.sh --list       # List removable profiles (excludes active)
```

## What baseline-deploy.sh Installs (52 items)

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
├── LXC: vaultwarden (10.1.1.10) ← secrets (shared)
├── LXC: deepsec       (10.1.1.20) ← baseline + deepsec profile
├── LXC: trading       (10.1.1.30) ← baseline + trading profile
└── LXC: future        (10.1.1.x)  ← baseline + its profile

Each LXC = one project = one Hermes profile.
Baseline is identical. Only the imported profile changes.
Engram is local per LXC. Vaultwarden is shared.
Tailscale runs on Proxmox host only (subnet router 10.1.1.0/24).
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
├── baseline-deploy.sh          # Main deployment (12 steps, automated)
├── export-profile.sh           # Profile exporter (.tar.gz for migration)
├── remove-profile.sh           # Safe profile remover
├── config/
│   ├── hermes-config.yaml      # Global Hermes config (22 sections)
│   ├── iptables-rules.v4       # Firewall (INPUT DROP, 4 allow sources)
│   ├── sshd_config.hardened    # SSH hardening (11 params)
│   ├── jail.local              # fail2ban sshd jail
│   └── netdata.conf            # Netdata (bind 127.0.0.1)
├── systemd/
│   ├── hermes-gateway.service
│   ├── hermes-dashboard.service
│   └── dashboard-https-proxy.service
├── cron/
│   ├── security-audit.sh       # Snapshot-based change detection
│   ├── log-inspector.sh        # Auth/syslog anomaly scanner
│   ├── journal-analyzer.sh     # Systemd failure detector
│   ├── backup-watchdog.sh      # Backup integrity verifier
│   ├── disk-cleaner.sh         # Weekly cleanup
│   └── system-updater.sh       # Weekly apt updates
├── docs/
│   ├── INFRASTRUCTURE.md       # Full architecture reference
│   └── WORKFLOW.md             # Step-by-step implementation guide
├── exports/                    # Profile tarballs (gitignored)
└── README.md
```

## baseline-deploy.sh Options

```bash
# Deploy infrastructure (profile imported separately)
sudo bash baseline-deploy.sh

# Skip post-deploy verification (faster, less safe)
sudo bash baseline-deploy.sh --skip-verify

# Recover mode (re-apply to existing LXC without overwriting)
sudo bash baseline-deploy.sh --recover
```

## Post-Deploy Verification

```bash
# Profile
hermes profile list
# → ◆ deepsec (default)

# Gateway
systemctl --user status hermes-gateway
# → active (running)

# Dashboard
curl -k https://10.1.1.x:9119
# → HTML response

# Firewall
sudo iptables -L INPUT -n | head -1
# → Chain INPUT (policy DROP)

# SSH
sudo sshd -T | grep permitrootlogin
# → permitrootlogin no

# Vaultwarden
curl -s https://10.1.1.10:8443/api/config | jq .version
# → version string

# Engram
engram doctor
# → all checks pass
```

## Security Model

- SSH: key-only, no root, 2 max auth tries
- Firewall: INPUT DROP, only 10.1.1.0/24 + 10.0.0.0/24 + 192.168.1.0/24 + Tailscale mesh (100.64.0.0/10)
- fail2ban: sshd jail, 3 attempts = 1 hour ban
- CrowdSec: collaborative IPS, auto-blocks known malicious IPs
- Netdata: bound to 127.0.0.1 only
- Dashboard: HTTPS via local proxy, accessible only via Tailscale subnet
- API keys: never on disk, pulled from Vaultwarden at runtime
- Profile removal: guarded (can't remove active profile, must type 'DELETE' to confirm)
