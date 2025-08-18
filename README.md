# BTor — Simple Tor service manager (single-file)

BTor is a single-file Bash tool to manage Tor via systemd with a simple numbered menu. It supports install via one-line curl, creates a system-wide btor command, can self-update from GitHub, and uninstall cleanly.

BTor features:
- Start, Stop, Restart Tor
- Enable/Disable Tor at boot
- Show concise/full status
- Self-update
- Uninstall
- Works both interactively (menu) and via CLI arguments

BTor requirements:
- systemd (systemctl)
- bash, curl
- sudo privileges for service and symlink actions
- Tor installed as tor.service (override supported)

## Quick install

Recommended one-liner (downloads to /tmp, makes executable, installs, and creates btor command):

- curl -fsSL https://raw.githubusercontent.com/linux-brat/BTor/main/btor.sh -o /tmp/btor.sh && chmod +x /tmp/btor.sh && /tmp/btor.sh install

After install, launch the menu:

- btor

## Usage

Interactive menu:

- btor

Command-line (non-interactive):

- btor status            Show concise status
- btor status --full     Show full systemctl status
- btor start             Start Tor
- btor stop              Stop Tor
- btor restart           Restart Tor
- btor enable            Enable Tor at boot
- btor disable           Disable Tor at boot
- btor update            Self-update from repo
- btor uninstall         Remove BTor

Run without installing (ad-hoc):

- curl -fsSL https://raw.githubusercontent.com/linux-brat/BTor/main/btor.sh | bash

Note: When piped via curl, the script will install itself and then launch the menu where possible, or fallback to reading from /dev/tty so the menu remains interactive.

## Service name override

Some distros use tor@default.service instead of tor.service. Override with an environment variable:

- BTOR_SERVICE_NAME=tor@default.service btor

To make this permanent, add to shell profile:

- echo 'export BTOR_SERVICE_NAME=tor@default.service' >> ~/.bashrc

## Update BTor

- btor update

or re-run the install one-liner:

- curl -fsSL https://raw.githubusercontent.com/linux-brat/BTor/main/btor.sh -o /tmp/btor.sh && chmod +x /tmp/btor.sh && /tmp/btor.sh install

## Uninstall

- btor uninstall

This removes the /usr/local/bin/btor symlink and the install directory (~/.btor).

## Troubleshooting

- 404 when fetching: Use the raw URL format without “blob”. The correct path is:
  - https://raw.githubusercontent.com/linux-brat/BTor/main/btor.sh

- Menu exits immediately when piped via curl: BTor reads input from /dev/tty to stay interactive even when stdin is a pipe. If running in an environment without /dev/tty (some containers/CI), install and run directly:
  - curl -fsSL https://raw.githubusercontent.com/linux-brat/BTor/main/btor.sh -o /tmp/btor.sh && chmod +x /tmp/btor.sh && /tmp/btor.sh install && btor

- Permission errors: Service actions and creating /usr/local/bin symlink require sudo.

- systemd not found: BTor requires systemctl; it won’t work on non-systemd systems.

- noexec on $HOME: If the home partition is mounted with noexec, override install path:
  - BTOR_HOME=/usr/local/lib/btor /tmp/btor.sh install

- Windows line endings: If edited on Windows, convert:
  - sed -i 's/\r$//' ~/.btor/btor

## Security notes

- Review the script before piping into bash.
- BTor uses sudo for systemctl actions and to place the btor symlink into /usr/local/bin.

## Project structure

This project is intentionally single-file. The script installs itself to:
- ~/.btor/btor (default install dir)
- /usr/local/bin/btor (symlink for global command)

Environment variables:
- BTOR_SERVICE_NAME: Override service unit name (default: tor.service)
- BTOR_HOME: Install location (default: $HOME/.btor)
- BTOR_BIN_LINK: Symlink location (default: /usr/local/bin/btor)
- BTOR_REPO_RAW: Override update URL (default points to repo raw btor.sh)

## License

MIT (or your preferred license). Add a LICENSE file if needed.

[1] https://raw.githubusercontent.com/linux-brat/BTor/main/btor.sh