# Contributing to Useful Bash Scripts

Thank you for considering contributing to this project! We welcome contributions of all kinds.

## Table of Contents

- [Getting Started](#getting-started)
- [How to Contribute](#how-to-contribute)
- [Script Guidelines](#script-guidelines)
- [Testing](#testing)
- [Documentation](#documentation)
- [Pull Request Process](#pull-request-process)

## Getting Started

1. Fork the repository
2. Clone your fork locally
3. Create a new branch for your contribution
4. Make your changes
5. Test your changes thoroughly
6. Submit a pull request

## How to Contribute

### Adding New Scripts

1. **Choose the right OS directory**: First select the appropriate operating system directory:
   - `scripts/debian-ubuntu/` - Debian/Ubuntu specific (apt, systemd)
   - `scripts/rhel-centos/` - RHEL/CentOS/Rocky/Alma (yum/dnf, systemd)
   - `scripts/fedora/` - Fedora specific (dnf, systemd)
   - `scripts/arch/` - Arch Linux specific (pacman, systemd)
   - `scripts/opensuse/` - openSUSE specific (zypper, systemd)
   - `scripts/alpine/` - Alpine Linux specific (apk, openrc)
   - `scripts/universal/` - Cross-platform compatible scripts

2. **Choose the functional subdirectory**: Within the OS directory, select:
   - `system/` - System administration tasks
   - `development/` - Development and build tools
   - `network/` - Network utilities
   - `backup/` - Backup and recovery tools
   - `monitoring/` - System monitoring scripts
   - `utilities/` - General purpose utilities

3. **Use the template**: Start with `templates/script-template.sh` and customize it
4. **Follow naming conventions**: Use kebab-case (e.g., `system-info.sh`, `backup-mysql.sh`)
5. **Include OS detection**: Add appropriate OS/distribution checks if needed
6. **Make it executable**: `chmod +x your-script.sh`

### Improving Existing Scripts

- Bug fixes are always welcome
- Performance improvements
- Better error handling
- Enhanced documentation
- OS-specific optimizations
- Adding support for additional distributions within OS families

## Script Guidelines

### Code Quality

- Follow the coding standards in [CODING_STANDARDS.md](CODING_STANDARDS.md)
- Use `set -euo pipefail` for error handling
- Include proper input validation
- Handle edge cases gracefully
- Use meaningful variable names
- Add appropriate comments

### Documentation

Each script must include:

- **Header comment block** with:
  - Script name and brief description
  - Author information
  - Creation and modification dates
  - Usage examples
  - Requirements and dependencies
  - **OS/Distribution compatibility information**
  - **Package manager requirements** (apt, yum, dnf, pacman, etc.)

- **Help functionality**: Support `--help` flag with detailed usage information
- **Version information**: Support `--version` flag

### Error Handling

- Always check command return codes
- Provide meaningful error messages
- Use proper exit codes
- Implement cleanup functions where necessary
- Handle signals appropriately

## Testing

### Manual Testing

- Test on the target OS/distribution when possible
- Test with different user permissions (user vs root)
- Test edge cases and error conditions
- Verify that help and version flags work correctly
- Test with different package manager versions
- Verify OS detection works correctly if implemented

### Test Checklist

- [ ] Script runs without syntax errors
- [ ] All command line options work as expected
- [ ] Error cases are handled gracefully
- [ ] Help documentation is accurate and complete
- [ ] Script doesn't leave temporary files or processes
- [ ] **Works on target OS/distribution**
- [ ] **Package manager commands work correctly**
- [ ] **OS-specific paths and commands are valid**

## Documentation

### README Updates

When adding new scripts, update the main README.md:

1. Add script to the appropriate **OS and functional category** section
2. Include a brief description
3. Note any special requirements and **OS-specific dependencies**
4. Add usage example if helpful
5. **Specify which distributions are supported**

### Script Documentation

- Use clear, concise comments
- Document complex logic
- Explain any system-specific commands
- Note compatibility limitations
- Include usage examples in comments

## Pull Request Process

1. **Create a descriptive branch name**: `feature/new-backup-script` or `fix/system-info-bug`

2. **Write a clear commit message**:
   - Use the imperative mood ("Add feature" not "Added feature")
   - Keep the first line under 50 characters
   - Include more details in the body if needed

3. **Test thoroughly** before submitting

4. **Update documentation** as needed

5. **Submit the pull request** with:
   - Clear description of changes
   - Reference to any related issues
   - Testing information
   - Screenshots if applicable

### Pull Request Checklist

- [ ] Code follows project coding standards
- [ ] Script includes proper documentation
- [ ] All tests pass
- [ ] README.md updated if needed
- [ ] No unnecessary files included
- [ ] Commit messages are clear and descriptive

## Code Review Process

All contributions will be reviewed for:

- Code quality and adherence to standards
- Security implications
- Cross-platform compatibility
- Documentation completeness
- Testing adequacy

## Questions?

If you have questions about contributing:

1. Check existing issues and discussions
2. Review the documentation in the `docs/` directory
3. Open an issue with your question

## License

By contributing, you agree that your contributions will be licensed under the same MIT License that covers the project.