#!/bin/bash

#
# Script Name: system-update.sh
# Description: RHEL/CentOS system update script with DNF by default, optional Flatpak/firmware updates, and RPM configuration conflict detection
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
#   system-update.sh --enable-flatpak
#   system-update.sh --enable-firmware
#
# Requirements:
#   - Bash 4.0 or higher
#   - sudo privileges for system updates
#   - dnf package manager
#   - RHEL/CentOS/Rocky/AlmaLinux system
#
# Compatibility:
#   - Target OS: RHEL_CENTOS
#   - Tested on: RHEL 8/9, CentOS 8/9, Rocky Linux 8/9, AlmaLinux 8/9
#   - Package Manager: dnf
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
    RHEL/CentOS system update script that performs DNF package updates by default.
    Optionally updates Flatpak applications and firmware when explicitly enabled.
    Detects RPM configuration conflicts and provides detailed information about
    manual actions required.

Options:
    -h, --help              Show this help message and exit
    -v, --verbose           Enable verbose debug output
    -d, --dry-run           Show what would be done without executing
    --show-output           Display full command output in real-time
    --enable-firmware       Enable firmware updates (requires fwupd installation)
    --enable-flatpak        Enable Flatpak application updates
    --version               Show version information

Examples:
    $SCRIPT_NAME                          # Basic DNF update only
    $SCRIPT_NAME --verbose --show-output  # DNF update with full output display
    $SCRIPT_NAME --dry-run                # See what would be updated
    $SCRIPT_NAME --enable-flatpak         # Include Flatpak app updates
    $SCRIPT_NAME --enable-firmware        # Include firmware updates

Notes:
    - This script is designed for RHEL 8+, CentOS 8+, Rocky Linux, and AlmaLinux
    - Snap packages are not supported (not common on RHEL-based systems)
    - Major version upgrades (RHEL 8 -> 9) require specialized migration tools

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

# Get RHEL/CentOS version
get_os_version() {
    if [[ -f /etc/os-release ]]; then
        # shellcheck source=/dev/null
        source /etc/os-release
        echo "$VERSION_ID"
    elif [[ -f /etc/redhat-release ]]; then
        grep -oE '[0-9]+\.[0-9]+' /etc/redhat-release | head -1
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
        rhel|centos|rocky|almalinux) echo "dnf" ;;
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

# Check for RPM configuration conflicts
check_rpm_config_conflicts() {
    local dnf_output="$1"
    local conflicts_found=false
    
    # Check for various types of RPM configuration conflicts
    if echo "$dnf_output" | grep -q "warning.*saved as.*\.rpmsave"; then
        conflicts_found=true
        CONFIG_CONFLICTS+=("Configuration files backed up as .rpmsave files")
    fi
    
    if echo "$dnf_output" | grep -q "warning.*created as.*\.rpmnew"; then
        conflicts_found=true
        CONFIG_CONFLICTS+=("New configuration files created as .rpmnew files")
    fi
    
    if echo "$dnf_output" | grep -q "Transaction check error:"; then
        conflicts_found=true
        CONFIG_CONFLICTS+=("RPM transaction conflicts detected")
    fi
    
    if echo "$dnf_output" | grep -q "file.*conflicts between"; then
        conflicts_found=true
        CONFIG_CONFLICTS+=("File conflicts between packages detected")
    fi
    
    # Extract specific configuration files mentioned
    while IFS= read -r line; do
        if [[ "$line" =~ warning:.*(/etc/[^[:space:]]+).*saved.as.* ]]; then
            CONFIG_CONFLICTS+=("Config file backup: ${BASH_REMATCH[1]}")
        elif [[ "$line" =~ warning:.*(/etc/[^[:space:]]+).*created.as.* ]]; then
            CONFIG_CONFLICTS+=("New config file: ${BASH_REMATCH[1]}")
        fi
    done <<< "$dnf_output"
    
    if [[ "$conflicts_found" == true ]]; then
        MANUAL_ACTIONS+=("Review RPM configuration conflicts - check for .rpmsave and .rpmnew files")
        MANUAL_ACTIONS+=("Find config conflicts: find /etc -name '*.rpmsave' -o -name '*.rpmnew' -type f")
        MANUAL_ACTIONS+=("Compare config files manually and merge changes as needed")
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

# Get current running kernel version
get_running_kernel() {
    uname -r
}

# Get latest installed kernel version
get_latest_kernel() {
    rpm -q kernel --qf "%{VERSION}-%{RELEASE}.%{ARCH}\n" | sort -V | tail -1
}

# Check if kernel update requires reboot
check_kernel_update() {
    local running_kernel
    local latest_kernel
    
    running_kernel=$(get_running_kernel)
    latest_kernel=$(get_latest_kernel)
    
    log_debug "Running kernel: $running_kernel"
    log_debug "Latest kernel: $latest_kernel"
    
    if [[ "$running_kernel" != "$latest_kernel" ]]; then
        REBOOT_REQUIRED=true
        MANUAL_ACTIONS+=("Kernel update detected - system reboot required")
        MANUAL_ACTIONS+=("Running: $running_kernel, Latest: $latest_kernel")
    fi
}

# DNF package management functions
update_dnf_packages() {
    log_section "Updating DNF Packages"
    
    # DNF update combines repository refresh and package upgrade
    local dnf_output
    if [[ "$DRY_RUN" == false ]]; then
        # First check what would be updated
        local update_count
        update_count=$(dnf list --updates 2>/dev/null | tail -n +2 | wc -l)
        if [[ $update_count -gt 0 ]]; then
            log_info "Found $update_count packages to update"
            UPDATED_PACKAGES+=("DNF packages: $update_count updates available")
        else
            log_info "All DNF packages are up to date"
        fi
        
        # Perform the update and capture output for conflict detection
        dnf_output=$(execute_command "sudo dnf update -y" "Updating system packages" true)
        check_rpm_config_conflicts "$dnf_output"
        check_kernel_update
    else
        execute_command "sudo dnf update -y" "Would update system packages"
    fi
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
        MANUAL_ACTIONS+=("Install Flatpak: sudo dnf install flatpak")
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
        log_warn "fwupdmgr not available - install with: sudo dnf install fwupd"
        MANUAL_ACTIONS+=("Install fwupd for firmware updates: sudo dnf install fwupd")
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
    
    execute_command "sudo dnf autoremove -y" "Removing orphaned packages"
    execute_command "sudo dnf clean all" "Cleaning package cache and metadata"
    
    # Clean flatpak cache if flatpak updates were enabled
    if command_exists flatpak && [[ "$ENABLE_FLATPAK" == true ]]; then
        execute_command "flatpak uninstall --unused -y" "Removing unused Flatpak runtimes"
    fi
}

# Post-update system checks
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
        # Alternative check using dnf history for recently updated packages
        if [[ "$DRY_RUN" == false ]]; then
            local recent_updates
            recent_updates=$(dnf history list --reverse | head -20 | grep -c "Update" || true)
            if [[ $recent_updates -gt 0 ]]; then
                MANUAL_ACTIONS+=("Consider installing 'needrestart' to check for service restart requirements")
                MANUAL_ACTIONS+=("Some services may need restart after library updates")
            fi
        fi
    fi
}

check_broken_packages() {
    # Check for broken dependencies
    local broken_output
    broken_output=$(dnf check 2>&1 || true)
    if [[ -n "$broken_output" ]] && [[ "$broken_output" != *"No problems found"* ]]; then
        MANUAL_ACTIONS+=("Package dependency issues detected - run: sudo dnf check")
    fi
}

# Check requirements
check_requirements() {
    local missing_deps=()
    
    # Check OS compatibility
    check_os_compatibility "rhel-centos"
    
    # Check RHEL/CentOS version
    local os_version
    os_version=$(get_os_version)
    local major_version
    major_version=$(echo "$os_version" | cut -d. -f1)
    
    if [[ "$major_version" -lt 8 ]]; then
        log_warn "This script is designed for RHEL/CentOS 8+ (detected: version $os_version)"
        log_warn "Older versions may work but are not officially supported"
    fi
    
    # Check for essential commands
    if ! command_exists dnf; then
        # Try yum as fallback
        if ! command_exists yum; then
            missing_deps+=("dnf or yum")
        else
            log_info "Using yum as package manager (dnf preferred for RHEL 8+)"
        fi
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
        log_section "RPM Configuration Conflicts Detected"
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
        if [[ "$action" =~ ^.*[Rr]eboot.*$ ]] || [[ "$action" =~ ^.*[Kk]ernel.*$ ]] || [[ "$action" =~ ^.*[Cc]onflict.*$ ]]; then
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
        log_error "A kernel update has been installed that requires a system restart."
        log_error "The system is currently running an older kernel version."
        log_error "Please reboot your system when convenient to use the new kernel."
    fi
}

# Main function
main() {
    log_info "Starting RHEL/CentOS System Update (v$SCRIPT_VERSION)"
    
    if [[ "$DRY_RUN" == true ]]; then
        log_warn "Running in DRY RUN mode - no changes will be made"
    fi
    
    # Perform updates in logical order
    update_dnf_packages
    update_flatpak_packages
    update_firmware
    cleanup_system
    
    # Post-update checks
    if [[ "$DRY_RUN" == false ]]; then
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