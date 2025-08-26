#!/bin/bash

#
# Script Name: system-update.sh
# Description: Ubuntu system update script with APT by default, optional Snap/Flatpak/firmware updates, and configuration conflict detection
# Author: Zachary Arthur
# Created: 2025-08-26
# Last Modified: 2025-08-26
#
# Usage: system-update.sh [OPTIONS]
#
# Examples:
#   system-update.sh --help
#   system-update.sh --verbose --show-output
#   system-update.sh --dry-run
#   system-update.sh --enable-snap --enable-flatpak
#   system-update.sh --enable-dist-upgrade --enable-firmware
#
# Requirements:
#   - Bash 4.0 or higher
#   - sudo privileges for system updates
#   - apt package manager
#   - Ubuntu/Debian system
#
# Compatibility:
#   - Target OS: DEBIAN_UBUNTU
#   - Tested on: Ubuntu 24.04 LTS (Noble)
#   - Package Manager: apt
#   - Service Manager: systemd
#

set -euo pipefail

# Script configuration
readonly SCRIPT_NAME="$(basename "$0")"
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly SCRIPT_VERSION="1.0.0"

# Default values
VERBOSE=false
DRY_RUN=false
SHOW_OUTPUT=false
ENABLE_FIRMWARE=false
ENABLE_FLATPAK=false
ENABLE_SNAP=false
ENABLE_DIST_UPGRADE=false

# Colors for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly CYAN='\033[0;36m'
readonly BOLD='\033[1m'
readonly NC='\033[0m' # No Color

# Update tracking
declare -a UPDATED_PACKAGES=()
declare -a MANUAL_ACTIONS=()
declare -a CONFIG_CONFLICTS=()
REBOOT_REQUIRED=false

# Logging functions
log_info() {
    echo -e "${GREEN}[INFO]${NC} $*" >&2
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $*" >&2
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $*" >&2
}

log_debug() {
    if [[ "$VERBOSE" == true ]]; then
        echo -e "${BLUE}[DEBUG]${NC} $*" >&2
    fi
}

log_section() {
    echo -e "${CYAN}${BOLD}=== $* ===${NC}" >&2
}

# Error handling
error_exit() {
    log_error "$1"
    exit "${2:-1}"
}

# Cleanup function
cleanup() {
    log_debug "Cleaning up..."
    # Remove any temporary files if created
}

# Set trap for cleanup
trap cleanup EXIT

# Usage information
usage() {
    cat << EOF
Usage: $SCRIPT_NAME [OPTIONS]

Description:
    Ubuntu system update script that performs APT package updates by default.
    Optionally updates Snap packages, Flatpak applications, performs distribution
    upgrades, and firmware updates when explicitly enabled. Detects configuration
    conflicts and provides detailed information about manual actions required.

Options:
    -h, --help              Show this help message and exit
    -v, --verbose           Enable verbose debug output
    -d, --dry-run           Show what would be done without executing
    --show-output           Display full command output in real-time
    --enable-firmware       Enable firmware updates (requires fwupd installation)
    --enable-flatpak        Enable Flatpak application updates
    --enable-snap           Enable Snap package updates
    --enable-dist-upgrade   Enable distribution upgrades (beyond regular upgrades)
    --version               Show version information

Examples:
    $SCRIPT_NAME                          # Basic APT update and upgrade only
    $SCRIPT_NAME --verbose --show-output  # APT update with full output display
    $SCRIPT_NAME --dry-run                # See what would be updated
    $SCRIPT_NAME --enable-snap            # Include Snap package updates
    $SCRIPT_NAME --enable-flatpak         # Include Flatpak app updates
    $SCRIPT_NAME --enable-dist-upgrade    # Include distribution upgrades
    $SCRIPT_NAME --enable-firmware        # Include firmware updates

EOF
}

# Version information
version() {
    echo "$SCRIPT_NAME version $SCRIPT_VERSION"
}

# Check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# OS Detection functions
detect_os() {
    if [[ -f /etc/os-release ]]; then
        # shellcheck source=/dev/null
        source /etc/os-release
        echo "$ID"
    elif [[ -f /etc/redhat-release ]]; then
        echo "rhel"
    elif [[ -f /etc/debian_version ]]; then
        echo "debian"
    elif [[ -f /etc/arch-release ]]; then
        echo "arch"
    elif [[ -f /etc/alpine-release ]]; then
        echo "alpine"
    else
        echo "unknown"
    fi
}

# Get package manager
get_package_manager() {
    local os_id
    os_id=$(detect_os)
    
    case "$os_id" in
        ubuntu|debian) echo "apt" ;;
        rhel|centos|rocky|almalinux) echo "yum" ;;
        fedora) echo "dnf" ;;
        arch|manjaro) echo "pacman" ;;
        opensuse*) echo "zypper" ;;
        alpine) echo "apk" ;;
        *) echo "unknown" ;;
    esac
}

# Check OS compatibility
check_os_compatibility() {
    local required_os="$1"
    local current_os
    current_os=$(detect_os)
    
    case "$required_os" in
        "debian-ubuntu")
            if [[ "$current_os" != "ubuntu" && "$current_os" != "debian" ]]; then
                error_exit "This script requires Debian or Ubuntu (detected: $current_os)"
            fi
            ;;
        "rhel-centos")
            if [[ "$current_os" != "rhel" && "$current_os" != "centos" && "$current_os" != "rocky" && "$current_os" != "almalinux" ]]; then
                error_exit "This script requires RHEL/CentOS/Rocky/Alma (detected: $current_os)"
            fi
            ;;
        "fedora")
            if [[ "$current_os" != "fedora" ]]; then
                error_exit "This script requires Fedora (detected: $current_os)"
            fi
            ;;
        "arch")
            if [[ "$current_os" != "arch" && "$current_os" != "manjaro" ]]; then
                error_exit "This script requires Arch Linux or Manjaro (detected: $current_os)"
            fi
            ;;
        "opensuse")
            if [[ "$current_os" != opensuse* ]]; then
                error_exit "This script requires openSUSE (detected: $current_os)"
            fi
            ;;
        "alpine")
            if [[ "$current_os" != "alpine" ]]; then
                error_exit "This script requires Alpine Linux (detected: $current_os)"
            fi
            ;;
        "universal")
            log_debug "Universal script - no OS restriction"
            ;;
        *)
            log_warn "Unknown OS requirement: $required_os"
            ;;
    esac
}

# Check if running as root
check_root() {
    if [[ $EUID -eq 0 ]]; then
        log_warn "Running as root. Consider using sudo instead for better security."
    fi
}

# Check sudo availability
check_sudo() {
    if ! sudo -n true 2>/dev/null; then
        log_info "This script requires sudo privileges for system updates."
        log_info "You may be prompted for your password during execution."
    fi
}

# Check for configuration conflicts in apt output
check_config_conflicts() {
    local apt_output="$1"
    local conflicts_found=false
    
    # Check for various types of configuration conflicts
    if echo "$apt_output" | grep -q "Configuration file.*which you have modified"; then
        conflicts_found=true
        CONFIG_CONFLICTS+=("Modified configuration files detected during package updates")
    fi
    
    if echo "$apt_output" | grep -q "dpkg: configuration conflict"; then
        conflicts_found=true
        CONFIG_CONFLICTS+=("dpkg configuration conflicts detected")
    fi
    
    if echo "$apt_output" | grep -q "conffile.*differs from"; then
        conflicts_found=true
        CONFIG_CONFLICTS+=("Configuration file differences detected")
    fi
    
    if echo "$apt_output" | grep -q "*** .*\.dpkg-"; then
        conflicts_found=true
        CONFIG_CONFLICTS+=("dpkg backup files created (*.dpkg-old, *.dpkg-new, *.dpkg-dist)")
    fi
    
    # Extract specific configuration files mentioned
    while IFS= read -r line; do
        if [[ "$line" =~ Configuration\ file\ \'([^\']+)\' ]]; then
            CONFIG_CONFLICTS+=("Config file needs review: ${BASH_REMATCH[1]}")
        fi
    done <<< "$apt_output"
    
    if [[ "$conflicts_found" == true ]]; then
        MANUAL_ACTIONS+=("Review configuration conflicts - run: sudo dpkg --configure -a")
        MANUAL_ACTIONS+=("Check for .dpkg-* files in /etc: find /etc -name '*.dpkg-*' -type f")
    fi
}

# Execute command with proper logging
execute_command() {
    local cmd="$1"
    local description="$2"
    local capture_output="${3:-false}"
    
    if [[ "$DRY_RUN" == true ]]; then
        log_info "[DRY RUN] Would execute: $description"
        log_debug "[DRY RUN] Command: $cmd"
        return 0
    fi
    
    log_info "$description"
    log_debug "Executing: $cmd"
    
    if [[ "$SHOW_OUTPUT" == true ]]; then
        # Show full command output in real-time
        eval "$cmd"
    elif [[ "$VERBOSE" == true ]]; then
        # Show command output for verbose mode
        eval "$cmd"
    elif [[ "$capture_output" == true ]]; then
        # Capture output for parsing (like conflict detection)
        eval "$cmd" 2>&1
    else
        # Silent execution
        eval "$cmd" >/dev/null 2>&1
    fi
}

# APT package management functions
update_apt_packages() {
    log_section "Updating APT Package Lists"
    
    execute_command "sudo apt update" "Updating package database"
    
    if [[ "$DRY_RUN" == false ]]; then
        local upgradeable_count
        upgradeable_count=$(apt list --upgradeable 2>/dev/null | wc -l)
        if [[ $upgradeable_count -gt 1 ]]; then
            log_info "Found $((upgradeable_count - 1)) upgradeable packages"
            UPDATED_PACKAGES+=("APT packages: $((upgradeable_count - 1)) available")
        else
            log_info "All APT packages are up to date"
        fi
    fi
}

upgrade_apt_packages() {
    log_section "Upgrading APT Packages"
    
    # Capture output to check for conflicts
    local apt_output
    if [[ "$DRY_RUN" == false ]]; then
        apt_output=$(execute_command "sudo apt upgrade -y" "Upgrading installed packages" true)
        check_config_conflicts "$apt_output"
    else
        execute_command "sudo apt upgrade -y" "Upgrading installed packages"
    fi
}

# Distribution upgrade function (now separate and optional)
upgrade_distribution() {
    if [[ "$ENABLE_DIST_UPGRADE" == false ]]; then
        # Check if dist-upgrade would do anything additional
        if [[ "$DRY_RUN" == false ]]; then
            local dist_upgrades
            dist_upgrades=$(apt list --upgradeable 2>/dev/null | wc -l)
            if [[ $dist_upgrades -gt 1 ]]; then
                log_info "Additional packages available via distribution upgrade (use --enable-dist-upgrade)"
                MANUAL_ACTIONS+=("Consider running with --enable-dist-upgrade for additional package updates")
            fi
        fi
        return 0
    fi
    
    log_section "Performing Distribution Upgrade"
    
    # Capture output to check for conflicts
    local apt_output
    if [[ "$DRY_RUN" == false ]]; then
        apt_output=$(execute_command "sudo apt dist-upgrade -y" "Performing distribution upgrade" true)
        check_config_conflicts "$apt_output"
    else
        execute_command "sudo apt dist-upgrade -y" "Would perform distribution upgrade"
    fi
}

# Snap package management
update_snap_packages() {
    if [[ "$ENABLE_SNAP" == false ]]; then
        if command_exists snap && [[ "$DRY_RUN" == false ]]; then
            local snap_count
            snap_count=$(snap list 2>/dev/null | tail -n +2 | wc -l)
            if [[ $snap_count -gt 0 ]]; then
                log_info "Snap packages available for update (use --enable-snap)"
                MANUAL_ACTIONS+=("Consider running with --enable-snap to update $snap_count Snap packages")
            fi
        fi
        return 0
    fi
    
    if ! command_exists snap; then
        log_warn "Snap not installed but --enable-snap specified"
        MANUAL_ACTIONS+=("Install snapd to use Snap packages: sudo apt install snapd")
        return 0
    fi
    
    log_section "Updating Snap Packages"
    
    if [[ "$DRY_RUN" == false ]]; then
        local snap_list
        snap_list=$(snap list 2>/dev/null | tail -n +2 | wc -l)
        if [[ $snap_list -gt 0 ]]; then
            log_info "Found $snap_list Snap packages to check"
            UPDATED_PACKAGES+=("Snap packages: $snap_list checked")
        fi
    fi
    
    execute_command "sudo snap refresh" "Refreshing Snap packages"
}

# Flatpak package management
update_flatpak_packages() {
    if [[ "$ENABLE_FLATPAK" == false ]]; then
        if command_exists flatpak && [[ "$DRY_RUN" == false ]]; then
            local flatpak_count
            flatpak_count=$(flatpak list --app 2>/dev/null | wc -l)
            if [[ $flatpak_count -gt 0 ]]; then
                log_info "Flatpak applications available for update (use --enable-flatpak)"
                MANUAL_ACTIONS+=("Consider running with --enable-flatpak to update $flatpak_count Flatpak apps")
            fi
        fi
        return 0
    fi
    
    if ! command_exists flatpak; then
        log_warn "Flatpak not installed but --enable-flatpak specified"
        MANUAL_ACTIONS+=("Install Flatpak to use Flatpak apps: sudo apt install flatpak")
        return 0
    fi
    
    log_section "Updating Flatpak Packages"
    
    if [[ "$DRY_RUN" == false ]]; then
        local flatpak_count
        flatpak_count=$(flatpak list --app 2>/dev/null | wc -l)
        if [[ $flatpak_count -gt 0 ]]; then
            log_info "Found $flatpak_count Flatpak applications to check"
            UPDATED_PACKAGES+=("Flatpak apps: $flatpak_count checked")
        fi
    fi
    
    execute_command "flatpak update -y" "Updating Flatpak applications"
}

# Firmware update management
update_firmware() {
    if [[ "$ENABLE_FIRMWARE" == false ]]; then
        log_debug "Firmware updates disabled (use --enable-firmware to enable)"
        return 0
    fi
    
    if ! command_exists fwupdmgr; then
        log_warn "fwupdmgr not available - install with: sudo apt install fwupd"
        MANUAL_ACTIONS+=("Install fwupd for firmware updates: sudo apt install fwupd")
        return 0
    fi
    
    log_section "Checking Firmware Updates"
    
    execute_command "fwupdmgr refresh --force" "Refreshing firmware metadata"
    
    if [[ "$DRY_RUN" == false ]]; then
        local firmware_updates
        firmware_updates=$(fwupdmgr get-updates 2>/dev/null | grep -c "Update" || true)
        if [[ $firmware_updates -gt 0 ]]; then
            log_info "Found $firmware_updates firmware updates available"
            execute_command "fwupdmgr update -y" "Applying firmware updates"
            UPDATED_PACKAGES+=("Firmware: $firmware_updates updates applied")
        else
            log_info "No firmware updates available"
        fi
    else
        execute_command "fwupdmgr update -y" "Would apply available firmware updates"
    fi
}

# System cleanup functions
cleanup_system() {
    log_section "Cleaning Up System"
    
    execute_command "sudo apt autoremove -y" "Removing orphaned packages"
    execute_command "sudo apt autoclean" "Cleaning package cache"
    
    # Clean snap cache if snap updates were enabled
    if command_exists snap && [[ "$ENABLE_SNAP" == true ]]; then
        # Snap doesn't have a direct cache clean, but we can check disk usage
        if [[ "$DRY_RUN" == false ]]; then
            local snap_cache_size
            snap_cache_size=$(du -sh /var/lib/snapd/cache 2>/dev/null | cut -f1 || echo "0")
            log_debug "Snap cache size: $snap_cache_size"
        fi
    fi
    
    # Clean flatpak cache if flatpak updates were enabled
    if command_exists flatpak && [[ "$ENABLE_FLATPAK" == true ]]; then
        execute_command "flatpak uninstall --unused -y" "Removing unused Flatpak runtimes"
    fi
}

# Post-update system checks
check_reboot_required() {
    if [[ -f /var/run/reboot-required ]]; then
        REBOOT_REQUIRED=true
        MANUAL_ACTIONS+=("System reboot required for kernel/critical updates")
        
        if [[ -f /var/run/reboot-required.pkgs ]]; then
            local reboot_pkgs
            reboot_pkgs=$(cat /var/run/reboot-required.pkgs | tr '\n' ' ')
            MANUAL_ACTIONS+=("Packages requiring reboot: $reboot_pkgs")
        fi
    fi
}

check_service_restarts() {
    # Check for services that need restart after library updates
    if command_exists needrestart; then
        log_debug "Using needrestart to check for service restarts"
        local services_need_restart
        services_need_restart=$(needrestart -r l 2>/dev/null | grep -c "NEEDRESTART-SVC:" || true)
        if [[ $services_need_restart -gt 0 ]]; then
            MANUAL_ACTIONS+=("$services_need_restart services may need restart (run: sudo needrestart)")
        fi
    else
        MANUAL_ACTIONS+=("Consider installing 'needrestart' to check for service restart requirements")
    fi
}

check_broken_packages() {
    local broken_count
    broken_count=$(apt-cache check 2>&1 | grep -c "broken" || true)
    if [[ $broken_count -gt 0 ]]; then
        MANUAL_ACTIONS+=("Broken packages detected - run: sudo apt --fix-broken install")
    fi
}

# Check requirements
check_requirements() {
    local missing_deps=()
    
    # Check OS compatibility
    check_os_compatibility "debian-ubuntu"
    
    # Check for essential commands
    if ! command_exists apt; then
        missing_deps+=("apt")
    fi
    
    if ! command_exists sudo; then
        missing_deps+=("sudo")
    fi
    
    if [[ ${#missing_deps[@]} -gt 0 ]]; then
        error_exit "Missing required dependencies: ${missing_deps[*]}"
    fi
    
    # Additional checks
    check_root
    check_sudo
}

# Display summary of actions
display_summary() {
    log_section "Update Summary"
    
    if [[ ${#UPDATED_PACKAGES[@]} -gt 0 ]]; then
        log_info "Updates completed:"
        for update in "${UPDATED_PACKAGES[@]}"; do
            log_info "  * $update"
        done
    else
        log_info "No packages were updated (system may already be current)"
    fi
    
    # Display configuration conflicts (critical)
    if [[ ${#CONFIG_CONFLICTS[@]} -gt 0 ]]; then
        log_section "Configuration Conflicts Detected"
        log_error "CRITICAL: Configuration conflicts need manual resolution:"
        for conflict in "${CONFIG_CONFLICTS[@]}"; do
            log_error "  [!] $conflict"
        done
    fi
    
    # Categorize manual actions
    local -a critical_actions=()
    local -a recommended_actions=()
    local -a optional_actions=()
    
    for action in "${MANUAL_ACTIONS[@]}"; do
        if [[ "$action" =~ ^.*[Rr]eboot.*$ ]] || [[ "$action" =~ ^.*[Cc]onflict.*$ ]] || [[ "$action" =~ ^.*dpkg.*$ ]]; then
            critical_actions+=("$action")
        elif [[ "$action" =~ ^.*[Cc]onsider.*$ ]] || [[ "$action" =~ ^.*needrestart.*$ ]]; then
            optional_actions+=("$action")
        else
            recommended_actions+=("$action")
        fi
    done
    
    # Display categorized actions
    if [[ ${#critical_actions[@]} -gt 0 ]]; then
        log_section "Critical Actions Required"
        log_error "These actions are essential and should be performed soon:"
        for action in "${critical_actions[@]}"; do
            log_error "  [!] $action"
        done
    fi
    
    if [[ ${#recommended_actions[@]} -gt 0 ]]; then
        log_section "Recommended Actions"
        log_warn "These actions are recommended for optimal system health:"
        for action in "${recommended_actions[@]}"; do
            log_warn "  * $action"
        done
    fi
    
    if [[ ${#optional_actions[@]} -gt 0 ]]; then
        log_section "Optional Actions"
        log_info "Consider these actions for additional functionality:"
        for action in "${optional_actions[@]}"; do
            log_info "  - $action"
        done
    fi
    
    if [[ "$REBOOT_REQUIRED" == true ]]; then
        echo
        log_error "*** SYSTEM REBOOT REQUIRED ***"
        log_error "Critical updates have been installed that require a system restart."
        log_error "Reason: Kernel or critical system library updates"
        log_error "Please reboot your system when convenient."
    fi
}

# Main function
main() {
    log_info "Starting Ubuntu System Update (v$SCRIPT_VERSION)"
    
    if [[ "$DRY_RUN" == true ]]; then
        log_warn "Running in DRY RUN mode - no changes will be made"
    fi
    
    # Perform updates in logical order
    update_apt_packages
    upgrade_apt_packages
    upgrade_distribution
    update_snap_packages
    update_flatpak_packages
    update_firmware
    cleanup_system
    
    # Post-update checks
    if [[ "$DRY_RUN" == false ]]; then
        check_reboot_required
        check_service_restarts
        check_broken_packages
    fi
    
    # Display final summary
    display_summary
    
    log_info "System update completed successfully"
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            usage
            exit 0
            ;;
        -v|--verbose)
            VERBOSE=true
            shift
            ;;
        -d|--dry-run)
            DRY_RUN=true
            shift
            ;;
        --show-output)
            SHOW_OUTPUT=true
            shift
            ;;
        --enable-firmware)
            ENABLE_FIRMWARE=true
            shift
            ;;
        --enable-flatpak)
            ENABLE_FLATPAK=true
            shift
            ;;
        --enable-snap)
            ENABLE_SNAP=true
            shift
            ;;
        --enable-dist-upgrade)
            ENABLE_DIST_UPGRADE=true
            shift
            ;;
        --version)
            version
            exit 0
            ;;
        -*)
            error_exit "Unknown option: $1"
            ;;
        *)
            # Positional arguments
            error_exit "This script does not accept positional arguments: $1"
            shift
            ;;
    esac
done

# Check requirements before running
check_requirements

# Run main function
main "$@"