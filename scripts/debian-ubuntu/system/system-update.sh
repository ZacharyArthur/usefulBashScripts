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
#   - apt-get package manager
#   - Ubuntu/Debian system
#
# Compatibility:
#   - Target OS: DEBIAN_UBUNTU
#   - Tested on: Ubuntu 24.04 LTS (Noble)
#   - Package Manager: apt-get
#   - Service Manager: systemd
#

set -euo pipefail

# Script configuration
readonly SCRIPT_NAME="$(basename "$0")"
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly SCRIPT_VERSION="1.0.0"

# Default values
verbose=false
dry_run=false
show_output=false
enable_firmware=false
enable_flatpak=false
enable_snap=false
enable_dist_upgrade=false

# Colors for output (TTY-aware)
if [[ -t 2 ]] && [[ -z "${NO_COLOR:-}" ]]; then
    readonly RED='\033[0;31m'
    readonly GREEN='\033[0;32m'
    readonly YELLOW='\033[1;33m'
    readonly BLUE='\033[0;34m'
    readonly CYAN='\033[0;36m'
    readonly BOLD='\033[1m'
    readonly NC='\033[0m'
else
    readonly RED=''
    readonly GREEN=''
    readonly YELLOW=''
    readonly BLUE=''
    readonly CYAN=''
    readonly BOLD=''
    readonly NC=''
fi

# Update tracking
declare -a updated_packages=()
declare -a manual_actions=()
declare -a config_conflicts=()
reboot_required=false

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
    if [[ "$verbose" == true ]]; then
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
        ubuntu|debian) echo "apt-get" ;;
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

# Check and initialize sudo session
check_sudo() {
    # Skip sudo check in dry-run mode
    if [[ "$dry_run" == true ]]; then
        log_debug "Dry-run mode: skipping sudo validation"
        return 0
    fi
    
    if ! sudo -n true 2>/dev/null; then
        log_info "This script requires sudo privileges for system updates."
        log_info "Please enter your password to continue."
        if ! sudo -v; then
            error_exit "Failed to obtain sudo privileges"
        fi
    else
        log_debug "Sudo credentials already cached"
    fi
}

# Refresh sudo timestamp for long-running operations
refresh_sudo() {
    # Skip in dry-run mode
    if [[ "$dry_run" == true ]]; then
        return 0
    fi
    
    if ! sudo -n true 2>/dev/null; then
        log_debug "Refreshing sudo timestamp"
        sudo -v || error_exit "Failed to refresh sudo credentials"
    fi
}

# Check for configuration conflicts in apt output and filesystem
check_config_conflicts() {
    local apt_output="$1"
    local conflicts_found=false
    
    # Enhanced pattern matching for different types of conflicts
    local -a conflict_patterns=(
        "Configuration file.*which you have modified"
        "conffile.*differs from"
        "dpkg: configuration conflict"
        "A new version of configuration file.*is available"
        "What would you like to do about it"
        "Package configuration"
        "debconf: unable to initialize frontend"
        "*** .*\\.dpkg-"
    )
    
    # Check for various types of configuration conflicts in output
    for pattern in "${conflict_patterns[@]}"; do
        if echo "$apt_output" | grep -qE "$pattern"; then
            conflicts_found=true
            config_conflicts+=("Configuration prompt detected: $pattern")
            
            # Extract specific configuration files mentioned
            while IFS= read -r line; do
                if [[ "$line" =~ Configuration\ file\ [\'\"]*([^\'\"\ ]+)[\'\"]*.*which\ you\ have\ modified ]]; then
                    config_conflicts+=("Modified config file: ${BASH_REMATCH[1]}")
                    generate_config_diff_advice "${BASH_REMATCH[1]}"
                elif [[ "$line" =~ conffile\ [\'\"]*([^\'\"\ ]+)[\'\"]*.*differs\ from ]]; then
                    config_conflicts+=("Config file differs: ${BASH_REMATCH[1]}")
                    generate_config_diff_advice "${BASH_REMATCH[1]}"
                fi
            done <<< "$apt_output"
            break
        fi
    done
    
    # Comprehensive scan for dpkg backup files
    scan_config_backups
    
    # Check dpkg audit for configuration issues
    check_dpkg_consistency
    
    if [[ "$conflicts_found" == true ]]; then
        manual_actions+=("CRITICAL: Configuration conflicts require manual resolution")
        manual_actions+=("Run configuration audit: sudo dpkg --configure -a")
        manual_actions+=("List all config backups: find /etc -name '*.dpkg-*' -type f -ls")
    fi
}

# Enhanced backup file scanning with categorization
scan_config_backups() {
    local dpkg_files
    dpkg_files=$(find /etc -name "*.dpkg-*" -type f 2>/dev/null || true)
    
    if [[ -n "$dpkg_files" ]]; then
        conflicts_found=true
        config_conflicts+=("dpkg backup files found in /etc")
        
        local -i new_files=0 old_files=0 dist_files=0
        
        while IFS= read -r file; do
            if [[ -n "$file" ]]; then
                case "$file" in
                    *.dpkg-new)
                        ((new_files++))
                        config_conflicts+=("New version available: $file")
                        ;;
                    *.dpkg-old)
                        ((old_files++))
                        config_conflicts+=("Old version backed up: $file")
                        ;;
                    *.dpkg-dist)
                        ((dist_files++))
                        config_conflicts+=("Distribution version: $file")
                        ;;
                    *)
                        config_conflicts+=("Other backup: $file")
                        ;;
                esac
            fi
        done <<< "$dpkg_files"
        
        # Provide summary and guidance
        if [[ $new_files -gt 0 ]]; then
            manual_actions+=("$new_files new config versions need review (*.dpkg-new files)")
        fi
        if [[ $old_files -gt 0 ]]; then
            manual_actions+=("$old_files config backups created (*.dpkg-old files)")
        fi
        if [[ $dist_files -gt 0 ]]; then
            manual_actions+=("$dist_files distribution configs available (*.dpkg-dist files)")
        fi
    fi
}

# Generate specific advice for configuration file conflicts
generate_config_diff_advice() {
    local config_file="$1"
    local base_name="${config_file%.*}"
    
    # Check what types of backup files exist for this config
    if [[ -f "$config_file.dpkg-new" ]]; then
        manual_actions+=("Compare configs: diff '$config_file' '$config_file.dpkg-new'")
        manual_actions+=("Merge configs: vimdiff '$config_file' '$config_file.dpkg-new'")
    fi
    if [[ -f "$config_file.dpkg-old" ]]; then
        manual_actions+=("View original: diff '$config_file.dpkg-old' '$config_file'")
    fi
    if [[ -f "$config_file.dpkg-dist" ]]; then
        manual_actions+=("See distribution default: cat '$config_file.dpkg-dist'")
    fi
}

# Enhanced dpkg consistency checking
check_dpkg_consistency() {
    # Check for packages in inconsistent states
    local dpkg_status
    dpkg_status=$(sudo dpkg --audit 2>/dev/null || true)
    
    if [[ -n "$dpkg_status" ]]; then
        conflicts_found=true
        config_conflicts+=("dpkg audit found package inconsistencies")
        
        # Parse different types of dpkg issues
        while IFS= read -r line; do
            if [[ -n "$line" ]]; then
                case "$line" in
                    *"is in a very bad inconsistent state"*)
                        config_conflicts+=("CRITICAL: $line")
                        manual_actions+=("Fix broken package: sudo dpkg --configure -a")
                        ;;
                    *"missing conffiles"*)
                        config_conflicts+=("Missing config files: $line")
                        manual_actions+=("Reinstall package to restore conffiles")
                        ;;
                    *)
                        config_conflicts+=("dpkg issue: $line")
                        ;;
                esac
            fi
        done <<< "$dpkg_status"
    fi
    
    # Check for packages in half-configured state
    local half_configured
    half_configured=$(sudo dpkg -l 2>/dev/null | awk '/^[ih]/ {print $2}' || true)
    if [[ -n "$half_configured" ]]; then
        conflicts_found=true
        config_conflicts+=("Packages in half-configured state: $half_configured")
        manual_actions+=("Fix half-configured packages: sudo dpkg --configure -a")
    fi
}

# Check for and handle apt/dpkg locks with retry logic
wait_for_apt_lock() {
    # Skip lock check in dry-run mode
    if [[ "$dry_run" == true ]]; then
        return 0
    fi
    
    local max_attempts=6
    local attempt=1
    local wait_time=10
    
    while [[ $attempt -le $max_attempts ]]; do
        # Check only the critical lock files that prevent apt-get from running
        local locks_held=false
        
        if fuser /var/lib/dpkg/lock-frontend >/dev/null 2>&1; then
            locks_held=true
        elif fuser /var/lib/dpkg/lock >/dev/null 2>&1; then  
            locks_held=true
        elif fuser /var/lib/apt/lists/lock >/dev/null 2>&1; then
            locks_held=true
        elif fuser /var/cache/apt/archives/lock >/dev/null 2>&1; then
            locks_held=true
        fi
        
        if [[ "$locks_held" == false ]]; then
            return 0
        fi
        
        if [[ $attempt -eq 1 ]]; then
            log_warn "APT/dpkg locks detected, waiting for other package operations to complete..."
        fi
        
        log_debug "Lock files in use, attempt $attempt/$max_attempts - waiting ${wait_time}s"
        sleep $wait_time
        
        # Linear backoff
        wait_time=$((wait_time + 5))
        ((attempt++))
    done
    
    # Provide helpful diagnostics on failure
    log_error "Lock diagnostic information:"
    fuser /var/lib/dpkg/lock-frontend /var/lib/dpkg/lock /var/lib/apt/lists/lock /var/cache/apt/archives/lock 2>/dev/null || true
    error_exit "Failed to acquire APT/dpkg locks after $max_attempts attempts"
}

# Execute command with proper logging and output handling
execute_command() {
    local description="$1"
    shift
    local capture_output=false
    local temp_output=""
    
    # Check if last argument is capture_output flag
    if [[ "${@: -1}" == "--capture-output" ]]; then
        capture_output=true
        set -- "${@:1:$(($#-1))}" # Remove last argument
    fi
    
    if [[ "$dry_run" == true ]]; then
        log_info "[DRY RUN] Would execute: $description"
        log_debug "[DRY RUN] Command: $*"
        return 0
    fi
    
    log_info "$description"
    log_debug "Executing: $*"
    
    # Create temporary file for output capture if needed
    if [[ "$capture_output" == true ]]; then
        temp_output=$(mktemp)
    fi
    
    local exit_code=0
    
    if [[ "$show_output" == true ]] && [[ "$capture_output" == true ]]; then
        # Show output in real-time AND capture for parsing
        "$@" 2>&1 | tee "$temp_output"
        exit_code=${PIPESTATUS[0]}
    elif [[ "$show_output" == true ]] || [[ "$verbose" == true ]]; then
        # Show command output
        "$@"
        exit_code=$?
    elif [[ "$capture_output" == true ]]; then
        # Capture output for parsing only
        "$@" >"$temp_output" 2>&1
        exit_code=$?
    else
        # Silent execution
        "$@" >/dev/null 2>&1
        exit_code=$?
    fi
    
    # Return captured output if requested
    if [[ "$capture_output" == true ]]; then
        cat "$temp_output"
        rm -f "$temp_output"
    fi
    
    return $exit_code
}

# Pre-flight analysis functions
analyze_pending_updates() {
    log_section "Analyzing Pending Updates"
    
    if [[ "$dry_run" == true ]]; then
        log_debug "Skipping update analysis in dry-run mode"
        return 0
    fi
    
    # Get list of upgradeable packages with details
    local upgrade_info
    upgrade_info=$(sudo apt-get -s upgrade 2>/dev/null)
    
    # Check for kernel updates
    if echo "$upgrade_info" | grep -q "linux-image\|linux-headers\|linux-modules"; then
        log_warn "Kernel updates detected - system reboot will be required"
        manual_actions+=("CRITICAL: Kernel update requires reboot after completion")
        manual_actions+=("Bootloader (GRUB) may prompt for configuration during kernel install")
    fi
    
    # Check for critical interactive packages
    check_critical_packages "$upgrade_info"
    
    # Estimate service impacts
    estimate_service_impacts "$upgrade_info"
}

check_critical_packages() {
    local upgrade_info="$1"
    
    # Define packages known to be interactive or critical
    local -a interactive_packages=(
        "mysql-server" "mariadb-server" "postgresql" "postfix" "exim4" 
        "dovecot" "apache2" "nginx" "openssh-server" "ufw" "iptables-persistent"
        "grub-" "systemd" "dbus" "network-manager" "resolvconf"
    )
    
    for package in "${interactive_packages[@]}"; do
        if echo "$upgrade_info" | grep -q "^Inst $package\|^Inst.*$package"; then
            case "$package" in
                "mysql-server"|"mariadb-server"|"postgresql")
                    manual_actions+=("Database server ($package) update detected - may prompt for root password")
                    ;;
                "postfix"|"exim4"|"dovecot")
                    manual_actions+=("Mail server ($package) update detected - may prompt for configuration")
                    ;;
                "apache2"|"nginx")
                    manual_actions+=("Web server ($package) update detected - service restart required")
                    ;;
                "openssh-server")
                    manual_actions+=("CRITICAL: SSH server update detected - ensure you maintain access")
                    ;;
                "grub-"*)
                    manual_actions+=("Bootloader (GRUB) update detected - may prompt about configuration files")
                    ;;
                "systemd"|"dbus")
                    manual_actions+=("CRITICAL: Core system component ($package) update - may require reboot")
                    ;;
                "network-manager"|"resolvconf")
                    manual_actions+=("Network component ($package) update - may affect connectivity")
                    ;;
                *)
                    manual_actions+=("Interactive package ($package) update detected - may require user input")
                    ;;
            esac
        fi
    done
}

estimate_service_impacts() {
    local upgrade_info="$1"
    
    # Look for packages that commonly affect running services
    local -a service_packages=(
        "apache2:apache2" "nginx:nginx" "mysql-server:mysql" "postgresql:postgresql"
        "openssh-server:ssh" "docker:docker" "systemd:systemd-resolved"
        "network-manager:NetworkManager" "bluetooth:bluetooth"
    )
    
    for pkg_service in "${service_packages[@]}"; do
        local package="${pkg_service%:*}"
        local service="${pkg_service#*:}"
        
        if echo "$upgrade_info" | grep -q "^Inst $package\|^Inst.*$package"; then
            if systemctl is-active --quiet "$service" 2>/dev/null; then
                manual_actions+=("Service restart recommended: sudo systemctl restart $service")
            fi
        fi
    done
}

# APT package management functions
update_apt_packages() {
    log_section "Updating APT Package Lists"
    
    refresh_sudo
    wait_for_apt_lock
    execute_command "Updating package database" sudo DEBIAN_FRONTEND=noninteractive apt-get update
    
    if [[ "$dry_run" == false ]]; then
        local upgradeable_count
        upgradeable_count=$(sudo apt-get -s upgrade 2>/dev/null | grep -c "^Inst " || true)
        if [[ $upgradeable_count -gt 0 ]]; then
            log_info "Found $upgradeable_count upgradeable packages"
            updated_packages+=("APT packages: $upgradeable_count available")
        else
            log_info "All APT packages are up to date"
        fi
    fi
}

upgrade_apt_packages() {
    log_section "Upgrading APT Packages"
    
    refresh_sudo
    wait_for_apt_lock
    # Capture output to check for conflicts
    local apt_output
    if [[ "$dry_run" == false ]]; then
        apt_output=$(execute_command "Upgrading installed packages" sudo DEBIAN_FRONTEND=noninteractive apt-get -y -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold" upgrade --capture-output)
        check_config_conflicts "$apt_output"
    else
        execute_command "Upgrading installed packages" sudo apt-get -s upgrade
    fi
}

# Distribution upgrade function (now separate and optional)
upgrade_distribution() {
    if [[ "$enable_dist_upgrade" == false ]]; then
        # Check if dist-upgrade would do anything additional by comparing upgrade vs full-upgrade
        if [[ "$dry_run" == false ]]; then
            local upgrade_count full_upgrade_count
            upgrade_count=$(sudo apt-get -s upgrade 2>/dev/null | grep -c "^Inst " || true)
            full_upgrade_count=$(sudo apt-get -s full-upgrade 2>/dev/null | grep -c "^Inst " || true)
            
            if [[ $full_upgrade_count -gt $upgrade_count ]]; then
                log_info "Additional $((full_upgrade_count - upgrade_count)) packages available via distribution upgrade (use --enable-dist-upgrade)"
                manual_actions+=("Consider running with --enable-dist-upgrade for $((full_upgrade_count - upgrade_count)) additional package updates")
            fi
        fi
        return 0
    fi
    
    log_section "Performing Distribution Upgrade"
    
    refresh_sudo
    wait_for_apt_lock
    # Capture output to check for conflicts
    local apt_output
    if [[ "$dry_run" == false ]]; then
        apt_output=$(execute_command "Performing distribution upgrade" sudo DEBIAN_FRONTEND=noninteractive apt-get -y -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold" full-upgrade --capture-output)
        check_config_conflicts "$apt_output"
    else
        execute_command "Would perform distribution upgrade" sudo apt-get -s full-upgrade
    fi
}

# Snap package management
update_snap_packages() {
    if [[ "$enable_snap" == false ]]; then
        if command_exists snap && [[ "$dry_run" == false ]]; then
            local snap_updates
            snap_updates=$(snap refresh --list 2>/dev/null | wc -l)
            if [[ $snap_updates -gt 0 ]]; then
                log_info "$snap_updates Snap packages have available updates (use --enable-snap)"
                manual_actions+=("Consider running with --enable-snap to update $snap_updates Snap packages")
            fi
        fi
        return 0
    fi
    
    if ! command_exists snap; then
        log_warn "Snap not installed but --enable-snap specified"
        manual_actions+=("Install snapd to use Snap packages: sudo apt-get install snapd")
        return 0
    fi
    
    log_section "Updating Snap Packages"
    
    refresh_sudo
    
    if [[ "$dry_run" == false ]]; then
        local snap_updates
        snap_updates=$(snap refresh --list 2>/dev/null | wc -l)
        if [[ $snap_updates -gt 0 ]]; then
            log_info "Found $snap_updates Snap packages with updates available"
            updated_packages+=("Snap packages: $snap_updates updated")
        else
            log_info "All Snap packages are up to date"
        fi
    fi
    
    execute_command "Refreshing Snap packages" sudo snap refresh
}

# Flatpak package management
update_flatpak_packages() {
    if [[ "$enable_flatpak" == false ]]; then
        if command_exists flatpak && [[ "$dry_run" == false ]]; then
            local flatpak_updates
            flatpak_updates=$(flatpak remote-ls --updates 2>/dev/null | wc -l)
            if [[ $flatpak_updates -gt 0 ]]; then
                log_info "$flatpak_updates Flatpak applications have available updates (use --enable-flatpak)"
                manual_actions+=("Consider running with --enable-flatpak to update $flatpak_updates Flatpak apps")
            fi
        fi
        return 0
    fi
    
    if ! command_exists flatpak; then
        log_warn "Flatpak not installed but --enable-flatpak specified"
        manual_actions+=("Install Flatpak to use Flatpak apps: sudo apt-get install flatpak")
        return 0
    fi
    
    log_section "Updating Flatpak Packages"
    
    if [[ "$dry_run" == false ]]; then
        local flatpak_updates
        flatpak_updates=$(flatpak remote-ls --updates 2>/dev/null | wc -l)
        if [[ $flatpak_updates -gt 0 ]]; then
            log_info "Found $flatpak_updates Flatpak applications with updates available"
            updated_packages+=("Flatpak apps: $flatpak_updates updated")
        else
            log_info "All Flatpak applications are up to date"
        fi
    fi
    
    execute_command "Updating Flatpak applications" flatpak update -y --noninteractive
}

# Firmware update management
update_firmware() {
    if [[ "$enable_firmware" == false ]]; then
        log_debug "Firmware updates disabled (use --enable-firmware to enable)"
        return 0
    fi
    
    if ! command_exists fwupdmgr; then
        log_warn "fwupdmgr not available - install with: sudo apt-get install fwupd"
        manual_actions+=("Install fwupd for firmware updates: sudo apt-get install fwupd")
        return 0
    fi
    
    log_section "Checking Firmware Updates"
    
    refresh_sudo
    execute_command "Refreshing firmware metadata" fwupdmgr refresh --force
    
    if [[ "$dry_run" == false ]]; then
        local firmware_updates
        firmware_updates=$(fwupdmgr get-updates 2>/dev/null | grep -c "Update" || true)
        if [[ $firmware_updates -gt 0 ]]; then
            log_info "Found $firmware_updates firmware updates available"
            execute_command "Applying firmware updates" fwupdmgr update --assume-yes --no-reboot-check
            updated_packages+=("Firmware: $firmware_updates updates applied")
        else
            log_info "No firmware updates available"
        fi
    else
        execute_command "Would apply available firmware updates" fwupdmgr get-updates
    fi
}

# System cleanup functions
cleanup_system() {
    log_section "Cleaning Up System"
    
    refresh_sudo
    wait_for_apt_lock
    execute_command "Removing orphaned packages" sudo DEBIAN_FRONTEND=noninteractive apt-get -y autoremove
    execute_command "Cleaning package cache" sudo apt-get autoclean
    
    # Clean snap cache if snap updates were enabled
    if command_exists snap && [[ "$enable_snap" == true ]]; then
        # Snap doesn't have a direct cache clean, but we can check disk usage
        if [[ "$dry_run" == false ]]; then
            local snap_cache_size
            snap_cache_size=$(du -sh /var/lib/snapd/cache 2>/dev/null | cut -f1 || echo "0")
            log_debug "Snap cache size: $snap_cache_size"
        fi
    fi
    
    # Clean flatpak cache if flatpak updates were enabled
    if command_exists flatpak && [[ "$enable_flatpak" == true ]]; then
        execute_command "Removing unused Flatpak runtimes" flatpak uninstall --unused -y --noninteractive
    fi
}

# Post-update system checks
check_reboot_required() {
    if [[ -f /var/run/reboot-required ]]; then
        reboot_required=true
        manual_actions+=("System reboot required for kernel/critical updates")
        
        if [[ -f /var/run/reboot-required.pkgs ]]; then
            local reboot_pkgs
            reboot_pkgs=$(cat /var/run/reboot-required.pkgs | tr '\n' ' ')
            manual_actions+=("Packages requiring reboot: $reboot_pkgs")
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
            manual_actions+=("$services_need_restart services may need restart (run: sudo needrestart)")
        fi
    else
        manual_actions+=("Consider installing 'needrestart' to check for service restart requirements")
    fi
}

check_broken_packages() {
    # Use apt-get simulation to properly detect broken packages
    local fix_broken_output
    fix_broken_output=$(sudo apt-get -s --fix-broken install 2>&1 | grep -E "^(E:|Broken)" || true)
    
    if [[ -n "$fix_broken_output" ]]; then
        manual_actions+=("Broken packages detected - run: sudo apt-get --fix-broken install")
        manual_actions+=("Details: $fix_broken_output")
    fi
}

# Check requirements
check_requirements() {
    local missing_deps=()
    
    # Check OS compatibility
    check_os_compatibility "debian-ubuntu"
    
    # Check for essential commands
    if ! command_exists apt-get; then
        missing_deps+=("apt-get")
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
    
    if [[ ${#updated_packages[@]} -gt 0 ]]; then
        log_info "Updates completed:"
        for update in "${updated_packages[@]}"; do
            log_info "  * $update"
        done
    else
        log_info "No packages were updated (system may already be current)"
    fi
    
    # Display configuration conflicts (critical)
    if [[ ${#config_conflicts[@]} -gt 0 ]]; then
        log_section "Configuration Conflicts Detected"
        log_error "CRITICAL: Configuration conflicts need manual resolution:"
        for conflict in "${config_conflicts[@]}"; do
            log_error "  [!] $conflict"
        done
    fi
    
    # Categorize manual actions with enhanced severity detection
    local -a critical_actions=()
    local -a high_priority_actions=()
    local -a recommended_actions=()
    local -a optional_actions=()
    
    for action in "${manual_actions[@]}"; do
        if [[ "$action" =~ ^CRITICAL: ]] || [[ "$action" =~ [Kk]ernel.*reboot ]] || [[ "$action" =~ SSH.*server ]] || [[ "$action" =~ [Cc]ore.*system.*component ]]; then
            critical_actions+=("$action")
        elif [[ "$action" =~ ^.*[Rr]eboot.*$ ]] || [[ "$action" =~ [Cc]onfiguration.*conflict ]] || [[ "$action" =~ [Bb]roken.*package ]] || [[ "$action" =~ dpkg.*configure ]]; then
            high_priority_actions+=("$action")
        elif [[ "$action" =~ [Ss]ervice.*restart ]] || [[ "$action" =~ [Ww]eb.*server ]] || [[ "$action" =~ [Dd]atabase.*server ]] || [[ "$action" =~ [Cc]onfig.*review ]]; then
            recommended_actions+=("$action")
        elif [[ "$action" =~ ^.*[Cc]onsider.*$ ]] || [[ "$action" =~ needrestart ]] || [[ "$action" =~ --enable- ]]; then
            optional_actions+=("$action")
        else
            recommended_actions+=("$action")
        fi
    done
    
    # Display categorized actions with enhanced formatting
    if [[ ${#critical_actions[@]} -gt 0 ]]; then
        log_section "🚨 CRITICAL Actions Required - Immediate Attention"
        log_error "These actions are ESSENTIAL and must be performed IMMEDIATELY:"
        local -i count=1
        for action in "${critical_actions[@]}"; do
            log_error "  $count. [CRITICAL] $action"
            ((count++))
        done
        echo >&2
    fi
    
    if [[ ${#high_priority_actions[@]} -gt 0 ]]; then
        log_section "⚠️  High Priority Actions - Soon Required"
        log_warn "These actions should be performed soon for system stability:"
        local -i count=1
        for action in "${high_priority_actions[@]}"; do
            log_warn "  $count. [HIGH] $action"
            ((count++))
        done
        echo >&2
    fi
    
    if [[ ${#recommended_actions[@]} -gt 0 ]]; then
        log_section "💡 Recommended Actions - System Health"
        log_warn "These actions are recommended for optimal system operation:"
        local -i count=1
        for action in "${recommended_actions[@]}"; do
            log_warn "  $count. [RECOMMENDED] $action"
            ((count++))
        done
        echo >&2
    fi
    
    if [[ ${#optional_actions[@]} -gt 0 ]]; then
        log_section "ℹ️  Optional Actions - Additional Features"
        log_info "Consider these actions for enhanced functionality:"
        local -i count=1
        for action in "${optional_actions[@]}"; do
            log_info "  $count. [OPTIONAL] $action"
            ((count++))
        done
    fi
    
    if [[ "$reboot_required" == true ]]; then
        echo
        log_error "*** SYSTEM REBOOT REQUIRED ***"
        log_error "Critical updates have been installed that require a system restart."
        log_error "Reason: Kernel or critical system library updates"
        log_error "Please reboot your system when convenient."
    fi
}

# Enhanced logging and reporting functions
generate_summary_report() {
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    local log_file="/var/log/system-update-$(date '+%Y%m%d-%H%M%S').log"
    local temp_file=$(mktemp)
    
    # Create summary report in temp file first
    cat > "$temp_file" << EOF
===========================================
System Update Summary Report
===========================================
Date: $timestamp
Script Version: $SCRIPT_VERSION
Dry Run Mode: $dry_run
Host: $(hostname -f 2>/dev/null || hostname)
OS: $(lsb_release -d 2>/dev/null | cut -f2 || echo "Unknown")
User: $(whoami)

===========================================
UPDATES PERFORMED
===========================================
EOF

    if [[ ${#updated_packages[@]} -gt 0 ]]; then
        echo "Packages Updated:" >> "$temp_file"
        for update in "${updated_packages[@]}"; do
            echo "  - $update" >> "$temp_file"
        done
    else
        echo "No packages were updated" >> "$temp_file"
    fi

    echo -e "\n===========================================" >> "$temp_file"
    echo "CONFIGURATION CONFLICTS" >> "$temp_file"
    echo "===========================================" >> "$temp_file"
    
    if [[ ${#config_conflicts[@]} -gt 0 ]]; then
        for conflict in "${config_conflicts[@]}"; do
            echo "  ! $conflict" >> "$temp_file"
        done
    else
        echo "No configuration conflicts detected" >> "$temp_file"
    fi

    echo -e "\n===========================================" >> "$temp_file"
    echo "MANUAL ACTIONS REQUIRED" >> "$temp_file"
    echo "===========================================" >> "$temp_file"
    
    if [[ ${#manual_actions[@]} -gt 0 ]]; then
        for action in "${manual_actions[@]}"; do
            echo "  → $action" >> "$temp_file"
        done
    else
        echo "No manual actions required" >> "$temp_file"
    fi

    echo -e "\n===========================================" >> "$temp_file"
    echo "SYSTEM STATUS" >> "$temp_file"
    echo "===========================================" >> "$temp_file"
    echo "Reboot Required: $reboot_required" >> "$temp_file"
    echo "Update Completion: $timestamp" >> "$temp_file"
    
    # Only create log file if we have sudo permission and it's not a dry run
    if [[ "$dry_run" == false ]] && sudo -n true 2>/dev/null; then
        if sudo cp "$temp_file" "$log_file" 2>/dev/null; then
            log_info "Detailed report saved to: $log_file"
            manual_actions+=("Review detailed log: cat '$log_file'")
        else
            log_debug "Could not create log file $log_file (permissions or space issue)"
        fi
    else
        log_debug "Log file creation skipped (dry-run mode or insufficient permissions)"
    fi
    
    # Clean up temp file
    rm -f "$temp_file"
}

display_pre_update_summary() {
    log_section "📋 Pre-Update Analysis Summary"
    
    # Skip detailed analysis in dry-run mode
    if [[ "$dry_run" == true ]]; then
        log_info "📋 Dry-run mode: Skipping detailed pre-flight analysis"
        return 0
    fi
    
    # Count different types of pending updates
    local upgrade_info
    upgrade_info=$(sudo apt-get -s upgrade 2>/dev/null || echo "")
    local package_count
    package_count=$(echo "$upgrade_info" | grep -c "^Inst " 2>/dev/null)
    package_count=${package_count:-0}
    
    if [[ "$package_count" -gt 0 ]]; then
        log_info "📦 $package_count packages have updates available"
        
        # Categorize package types
        local security_updates
        security_updates=$(echo "$upgrade_info" | grep -c "security" 2>/dev/null)
        security_updates=${security_updates:-0}
        if [[ "$security_updates" -gt 0 ]]; then
            log_warn "🔒 $security_updates security updates detected"
        fi
        
        # Check for kernel updates specifically
        local kernel_updates
        kernel_updates=$(echo "$upgrade_info" | grep -c "linux-image\|linux-headers" 2>/dev/null)
        kernel_updates=${kernel_updates:-0}
        if [[ "$kernel_updates" -gt 0 ]]; then
            log_warn "🔄 $kernel_updates kernel-related updates (reboot will be required)"
        fi
    else
        log_info "✅ System is up to date"
    fi
    
    # Disk space check
    local available_space
    available_space=$(df /var/cache/apt/archives --output=avail | tail -1)
    local available_mb=$((available_space / 1024))
    
    if [[ $available_mb -lt 500 ]]; then
        log_warn "⚠️  Low disk space: ${available_mb}MB available (recommend 500MB+)"
        manual_actions+=("Free up disk space before major updates: apt-get autoclean")
    else
        log_debug "Disk space check: ${available_mb}MB available ✓"
    fi
    
    echo >&2
}

# Main function
main() {
    log_info "Starting Ubuntu System Update (v$SCRIPT_VERSION)"
    
    if [[ "$dry_run" == true ]]; then
        log_warn "Running in DRY RUN mode - no changes will be made"
    fi
    
    # Pre-flight analysis and summary
    display_pre_update_summary
    analyze_pending_updates
    
    # Perform updates in logical order
    update_apt_packages
    upgrade_apt_packages
    upgrade_distribution
    update_snap_packages
    update_flatpak_packages
    update_firmware
    cleanup_system
    
    # Post-update checks
    if [[ "$dry_run" == false ]]; then
        check_reboot_required
        check_service_restarts
        check_broken_packages
    fi
    
    # Display final summary
    display_summary
    
    # Generate detailed log file
    generate_summary_report
    
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
            verbose=true
            shift
            ;;
        -d|--dry-run)
            dry_run=true
            shift
            ;;
        --show-output)
            show_output=true
            shift
            ;;
        --enable-firmware)
            enable_firmware=true
            shift
            ;;
        --enable-flatpak)
            enable_flatpak=true
            shift
            ;;
        --enable-snap)
            enable_snap=true
            shift
            ;;
        --enable-dist-upgrade)
            enable_dist_upgrade=true
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
            ;;
    esac
done

# Check requirements before running
check_requirements

# Run main function
main "$@"