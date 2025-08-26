# Useful Bash Scripts

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Shell Scripts](https://img.shields.io/badge/Shell-Bash-green.svg)](https://www.gnu.org/software/bash/)
[![GitHub last commit](https://img.shields.io/github/last-commit/ZacharyArthur/usefulBashScripts)](https://github.com/ZacharyArthur/usefulBashScripts/commits/main)
[![GitHub issues](https://img.shields.io/github/issues/ZacharyArthur/usefulBashScripts)](https://github.com/ZacharyArthur/usefulBashScripts/issues)
[![GitHub stars](https://img.shields.io/github/stars/ZacharyArthur/usefulBashScripts?style=social)](https://github.com/ZacharyArthur/usefulBashScripts/stargazers)

A curated collection of bash scripts for system administration, development, and general utilities organized by operating system and distribution.

## Overview

This repository contains a variety of bash scripts organized by operating system to handle distribution-specific differences in package management, service management, and system configuration.

## Directory Structure

```
scripts/
├── debian-ubuntu/       # Debian/Ubuntu specific scripts (apt, systemd)
│   ├── system/          # System administration scripts
│   ├── development/     # Development and build scripts
│   ├── network/         # Network utilities and tools
│   ├── backup/          # Backup and recovery scripts
│   ├── monitoring/      # System monitoring scripts
│   └── utilities/       # General utility scripts
├── rhel-centos/         # RHEL/CentOS/Rocky/Alma scripts (yum/dnf, systemd)
│   └── [same subdirs]
├── fedora/              # Fedora specific scripts (dnf, systemd)
│   └── [same subdirs]
├── arch/                # Arch Linux specific scripts (pacman, systemd)
│   └── [same subdirs]
├── opensuse/            # openSUSE specific scripts (zypper, systemd)
│   └── [same subdirs]
├── alpine/              # Alpine Linux specific scripts (apk, openrc)
│   └── [same subdirs]
└── universal/           # Cross-platform compatible scripts
    └── [same subdirs]
```

## Installation

1. Clone the repository:
   ```bash
   git clone https://github.com/ZacharyArthur/usefulBashScripts.git
   cd usefulBashScripts
   ```

2. Make scripts executable:
   ```bash
   find scripts/ -name "*.sh" -exec chmod +x {} \;
   ```

3. Optionally, add the scripts directory to your PATH:
   ```bash
   export PATH="$PATH:$(pwd)/scripts"
   ```

## Usage

Each script includes usage documentation in its header. Run any script with the `-h` or `--help` flag for detailed usage information:

```bash
./scripts/debian-ubuntu/system/example-script.sh --help
```

## Supported Operating Systems

- **Debian/Ubuntu**: Scripts optimized for apt package manager and systemd
- **RHEL/CentOS**: Scripts for yum/dnf package manager and systemd  
- **Fedora**: Scripts optimized for dnf package manager and systemd
- **Arch Linux**: Scripts for pacman package manager and systemd
- **openSUSE**: Scripts for zypper package manager and systemd
- **Alpine Linux**: Scripts for apk package manager and OpenRC
- **Universal**: Cross-platform scripts that work across distributions

## Requirements

Most scripts require:
- Bash 4.0 or higher
- Standard Unix utilities (grep, awk, sed, etc.)
- Specific requirements are documented in individual script headers

## Contributing

We welcome contributions! Please see [CONTRIBUTING.md](docs/CONTRIBUTING.md) for guidelines on:
- Adding new scripts
- Coding standards
- Testing procedures
- Documentation requirements

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## Scripts Overview

<!-- This section will be populated as scripts are added -->

### Debian/Ubuntu Scripts
- **System**: 
  - `system-update.sh` - Comprehensive system updater for APT, Snap, Flatpak, and optional firmware
- **Development**: Coming soon...
- **Network**: Coming soon...
- **Backup**: Coming soon...
- **Monitoring**: Coming soon...
- **Utilities**: Coming soon...

### RHEL/CentOS Scripts
- **System**: Coming soon...
- **Development**: Coming soon...
- **Network**: Coming soon...
- **Backup**: Coming soon...
- **Monitoring**: Coming soon...
- **Utilities**: Coming soon...

### Universal Scripts
- **System**: Coming soon...
- **Development**: Coming soon...
- **Network**: Coming soon...
- **Backup**: Coming soon...
- **Monitoring**: Coming soon...
- **Utilities**: Coming soon...

### Other Distributions
- **Fedora**: Coming soon...
- **Arch Linux**: Coming soon...
- **openSUSE**: Coming soon...
- **Alpine Linux**: Coming soon...

## Support

If you encounter issues or have questions:
1. Check the script's built-in help: `script-name.sh --help`
2. Review the documentation in the `docs/` directory
3. Open an issue on GitHub with detailed information about your system and the problem