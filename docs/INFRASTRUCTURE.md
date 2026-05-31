# Hermes Baseline — Infrastructure Design v1.0

**Author:** Hermes / Asesor Personal — Raudol Ruiz (CEH)  
**Date:** 2026-05-30  
**Status:** Final Design — Ready for Implementation  

---

## 1. Architecture Overview

### 1.1 Physical Topology

```
┌─────────────────────────────────────────────────────────────────────┐
│                        TAILSCALE MESH (free tier, 3 endpoints)      │
│                                                                      │
│  Home (GL-MT6000)          Oracle VPS              OVH Proxmox       │
│  100.x.x.x                 100.x.x.x               100.x.x.x        │
│      │                         │                       │             │
│      │ 10.0.0.0/24             │                       │ subnet      │
│      │ (VPN subnet)            │                       │ router      │
│      │ 192.168.1.0/24          │                       │ --routes=   │
│      │ (Local LAN)             │                       │ 10.1.1.0/24 │
│      │                         │                       │             │
│      └────────────┬────────────┘                       │             │
│                   │                                    │             │
│                   └────── Tailscale mesh ──────────────┘             │
└─────────────────────────────────────────────────────────────────────┘
```

### 1.2 OVH Proxmox — LXC Layout

```
OVH Dedicated Server
├── Proxmox VE (host)
│   ├── Tailscale (subnet router: 10.1.1.0/24)
│   ├── Bridge: vmbr0 → 10.1.1.0/24
│   │
│   ├── LXC 100: vaultwarden       10.1.1.10
│   │   └── Secrets manager self-hosted (Bitwarden-compatible)
│   │
│   ├── LXC 200: deepsec-business  10.1.1.20
│   │   ├── Hermes core (profile: deepsec)
│   │   ├── Vault + DocuSeal + Prowler + Terraform
│   │   └── Gateway: @DeepSecBot (Telegram)
│   │
│   └── LXC 300: trading-system    10.1.1.30  (future)
│       ├── Hermes core (profile: trading)
│       └── Gateway: @TradeBot (Telegram)
```

### 1.3 Network — What Can Reach What

```
Source              →  Destination         Ports        Reason
──────────────────────────────────────────────────────────────────
Home LAN/VPN        →  10.1.1.x           22, 9119     SSH + Dashboard
Oracle VPS          →  10.1.1.x           22           Admin SSH
10.1.1.x (LXCs)     →  10.1.1.x           any          Inter-LXC (Vaultwarden)
10.1.1.x (LXCs)     →  internet            443, 22      API calls, GitHub
internet            →  10.1.1.x           NONE         Zero exposed ports
```

### 1.4 Baseline Contents (52 items)

```
BASELINE = Capa Global (22) + Capa Infra (20) + Cron Jobs (9) + Skills (20)
```

| Layer | What | Examples |
|-------|------|----------|
| **Global** | Hermes config | model providers, fallback chain, delegation, memory, security |
| **Infra** | System hardening | iptables, SSH, fail2ban, CrowdSec, Netdata, systemd, Engram |
| **Cron** | Watchdog jobs | security-audit, log-inspector, journal-analyzer, backup-watchdog |
| **Skills** | Reusable knowledge | 4 core + 1 debug + 10 devops + 5 github |

### 1.5 What is NOT in the baseline

- Vaultwarden (its own LXC, provisioned separately)
- API keys / tokens (stored in Vaultwarden, pulled at runtime)
- Profile-specific files (SOUL.md, profile skills, memories — imported separately)
- Tailscale (on Proxmox host, not in LXCs)
- Personal data (USER.md, memories, Daily Briefing cron)

---

## 2. Per-LXC Architecture

### 2.1 Each LXC = One Project = One Profile

```
LXC Fresh (Ubuntu 22.04)
        │
        ▼
baseline-deploy.sh --profile <name>
        │
        ├── 1. System hardening (iptables, SSH, fail2ban, CrowdSec)
        ├── 2. Hermes core installation
        ├── 3. Global config (providers, fallback, delegation, memory)
        ├── 4. 20 baseline skills installed
        ├── 5. Cron jobs activated (security, logs, backups)
        ├── 6. systemd services (gateway, dashboard, https proxy)
        ├── 7. Engram CLI + MCP server
        ├── 8. Profile import → replaces generic default
        └── 9. Vaultwarden connection → pulls secrets
                │
                ▼
        LXC READY FOR PRODUCTION
        hermes profile list → <name> (default)
```

### 2.2 Profile Architecture

```
hermes profile list
─────────────────
◆ deepsec (default)     ← el único perfil, reemplazó al default genérico
```

No existe `default` genérico. El perfil del proyecto ES default.

### 2.3 Vaultwarden Integration

```
┌─────────────────┐     ┌──────────────────┐
│ LXC: deepsec    │     │ LXC: vaultwarden │
│                 │     │  10.1.1.10:8443  │
│ Hermes arranca  │────▶│  GET /secrets    │
│ Pull automático │◀────│  OPENCODE_GO_KEY │
│                 │     │  TELEGRAM_TOKEN   │
│ Secrets en      │     │  DOCUSEAL_KEY     │
│ memoria (nunca  │     │  ...              │
│ en disco)       │     └──────────────────┘
└─────────────────┘
```

---

## 3. Firewall Model (inside each LXC)

```iptables
*filter
:INPUT DROP [0:0]
:FORWARD DROP [0:0]
:OUTPUT ACCEPT [0:0]

# Loopback (CRITICAL — DNS depende de esto)
-A INPUT -i lo -j ACCEPT

# Established connections
-A INPUT -m state --state RELATED,ESTABLISHED -j ACCEPT

# Proxmox bridge (inter-LXC communication)
-A INPUT -s 10.1.1.0/24 -j ACCEPT

# Home VPN subnet
-A INPUT -s 10.0.0.0/24 -j ACCEPT

# Home LAN subnet
-A INPUT -s 192.168.1.0/24 -j ACCEPT

# Tailscale mesh (Oracle, MacBook)
-A INPUT -s 100.64.0.0/10 -j ACCEPT

# ICMP (ping)
-A INPUT -p icmp -j ACCEPT

# CrowdSec IPS
-A INPUT -j CROWDSEC_CHAIN

# fail2ban SSH protection
-A INPUT -p tcp -m multiport --dports 22 -j f2b-sshd

# Log + Reject everything else
-A INPUT -m limit --limit 10/min -j LOG --log-prefix "FW-BLOCKED: "
-A INPUT -j REJECT --reject-with icmp-host-prohibited

COMMIT
```

---

## 4. SSH Hardening

```
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
Compression delayed
LogLevel VERBOSE
Port 22
```

---

## 5. Cron Job Schedule (all times UTC)

| Time (UTC) | Job | Type | Purpose |
|------------|-----|------|---------|
| 02:00 | log-inspector | no_agent | Anomalies in auth/syslog/CrowdSec |
| 02:30 | journal-analyzer | no_agent | Systemd failures, OOMs, errors |
| 03:00 | security-audit | no_agent | Snapshot-based change detection |
| 05:00 | hermes-full-backup | no_agent | Full backup + GitHub push |
| 05:30 | backup-watchdog | no_agent | Backup integrity verification |
| Sun 04:00 | system-updater | no_agent | Apt updates + health check |
| Sat 03:00 | disk-cleaner | no_agent | Remove old logs/caches/temp |
| Mon 09:00 | Weekly Memory Validation | LLM+skill | Engram health check |
| Sun 08:00 | Weekly System Audit | LLM+skill | Full Hermes audit |

---

## 6. Skills Included (20 total)

| Category | Skills | Count |
|----------|--------|-------|
| Core | engram-memory, server-security-audit, hermes-system-audit, hermes-backup-disaster-recovery | 4 |
| Debugging | systematic-debugging | 1 |
| DevOps | tailscale-serve, tailscale-hub-spoke, cloudflare-tunnel, webhook-subscriptions, hermes-multi-profile-infrastructure, hermes-secrets-bitwarden, kanban-orchestrator, kanban-worker, hermes-messaging-platforms, watchdog-workers | 10 |
| GitHub | github-auth, github-pr-workflow, github-code-review, github-issues, github-repo-management | 5 |
