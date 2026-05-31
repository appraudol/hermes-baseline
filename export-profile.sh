#!/usr/bin/env bash
# =============================================================================
# Hermes Profile Exporter — Interactive profile selector + full export
# =============================================================================
# Usage:
#   bash export-profile.sh                        # Interactive mode
#   bash export-profile.sh <profile-name>          # Direct export  
#   bash export-profile.sh --list                  # List profiles only
#
# Output:
#   ./exports/<profile-name>-<date>.tar.gz         # Full profile tarball
#   ./exports/<profile-name>-<date>-manifest.txt   # What's inside
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
EXPORT_DIR="${SCRIPT_DIR}/exports"
TIMESTAMP=$(date +%Y%m%d-%H%M%S)

# Colors
BOLD='\033[1m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
RED='\033[0;31m'
NC='\033[0m'

mkdir -p "$EXPORT_DIR"

# ── Discover Profiles ──────────────────────────────────────────────────────
discover_profiles() {
    # Method 1: Check profile directories
    local profile_dirs=()
    if [[ -d "${HOME}/.hermes/profiles" ]]; then
        for d in "${HOME}/.hermes/profiles"/*/; do
            [[ -d "$d" ]] || continue
            local name
            name=$(basename "$d")
            profile_dirs+=("$name")
        done
    fi
    
    # Method 2: Fallback to hermes profile list (parse carefully)
    if [[ ${#profile_dirs[@]} -eq 0 ]]; then
        local raw
        raw=$(hermes profile list 2>/dev/null | grep -v "Bitwarden\|Profile\|───\|^$" | awk '{print $1}' || true)
        while IFS= read -r line; do
            [[ -z "$line" ]] && continue
            line=$(echo "$line" | sed 's/^◆//;s/[^a-zA-Z0-9_-].*//')
            [[ -z "$line" ]] && continue
            profile_dirs+=("$line")
        done <<< "$raw"
    fi
    
    printf '%s\n' "${profile_dirs[@]}"
}

# ── Profile Info ────────────────────────────────────────────────────────────
get_profile_info() {
    local profile=$1
    local profile_dir="${HOME}/.hermes/profiles/${profile}"
    
    echo ""
    echo -e "${BOLD}Profile: ${GREEN}${profile}${NC}"
    echo "──────────────────────────────"
    
    # SOUL
    if [[ -f "${profile_dir}/HERMES_SOUL.md" ]]; then
        local soul_name
        soul_name=$(head -1 "${profile_dir}/HERMES_SOUL.md" 2>/dev/null | sed 's/^#*\s*//' | head -c 60)
        echo "  SOUL:    ${soul_name:-present}"
    elif [[ -f "${profile_dir}/HERMES_SOUL_COMPACT.md" ]]; then
        local soul_name
        soul_name=$(head -1 "${profile_dir}/HERMES_SOUL_COMPACT.md" 2>/dev/null | sed 's/^#*\s*//' | head -c 60)
        echo "  SOUL:    ${soul_name:-compact}"
    else
        echo "  SOUL:    (none)"
    fi
    
    # Skills
    local skill_count=0
    if [[ -d "${profile_dir}/skills" ]]; then
        skill_count=$(find "${profile_dir}/skills" -name "SKILL.md" 2>/dev/null | wc -l)
    fi
    echo "  Skills:  ${skill_count}"
    
    # Memory
    local mem_count=0
    if [[ -d "${profile_dir}/memories" ]]; then
        mem_count=$(find "${profile_dir}/memories" -name "*.md" 2>/dev/null | wc -l)
    fi
    echo "  Memory:  ${mem_count} entries"
    
    # Cron
    local cron_count=0
    if [[ -d "${profile_dir}/cron" ]]; then
        cron_count=$(find "${profile_dir}/cron" -type f 2>/dev/null | wc -l)
    fi
    echo "  Cron:    ${cron_count} jobs"
    
    # Size
    if [[ -d "$profile_dir" ]]; then
        local size
        size=$(du -sh "$profile_dir" 2>/dev/null | cut -f1)
        echo "  Size:    ${size}"
    fi
    
    # Gateway
    if [[ -f "${profile_dir}/.env" ]]; then
        if grep -q "TELEGRAM.*BOT_TOKEN" "${profile_dir}/.env" 2>/dev/null; then
            echo "  Gateway: Telegram (token present)"
        fi
    elif [[ -f "${profile_dir}/config.yaml" ]]; then
        if grep -q "telegram\|bot_token" "${profile_dir}/config.yaml" 2>/dev/null; then
            echo "  Gateway: Telegram (config present)"
        fi
    fi
    
    echo ""
}

# ── Export ──────────────────────────────────────────────────────────────────
export_profile() {
    local profile=$1
    local export_file="${EXPORT_DIR}/${profile}-${TIMESTAMP}.tar.gz"
    local manifest_file="${EXPORT_DIR}/${profile}-${TIMESTAMP}-manifest.txt"
    
    echo -e "${BOLD}Exporting: ${GREEN}${profile}${NC}"
    echo "──────────────────────────────"
    echo ""
    
    local profile_dir="${HOME}/.hermes/profiles/${profile}"
    
    if [[ ! -d "$profile_dir" ]]; then
        echo -e "  ${RED}❌${NC} Profile directory not found: $profile_dir"
        exit 1
    fi
    
    # Try Hermes native export first
    echo "  → Trying hermes profile export..."
    if hermes profile export "$profile" --output "$export_file" 2>/dev/null; then
        local native_size
        native_size=$(ls -lh "$export_file" 2>/dev/null | awk '{print $5}')
        local native_files
        native_files=$(tar -tzf "$export_file" 2>/dev/null | wc -l)
        echo -e "  ${GREEN}✅${NC} Hermes native export: ${native_size}, ${native_files} files"
    else
        echo -e "  ${YELLOW}⚠️${NC}  Hermes export not available — using manual tarball"
        
        # Manual tarball of the profile directory
        tar -czf "$export_file" -C "${HOME}/.hermes/profiles" "$profile" 2>/dev/null
        local manual_size
        manual_size=$(ls -lh "$export_file" 2>/dev/null | awk '{print $5}')
        local manual_files
        manual_files=$(tar -tzf "$export_file" 2>/dev/null | wc -l)
        echo -e "  ${GREEN}✅${NC} Manual tarball: ${manual_size}, ${manual_files} files"
    fi
    
    # Show what's inside
    local total_files
    total_files=$(tar -tzf "$export_file" 2>/dev/null | wc -l)
    local total_size
    total_size=$(ls -lh "$export_file" | awk '{print $5}')
    
    echo ""
    echo "  Contents:"
    echo "  ────────────────────────"
    tar -tzf "$export_file" 2>/dev/null | head -25 | while read -r line; do
        echo "    $line"
    done
    if [[ $total_files -gt 25 ]]; then
        echo "    ... and $((total_files - 25)) more files"
    fi
    
    # Generate manifest
    {
        echo "Profile Export Manifest"
        echo "======================"
        echo "Profile:    $profile"
        echo "Date:       $(date)"
        echo "Host:       $(hostname)"
        echo "File:       $(basename "$export_file")"
        echo "Size:       $total_size"
        echo "Files:      $total_files"
        echo ""
        echo "Full Contents:"
        tar -tzf "$export_file" 2>/dev/null
    } > "$manifest_file"
    
    echo ""
    echo "  📄 Manifest: $(basename "$manifest_file")"
    echo ""
    echo -e "  ${BOLD}📦 ${export_file}${NC}"
    echo ""
    echo "  ──────────────────────────────────────────"
    echo -e "  ${BOLD}To deploy on target LXC:${NC}"
    echo ""
    echo -e "  ${CYAN}# 1. Copy to LXC${NC}"
    echo -e "  scp ${export_file} hermes@10.1.1.x:/tmp/"
    echo ""
    echo -e "  ${CYAN}# 2. Import${NC}"
    echo -e "  ssh hermes@10.1.1.x"
    echo -e "  hermes profile import /tmp/$(basename "$export_file")"
    echo ""
    echo -e "  ${CYAN}# 3. Activate${NC}"
    echo -e "  hermes profile use ${profile}"
    echo -e "  systemctl --user restart hermes-gateway"
    echo ""
    echo -e "  ${CYAN}# 4. Verify${NC}"
    echo -e "  hermes profile list"
    echo "  ──────────────────────────────────────────"
}

# ── Main ────────────────────────────────────────────────────────────────────

echo ""
echo -e "${BOLD}╔════════════════════════════════════╗${NC}"
echo -e "${BOLD}║   Hermes Profile Exporter v1.0     ║${NC}"
echo -e "${BOLD}╚════════════════════════════════════╝${NC}"
echo ""

# Handle arguments
if [[ $# -gt 0 ]]; then
    case "$1" in
        --list|-l)
            mapfile -t profiles < <(discover_profiles)
            if [[ ${#profiles[@]} -eq 0 ]]; then
                echo "No profiles found."
            else
                echo -e "${BOLD}Available Profiles:${NC}"
                for p in "${profiles[@]}"; do
                    echo "  • $p"
                done
            fi
            exit 0
            ;;
        *)
            PROFILE_NAME="$1"
            get_profile_info "$PROFILE_NAME"
            export_profile "$PROFILE_NAME"
            exit 0
            ;;
    esac
fi

# Interactive mode
mapfile -t PROFILES < <(discover_profiles)

if [[ ${#PROFILES[@]} -eq 0 ]]; then
    echo -e "${RED}No profiles found in ${HOME}/.hermes/profiles/${NC}"
    exit 1
fi

echo -e "${BOLD}Available Profiles:${NC}"
echo "────────────────────"
for i in "${!PROFILES[@]}"; do
    local skill_count=0
    [[ -d "${HOME}/.hermes/profiles/${PROFILES[$i]}/skills" ]] && \
        skill_count=$(find "${HOME}/.hermes/profiles/${PROFILES[$i]}/skills" -name "SKILL.md" 2>/dev/null | wc -l)
    echo -e "  $((i+1))) ${PROFILES[$i]}  (${skill_count} skills)"
done
echo ""

if [[ ${#PROFILES[@]} -eq 1 ]]; then
    PROFILE_NAME="${PROFILES[0]}"
    echo -e "Only one profile found. Auto-selecting: ${GREEN}${PROFILE_NAME}${NC}"
else
    echo -n "Select profile [1-${#PROFILES[@]}]: "
    read -r SELECTION
    if [[ ! "$SELECTION" =~ ^[0-9]+$ ]] || [[ "$SELECTION" -lt 1 ]] || [[ "$SELECTION" -gt ${#PROFILES[@]} ]]; then
        echo -e "${RED}Invalid selection.${NC}"
        exit 1
    fi
    PROFILE_NAME="${PROFILES[$((SELECTION-1))]}"
fi

get_profile_info "$PROFILE_NAME"

echo -n "Export this profile? [Y/n]: "
read -r CONFIRM
if [[ "$CONFIRM" =~ ^[Nn] ]]; then
    echo "Cancelled."
    exit 0
fi

export_profile "$PROFILE_NAME"
