# WARP.md

This file provides guidance to WARP (warp.dev) when working with code in this repository.

## Project Overview

BTor is a cross-platform Tor service and browser manager that provides a unified CLI interface for managing Tor services and configuring browser proxies on both Linux and Windows. The project consists of two main platform-specific implementations that share common functionality but are tailored to their respective operating systems.

## Architecture

### Dual Platform Design

The codebase uses a **dual-script architecture** with platform-specific implementations:

- **`btor.sh`** - Linux implementation (Bash script, ~650+ lines)
- **`btor.cmd`** - Windows implementation (Batch script with PowerShell integration)

Both scripts provide the same core functionality through different OS-specific approaches but maintain API compatibility for user commands.

### Core Components

#### 1. **Service Management Layer**
- **Linux**: Uses `systemctl` for service operations (start/stop/restart/enable/disable)
- **Windows**: Uses Windows Service Control Manager (`sc.exe`) with service name `TorWinSvc`
- Both implementations handle service installation, configuration, and lifecycle management

#### 2. **Browser Proxy Management**
- **Firefox-focused approach**: Primary support for Firefox with automatic profile detection
- **Profile Configuration**: Automatically locates and modifies Firefox profiles
- **Configuration Methods**: 
  - `user.js` for new preferences
  - `prefs.js` for existing profile modifications
- **Proxy Settings**: SOCKS5 proxy configuration (127.0.0.1:9050 primary, 9150 fallback)

#### 3. **Installation and Self-Management**
- **Self-installing scripts**: Can install themselves to system paths
- **Auto-update capability**: Downloads latest version from GitHub raw URLs
- **PATH integration**: Ensures `btor` command is globally available
- **First-run setup**: Automatic dependency installation and configuration

#### 4. **Interactive Menu System**
- **Text-based UI**: Classic terminal interface with colored output
- **Menu hierarchy**: Main menu → sub-menus (proxy management, etc.)
- **Cross-platform consistency**: Similar user experience on both platforms

#### 5. **Network Testing and Validation**
- **Route testing**: Validates Tor connectivity via check.torproject.org
- **SOCKS proxy testing**: Tests both primary (9050) and fallback (9150) ports
- **Browser integration**: Opens test pages in configured browsers

## Common Development Commands

### Installation and Setup
```bash
# Linux - First-time installation
bash btor.sh install

# Windows - First-time installation (as Administrator)
BTor.cmd install
```

### Script Execution
```bash
# Linux - Direct script execution
bash btor.sh [command]

# Windows - Direct script execution  
BTor.cmd [command]

# Both platforms - After installation
btor [command]
```

### Service Management Commands
```bash
# Start Tor service
btor start

# Stop Tor service
btor stop

# Restart Tor service
btor restart

# Enable auto-start at boot
btor enable

# Disable auto-start at boot
btor disable

# Check service status
btor status
btor status --full    # Linux only - detailed systemctl status
```

### Development and Maintenance
```bash
# Update to latest version
btor update

# Launch interactive menu
btor

# Uninstall BTor
btor uninstall
```

### Testing and Debugging
```bash
# Test Tor routing
# This opens the main menu where you can select "Tor Route Test"
btor
# Then select option 8

# Browser proxy management
# Opens proxy sub-menu for Firefox configuration
btor
# Then select option 7
```

## Environment Variables and Configuration

### Linux Environment Variables
- `BTOR_SERVICE_NAME` - Override Tor systemd service name (default: `tor.service`)
- `BTOR_HOME` - Installation directory (default: `~/.btor`)
- `BTOR_BIN_LINK` - Global command symlink path (default: `/usr/local/bin/btor`)
- `BTOR_REPO_RAW` - Update source URL (GitHub raw script URL)
- `BTOR_TOR_BROWSER_DIR` - Tor Browser installation path (default: `~/.local/tor-browser`)
- `BTOR_SOCKS_HOST` - SOCKS proxy host (default: `127.0.0.1`)
- `BTOR_SOCKS_PORT` - Primary SOCKS port (default: `9050`)
- `BTOR_SOCKS_PORT_ALT` - Fallback SOCKS port (default: `9150`)

### Windows Configuration
- Service name: `TorWinSvc`
- Install directory: `%ProgramFiles%\BTor`
- Data directory: `%ProgramData%\BTor`
- Tor executable: `%ProgramFiles%\Tor\tor.exe`
- Configuration file: `%ProgramData%\Tor\torrc`

## Key Implementation Patterns

### Error Handling and User Feedback
- **Colored output system**: Uses terminal escape sequences for status indication (green=ok, red=error, yellow=warning)
- **Graceful degradation**: Continues operation even if optional components fail
- **User confirmation prompts**: Interactive confirmations for potentially destructive operations

### Cross-Platform Compatibility Strategies
- **Package manager detection**: Auto-detects and uses appropriate package managers (apt, dnf, yum, pacman, zypper)
- **Browser detection**: Scans multiple common installation paths for Tor Browser and Firefox
- **Service management abstraction**: Platform-specific service management with unified command interface

### Configuration Management
- **Non-destructive updates**: Backs up existing configurations before modifications
- **Profile scanning**: Automatically discovers browser profiles across different installation patterns
- **Environment-based overrides**: Allows customization through environment variables

## Dependencies and Requirements

### Linux Dependencies
- **System**: systemd (for service management), bash, curl
- **Package managers**: One of: apt-get, dnf, yum, pacman, zypper
- **Optional**: torbrowser-launcher, nyx, nodejs/npm (for additional features)
- **Browser**: Firefox (auto-installed if missing)

### Windows Dependencies
- **System**: Windows Service Control Manager, PowerShell 7 (pwsh.exe)
- **Manual setup required**: tor.exe binary must be placed in `%ProgramFiles%\Tor\`
- **Browser**: Firefox (manual installation recommended)

## File Structure
```
BTor/
├── btor.sh          # Linux implementation (main script)
├── btor.cmd         # Windows implementation (main script)
├── README.md        # Project documentation and usage instructions
├── LICENSE          # MIT License
├── BTor.png         # Project logo/icon
└── screenshots/     # UI screenshots for documentation
    ├── ss1.png
    ├── ss2.png
    ├── ss3.png
    ├── ss4.png
    └── ss5.png
```

## Development Notes

### Code Organization Principles
- **Single-file deployment**: Each platform implementation is self-contained in one script
- **Modular function design**: Functions are organized by responsibility (service, proxy, UI, etc.)
- **Configuration centralization**: All configurable values are defined at the top of each script
- **UI consistency**: Both platforms use similar menu structures and command syntax

### Security Considerations
- **Admin/sudo requirements**: Service operations require elevated privileges
- **Local-only proxy**: Default configuration only accepts local connections (127.0.0.1)
- **Configuration validation**: Scripts validate Tor service status before proxy configuration
- **Safe defaults**: Conservative default settings that prioritize security over convenience