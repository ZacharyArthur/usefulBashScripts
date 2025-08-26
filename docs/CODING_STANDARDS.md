# Bash Coding Standards

This document outlines the coding standards and best practices for bash scripts in this repository.

## Table of Contents

- [General Guidelines](#general-guidelines)
- [Script Structure](#script-structure)
- [Error Handling](#error-handling)
- [Variables and Functions](#variables-and-functions)
- [Input/Output](#inputoutput)
- [Security Considerations](#security-considerations)
- [Performance](#performance)
- [Documentation](#documentation)

## General Guidelines

### Shebang

Always start scripts with the proper shebang:
```bash
#!/bin/bash
```

### Shell Options

Use strict mode for better error handling:
```bash
set -euo pipefail
```

- `set -e`: Exit immediately if a command exits with a non-zero status
- `set -u`: Treat unset variables as errors
- `set -o pipefail`: Pipe commands return the exit status of the last command to exit with non-zero status

### File Permissions

Make scripts executable:
```bash
chmod +x script-name.sh
```

## Script Structure

### Template Structure

Follow this general structure for all scripts:

```bash
#!/bin/bash

# Header comment with metadata
set -euo pipefail

# Constants and configuration
readonly SCRIPT_NAME="$(basename "$0")"
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Global variables
VARIABLE_NAME=""

# Functions (in order: utilities, main logic, argument parsing)
function utility_function() {
    # Function body
}

function main() {
    # Main script logic
}

# Argument parsing
while [[ $# -gt 0 ]]; do
    # Parse arguments
done

# Execute main function
main "$@"
```

## Error Handling

### Exit Codes

Use meaningful exit codes:
- `0`: Success
- `1`: General error
- `2`: Misuse of shell command
- `126`: Command invoked cannot execute
- `127`: Command not found
- `128+n`: Fatal error signal "n"

### Error Functions

Implement consistent error handling:

```bash
log_error() {
    echo "ERROR: $*" >&2
}

error_exit() {
    log_error "$1"
    exit "${2:-1}"
}

# Usage
command || error_exit "Command failed" 2
```

### Cleanup

Implement cleanup functions:

```bash
cleanup() {
    # Remove temporary files, kill background processes, etc.
    [[ -n "${TEMP_DIR:-}" ]] && rm -rf "$TEMP_DIR"
}

trap cleanup EXIT INT TERM
```

## Variables and Functions

### Variable Naming

- Use UPPER_CASE for constants and environment variables
- Use lower_case for local variables
- Use descriptive names

```bash
readonly MAX_RETRIES=3
local user_input=""
```

### Variable Declaration

- Declare variables as `local` in functions
- Use `readonly` for constants
- Initialize variables when possible

```bash
function example_function() {
    local file_path="$1"
    local -i count=0
    readonly temp_file="/tmp/script.$$"
}
```

### Function Naming

- Use lowercase with underscores
- Use descriptive names
- Prefix utility functions consistently

```bash
function check_requirements() {
    # Check if required commands exist
}

function parse_config_file() {
    # Parse configuration
}
```

### Function Structure

```bash
function function_name() {
    local param1="$1"
    local param2="${2:-default_value}"
    
    # Validate parameters
    [[ -z "$param1" ]] && error_exit "Parameter required"
    
    # Function logic
    
    return 0
}
```

## Input/Output

### Argument Parsing

Use consistent patterns for argument parsing:

```bash
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
        -f|--file)
            FILE_PATH="$2"
            shift 2
            ;;
        -*)
            error_exit "Unknown option: $1"
            ;;
        *)
            POSITIONAL_ARGS+=("$1")
            shift
            ;;
    esac
done
```

### Output Functions

Implement consistent logging:

```bash
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly NC='\033[0m'

log_info() {
    echo -e "${GREEN}[INFO]${NC} $*" >&2
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $*" >&2
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $*" >&2
}
```

### User Input

Always validate user input:

```bash
read -p "Enter filename: " filename
[[ -z "$filename" ]] && error_exit "Filename cannot be empty"
[[ ! -f "$filename" ]] && error_exit "File does not exist: $filename"
```

## Security Considerations

### Quoting

Always quote variables to prevent word splitting:

```bash
# Good
cp "$source_file" "$destination_file"

# Bad
cp $source_file $destination_file
```

### Path Handling

Use absolute paths when possible:

```bash
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly CONFIG_FILE="$SCRIPT_DIR/config.conf"
```

### Temporary Files

Create secure temporary files:

```bash
readonly TEMP_DIR="$(mktemp -d)"
readonly TEMP_FILE="$(mktemp)"

# Ensure cleanup
trap 'rm -rf "$TEMP_DIR"' EXIT
```

### Command Execution

Be careful with command execution:

```bash
# Use arrays for commands with multiple arguments
local cmd=(rsync -av --delete)
"${cmd[@]}" "$source/" "$destination/"

# Avoid eval when possible
# eval "$user_command"  # Dangerous

# Use safer alternatives
$user_command  # Still be careful
```

## Performance

### Avoid Unnecessary Subprocesses

```bash
# Good - use shell built-ins
[[ "$string" == prefix* ]]

# Avoid - external commands
if echo "$string" | grep -q "^prefix"; then
```

### Efficient Loops

```bash
# Good - read file line by line
while IFS= read -r line; do
    process_line "$line"
done < "$file"

# Avoid - loading entire file into memory
for line in $(cat "$file"); do
    process_line "$line"
done
```

## Documentation

### Header Comments

Include comprehensive header:

```bash
#!/bin/bash

#
# Script Name: example-script.sh
# Description: Brief description of what the script does
# Author: Your Name
# Created: YYYY-MM-DD
# Last Modified: YYYY-MM-DD
#
# Usage: example-script.sh [OPTIONS] [ARGUMENTS]
#
# Examples:
#   example-script.sh --help
#   example-script.sh --verbose --file /path/to/file
#
# Requirements:
#   - Bash 4.0 or higher
#   - curl (for HTTP requests)
#   - jq (for JSON processing)
#
# Compatibility:
#   - Tested on Ubuntu 22.04 LTS
#   - Should work on Debian-based systems
#
```

### Function Documentation

Document complex functions:

```bash
#
# Parses configuration file and sets global variables
#
# Arguments:
#   $1 - Path to configuration file
#
# Returns:
#   0 on success, 1 on error
#
# Globals Modified:
#   CONFIG_OPTION1
#   CONFIG_OPTION2
#
function parse_config() {
    local config_file="$1"
    # Implementation
}
```

### Inline Comments

Use comments for complex logic:

```bash
# Check if running as root (UID 0)
if [[ $EUID -eq 0 ]]; then
    log_warn "Running as root - some features may not work correctly"
fi

# Process each file in parallel, limiting to 4 concurrent jobs
while [[ $(jobs -r | wc -l) -ge 4 ]]; do
    wait -n  # Wait for any background job to complete
done
```

## Common Patterns

### Command Existence Check

```bash
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

if ! command_exists "curl"; then
    error_exit "curl is required but not installed"
fi
```

### Retry Logic

```bash
retry_command() {
    local -i max_attempts="$1"
    local -i delay="$2"
    shift 2
    local cmd=("$@")
    
    local -i attempt=1
    while [[ $attempt -le $max_attempts ]]; do
        if "${cmd[@]}"; then
            return 0
        fi
        
        log_warn "Attempt $attempt failed, retrying in ${delay}s..."
        sleep "$delay"
        ((attempt++))
    done
    
    return 1
}
```

### Configuration File Parsing

```bash
parse_config() {
    local config_file="$1"
    
    [[ ! -f "$config_file" ]] && return 1
    
    while IFS='=' read -r key value; do
        # Skip comments and empty lines
        [[ $key =~ ^[[:space:]]*# ]] && continue
        [[ -z "$key" ]] && continue
        
        # Remove leading/trailing whitespace
        key=$(echo "$key" | xargs)
        value=$(echo "$value" | xargs)
        
        case "$key" in
            "option1") OPTION1="$value" ;;
            "option2") OPTION2="$value" ;;
            *) log_warn "Unknown config option: $key" ;;
        esac
    done < "$config_file"
}
```