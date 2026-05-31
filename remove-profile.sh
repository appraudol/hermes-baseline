#!/usr/bin/env bash
# =============================================================================
# Hermes Profile Remover — Interactive profile selector + safe removal
# =============================================================================
# Usage:
#   bash remove-profile.sh                    # Interactive mode
#   bash remove-profile.sh <profile-name>      # Direct remove (asks confirmation)
#   bash remove-profile.sh --force <name>      # Skip confirmation (DANGER)
#   bash remove-profile.sh --list              # List profiles only
#
# Safety guards:
#   - Won't remove the CURRENTLY ACTIVE profile
#   - Won't remove 'default' unless --force
#   - Always asks confirmation (unless --force)
#   - Shows what will be deleted before doing it
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Colors
BOLD='\033[1m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
CYAN='\033[0;36m'
NC='\033[0m'

# ── Discover Profiles ──────────────────────────────────────────────────────
discover_profiles() {
    local profile_dirs=()
    if [[ -d "${HOME}/.hermes/profiles" ]]; then
        for d in "${HOME}/.hermes/profiles"/*/; do
            [[ -d "$d" ]] || continue
            profile_dirs+=("$(basename "$d")")
        done
    fi
    printf '%s\n' "${profile_dirs[@]}"
}

# ── Get active profile ─────────────────────────────────────────────────────
get_active_profile() {
    # Method 1: Check if HERMES_PROFILE is set
    if [[ -n "${HERMES_PROFILE:-}" ]]; then
        echo "$HERMES_PROFILE"
        return
    fi
    
    # Method 2: Check .hermes/active_profile or config
    if [[ -f "${HOME}/.hermes/.active_profile" ]]; then
        cat "${HOME}/.hermes/.active_profile"
        return
    fi
    
    # Method 3: Hermes profile list shows ◆ next to active
    local active
    active=$(hermes profile list 2>/dev/null | grep "◆" | awk '{print $1}' | sed 's/◆//' | xargs || echo "")
    if [[ -n "$active" ]]; then
        echo "$active"
        return
    fi
    
    echo "default"
}

# ── Profile Info ────────────────────────────────────────────────────────────
show_profile_info() {
    local profile=$1
    local profile_dir="${HOME}/.hermes/profiles/${profile}"
    
    echo ""
    echo -e "${BOLD}Profile to remove: ${RED}${profile}${NC}"
    echo "──────────────────────────────"
    
    if [[ ! -d "$profile_dir" ]]; then
        echo -e "  ${YELLOW}⚠️${NC}  Profile directory not found at: $profile_dir"
        echo "  Nothing to remove on disk."
        return 1
    fi
    
    # Size
    local size
    size=$(du -sh "$profile_dir" 2>/dev/null | cut -f1)
    echo "  Size:    ${size}"
    
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
    
    # Files total
    local total_files
    total_files=$(find "$profile_dir" -type f 2>/dev/null | wc -l)
    echo "  Files:   ${total_files}"
    
    # Show top-level contents
    echo ""
    echo "  Contents:"
    find "$profile_dir" -maxdepth 1 -not -path "$profile_dir" 2>/dev/null | sort | while read -r item; do
        local item_name
        item_name=$(basename "$item")
        if [[ -d "$item" ]]; then
            local item_count
            item_count=$(find "$item" -type f 2>/dev/null | wc -l)
            echo "    📁 ${item_name}/ (${item_count} files)"
        else
            local item_size
            item_size=$(ls -lh "$item" 2>/dev/null | awk '{print $5}')
            echo "    📄 ${item_name} (${item_size})"
        fi
    done
    
    echo ""
    return 0
}

# ── Remove Profile ──────────────────────────────────────────────────────────
remove_profile() {
    local profile=$1
    local force=$2
    local profile_dir="${HOME}/.hermes/profiles/${profile}"
    local active_profile
    active_profile=$(get_active_profile)
    
    echo ""
    echo -e "${BOLD}╔══════════════════════════════════════╗${NC}"
    echo -e "${BOLD}║   Hermes Profile Remover v1.0        ║${NC}"
    echo -e "${BOLD}╚══════════════════════════════════════╝${NC}"
    
    # ── Safety Checks ──────────────────────────────────────────────────────
    
    # Check 1: Is this the active profile?
    if [[ "$profile" == "$active_profile" ]]; then
        echo ""
        echo -e "  ${RED}❌ CANNOT REMOVE ACTIVE PROFILE${NC}"
        echo -e "  '${profile}' is currently active (◆ in hermes profile list)."
        echo ""
        echo "  Switch to another profile first:"
        echo -e "  ${CYAN}hermes profile use default${NC}"
        echo ""
        exit 1
    fi
    
    # Check 2: Is this 'default' without --force?
    if [[ "$profile" == "default" ]] && [[ "$force" != "true" ]]; then
        echo ""
        echo -e "  ${RED}❌ CANNOT REMOVE 'default' PROFILE${NC}"
        echo "  The default profile is the fallback. Use --force to override."
        echo ""
        exit 1
    fi
    
    # Check 3: Does profile directory exist?
    if [[ ! -d "$profile_dir" ]]; then
        echo ""
        echo -e "  ${YELLOW}⚠️${NC}  Profile directory not found: $profile_dir"
        echo "  Nothing to delete on disk."
        exit 0
    fi
    
    # ── Show Info ──────────────────────────────────────────────────────────
    show_profile_info "$profile"
    
    # ── Back Up First? ─────────────────────────────────────────────────────
    if [[ "$force" != "true" ]]; then
        echo -e "  ${YELLOW}💡 Tip:${NC} Export before removing:"
        echo -e "      ${CYAN}bash export-profile.sh ${profile}${NC}"
        echo ""
    fi
    
    # ── Confirm ────────────────────────────────────────────────────────────
    if [[ "$force" != "true" ]]; then
        echo -e "  ${RED}${BOLD}This will PERMANENTLY DELETE all files above.${NC}"
        echo -n "  Type '${RED}DELETE${NC}' to confirm: "
        read -r CONFIRM
        if [[ "$CONFIRM" != "DELETE" ]]; then
            echo ""
            echo -e "  ${GREEN}✅${NC} Cancelled. Nothing was removed."
            exit 0
        fi
    fi
    
    # ── Execute Removal ────────────────────────────────────────────────────
    echo ""
    echo "  Removing..."
    
    # Step 1: Stop any gateway for this profile
    if systemctl --user is-active hermes-gateway &>/dev/null 2>&1; then
        echo "  → Stopping gateway..."
        systemctl --user stop hermes-gateway 2>/dev/null || true
    fi
    
    # Step 2: Remove profile directory
    echo "  → Deleting $profile_dir..."
    rm -rf "$profile_dir"
    
    # Step 3: Verify
    if [[ ! -d "$profile_dir" ]]; then
        echo ""
        echo -e "  ${GREEN}✅ Profile '${profile}' removed successfully.${NC}"
        echo ""
        
        # Show remaining profiles
        mapfile -t remaining < <(discover_profiles)
        if [[ ${#remaining[@]} -gt 0 ]]; then
            echo "  Remaining profiles:"
            for p in "${remaining[@]}"; do
                echo "    • $p"
            done
        else
            echo "  No profiles remaining."
        fi
        echo ""
        
        # Restart gateway if needed
        echo "  Restart gateway:"
        echo -e "  ${CYAN}systemctl --user restart hermes-gateway${NC}"
    else
        echo -e "  ${RED}❌${NC} Removal may have failed — directory still exists."
        exit 1
    fi
}

# ── Main ────────────────────────────────────────────────────────────────────

FORCE=false

# Parse arguments
if [[ $# -gt 0 ]]; then
    case "$1" in
        --list|-l)
            echo ""
            echo -e "${BOLD}Available Profiles (removable):${NC}"
            echo "──────────────────────────────"
            mapfile -t profiles < <(discover_profiles)
            if [[ ${#profiles[@]} -eq 0 ]]; then
                echo "  (none)"
            else
                active=""
                active=$(get_active_profile)
                for p in "${profiles[@]}"; do
                    if [[ "$p" == "$active" ]]; then
                        echo -e "  • ${GREEN}${p}${NC} ← active (cannot remove)"
                    else
                        echo "  • $p"
                    fi
                done
            fi
            echo ""
            exit 0
            ;;
        --force|-f)
            FORCE=true
            shift
            ;;
    esac
fi

# Direct profile name (with or without --force)
if [[ $# -gt 0 ]]; then
    remove_profile "$1" "$FORCE"
    exit 0
fi

# Interactive mode
mapfile -t PROFILES < <(discover_profiles)

if [[ ${#PROFILES[@]} -eq 0 ]]; then
    echo ""
    echo -e "${YELLOW}No profiles found in ${HOME}/.hermes/profiles/${NC}"
    echo "Nothing to remove."
    exit 0
fi

ACTIVE=$(get_active_profile)

echo ""
echo -e "${BOLD}Select profile to remove:${NC}"
echo "──────────────────────────"
for i in "${!PROFILES[@]}"; do
    if [[ "${PROFILES[$i]}" == "$ACTIVE" ]]; then
        echo -e "  $((i+1))) ${GREEN}${PROFILES[$i]}${NC} ← active (cannot remove)"
    elif [[ "${PROFILES[$i]}" == "default" ]]; then
        echo -e "  $((i+1))) ${YELLOW}${PROFILES[$i]}${NC} ← default (needs --force)"
    else
        echo "  $((i+1))) ${PROFILES[$i]}"
    fi
done
echo ""

# Filter to only removable profiles
REMOVABLE=()
for p in "${PROFILES[@]}"; do
    if [[ "$p" != "$ACTIVE" ]]; then
        REMOVABLE+=("$p")
    fi
done

if [[ ${#REMOVABLE[@]} -eq 0 ]]; then
    echo -e "${YELLOW}All profiles are either active or protected. Nothing to remove.${NC}"
    exit 0
fi

echo -n "Select [1-${#PROFILES[@]}]: "
read -r SELECTION

if [[ ! "$SELECTION" =~ ^[0-9]+$ ]] || [[ "$SELECTION" -lt 1 ]] || [[ "$SELECTION" -gt ${#PROFILES[@]} ]]; then
    echo -e "${RED}Invalid selection.${NC}"
    exit 1
fi

PROFILE_NAME="${PROFILES[$((SELECTION-1))]}"

if [[ "$PROFILE_NAME" == "$ACTIVE" ]]; then
    echo -e "${RED}Cannot remove active profile '${PROFILE_NAME}'. Switch profiles first.${NC}"
    exit 1
fi

remove_profile "$PROFILE_NAME" "$FORCE"
