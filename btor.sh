#!/usr/bin/env bash
set -euo pipefail

# BTor single-file installer + manager with first-run setup
# File: btor.sh
# Requirements: bash, curl, systemd (systemctl), sudo for service actions.

# -----------------------------
# Config (overridable via env)
# -----------------------------
SERVICE_NAME="${BTOR_SERVICE_NAME:-tor.service}"
BTOR_HOME="${BTOR_HOME:-$HOME/.btor}"
BTOR_BIN_LINK="${BTOR_BIN_LINK:-/usr/local/bin/btor}"
BTOR_RAW_URL_DEFAULT="https://raw.githubusercontent.com/linux-brat/BTor/main/btor.sh"
BTOR_RAW_URL="${BTOR_REPO_RAW:-$BTOR_RAW_URL_DEFAULT}"
BTOR_VERSION="${BTOR_VERSION:-0.2.0}"

# Tor Browser defaults
TOR_BROWSER_DIR_DEFAULT="$HOME/.local/tor-browser"
TOR_BROWSER_DIR="${BTOR_TOR_BROWSER_DIR:-$TOR_BROWSER_DIR_DEFAULT}"

# -----------------------------
# UI helpers
# -----------------------------
bold() { tput bold 2>/dev/null || true; }
reset() { tput sgr0 2>/dev/null || true; }
green() { tput setaf 2 2>/dev/null || true; }
red() { tput setaf 1 2>/dev/null || true; }
yellow() { tput setaf 3 2>/dev/null || true; }
blue() { tput setaf 4 2>/dev/null || true; }

info() { echo "$(blue)$(bold)[i]$(reset) $*"; }
ok() { echo "$(green)$(bold)[ok]$(reset) $*"; }
warn() { echo "$(yellow)$(bold)[warn]$(reset) $*"; }
err() { echo "$(red)$(bold)[err]$(reset) $*"; }

need_sudo() { if [[ $EUID -ne 0 ]]; then sudo -v; fi; }
have_systemctl() { command -v systemctl >/dev/null 2>&1; }
is_stdin_tty() { [[ -t 0 ]]; }
have_dev_tty() { [[ -r /dev/tty ]]; }

# Read from interactive TTY even if stdin is a pipe
tty_read() {
  local prompt="$1"
  if is_stdin_tty; then
    read -rp "$prompt" __choice || true
    echo "${__choice:-}"
    return
  fi
  if have_dev_tty; then
    printf "%s" "$prompt" >&2
    local line=""
    IFS= read -r line < /dev/tty || true
    echo "${line:-}"
    return
  fi
  err "No interactive TTY available. Try: bash btor.sh, or install then run: curl -fsSL ${BTOR_RAW_URL} -o btor.sh && bash btor.sh install && btor"
  exit 1
}

confirm() {
  local prompt="${1:-Proceed? [y/N]: }"
  local ans
  ans="$(tty_read "$prompt")"
  [[ "${ans,,}" == "y" || "${ans,,}" == "yes" ]]
}

press_enter() {
  if is_stdin_tty || have_dev_tty; then
    tty_read "Press Enter to continue..."
  fi
}

# -----------------------------
# OS / Package manager detection
# -----------------------------
pm_detect() {
  if command -v apt-get >/dev/null 2>&1; then echo "apt"; return; fi
  if command -v dnf >/dev/null 2>&1; then echo "dnf"; return; fi
  if command -v yum >/dev/null 2>&1; then echo "yum"; return; fi
  if command -v pacman >/dev/null 2>&1; then echo "pacman"; return; fi
  if command -v zypper >/dev/null 2>&1; then echo "zypper"; return; fi
  echo "unknown"
}

pm_install() {
  local pkgs=("$@")
  local pm; pm="$(pm_detect)"
  need_sudo
  case "$pm" in
    apt)
      sudo apt-get update -y
      sudo apt-get install -y "${pkgs[@]}"
      ;;
    dnf)
      sudo dnf install -y "${pkgs[@]}"
      ;;
    yum)
      sudo yum install -y "${pkgs[@]}"
      ;;
    pacman)
      sudo pacman -Sy --noconfirm "${pkgs[@]}"
      ;;
    zypper)
      sudo zypper install -y "${pkgs[@]}"
      ;;
    *)
      err "Unsupported package manager. Please install: ${pkgs[*]}"
      return 1
      ;;
  esac
}

# -----------------------------
# Tor CLI / service checks
# -----------------------------
tor_cli_installed() { command -v tor >/dev/null 2>&1; }
tor_service_exists() { systemctl list-unit-files | grep -q "^${SERVICE_NAME}\b" || systemctl status "${SERVICE_NAME}" >/dev/null 2>&1; }

install_or_update_tor() {
  info "Checking Tor installation..."
  if tor_cli_installed; then
    ok "Tor CLI found: $(command -v tor)"
  else
    warn "Tor CLI not found."
  fi

  if tor_service_exists; then
    ok "Tor service unit found: ${SERVICE_NAME}"
  else
    warn "Tor systemd unit ${SERVICE_NAME} not found."
  fi

  if tor_cli_installed && tor_service_exists; then
    # Try to update Tor via package manager
    if confirm "Tor seems installed. Check for updates via package manager? [y/N]: "; then
      case "$(pm_detect)" in
        apt) need_sudo; sudo apt-get update -y && sudo apt-get install -y tor ;;
        dnf) pm_install tor ;;
        yum) pm_install tor ;;
        pacman) pm_install tor ;;
        zypper) pm_install tor ;;
        *) warn "Unknown package manager. Skipping Tor update." ;;
      esac
    fi
    return 0
  fi

  # Offer install
  if confirm "Tor is missing or incomplete. Install Tor now? [y/N]: "; then
    case "$(pm_detect)" in
      apt) pm_install tor ;;
      dnf|yum) pm_install tor ;;
      pacman) pm_install tor ;;
      zypper) pm_install tor ;;
      *)
        err "Unsupported package manager. Please install Tor manually."
        return 1
        ;;
    esac
    ok "Tor installed."
  else
    warn "Skipping Tor installation."
    return 1
  fi
}

# -----------------------------
# Tor Browser checks
# -----------------------------
tor_browser_bin() {
  # Typical Tor Browser launcher inside extracted dir; try to find it.
  # Official tarball structure: tor-browser/Browser/start-tor-browser
  if [[ -x "${TOR_BROWSER_DIR}/tor-browser/Browser/start-tor-browser" ]]; then
    echo "${TOR_BROWSER_DIR}/tor-browser/Browser/start-tor-browser"
    return
  fi
  # Alternative location if user extracted elsewhere under the dir
  local cand
  cand="$(find "${TOR_BROWSER_DIR}" -type f -name start-tor-browser -perm -111 2>/dev/null | head -n1 || true)"
  if [[ -n "$cand" ]]; then
    echo "$cand"
    return
  fi
  echo ""
}

tor_browser_installed() {
  [[ -n "$(tor_browser_bin)" ]]
}

download_tor_browser() {
  # Try to choose an x86_64 English build by default.
  # Users can change later; we keep it simple and robust.
  local url="https://www.torproject.org/dist/torbrowser/13.5.2/tor-browser-linux64-13.5.2_ALL.tar.xz"
  # If that version becomes unavailable later, users can replace URL via BTOR_TB_URL env.
  url="${BTOR_TB_URL:-$url}"

  mkdir -p "${TOR_BROWSER_DIR}"
  info "Downloading Tor Browser to ${TOR_BROWSER_DIR}..."
  curl -fL --progress-bar "$url" -o "${TOR_BROWSER_DIR}/tor-browser.tar.xz"
  info "Extracting..."
  tar -xf "${TOR_BROWSER_DIR}/tor-browser.tar.xz" -C "${TOR_BROWSER_DIR}"
  rm -f "${TOR_BROWSER_DIR}/tor-browser.tar.xz"
  ok "Tor Browser downloaded."
}

install_or_update_tor_browser() {
  info "Checking Tor Browser..."
  local bin
  bin="$(tor_browser_bin)"
  if [[ -n "$bin" ]]; then
    ok "Tor Browser found: $bin"
    # We don't attempt auto-updater; Tor Browser has its own internal updater.
    if confirm "Launch Tor Browser updater (open GUI) now? [y/N]: "; then
      nohup "$bin" >/dev/null 2>&1 &
      info "Launched Tor Browser. Use its internal updater. Return to BTor when done."
    fi
    return 0
  fi

  warn "Tor Browser not found under ${TOR_BROWSER_DIR}."
  if confirm "Download Tor Browser now? [y/N]: "; then
    download_tor_browser
    bin="$(tor_browser_bin || true)"
    if [[ -n "$bin" ]]; then
      ok "Tor Browser ready: $bin"
    else
      warn "Tor Browser install could not be validated; please check ${TOR_BROWSER_DIR}."
    fi
  else
    warn "Skipping Tor Browser."
    return 1
  fi
}

# -----------------------------
# Node.js/npm/npx checks
# -----------------------------
npx_installed() { command -v npx >/dev/null 2>&1; }
npm_installed() { command -v npm >/dev/null 2>&1; }
node_installed() { command -v node >/dev/null 2>&1; }

install_or_update_node_stack() {
  info "Checking Node.js/npm/npx..."
  if node_installed && npm_installed && npx_installed; then
    ok "Node/npm/npx are installed."
    if confirm "Check for Node/npm updates via package manager? [y/N]: "; then
      case "$(pm_detect)" in
        apt) need_sudo; sudo apt-get update -y && sudo apt-get install -y nodejs npm ;;
        dnf|yum) pm_install nodejs npm ;;
        pacman) pm_install nodejs npm ;;
        zypper) pm_install nodejs npm ;;
        *) warn "Unsupported package manager. Skipping Node update." ;;
      esac
    fi
    return 0
  fi

  warn "Node/npm/npx not fully available."
  if confirm "Install Node.js and npm now? [y/N]: "; then
    case "$(pm_detect)" in
      apt) pm_install nodejs npm ;;
      dnf|yum) pm_install nodejs npm ;;
      pacman) pm_install nodejs npm ;;
      zypper) pm_install nodejs npm ;;
      *)
        err "Unsupported package manager. Please install Node.js/npm manually."
        return 1
        ;;
    esac
    if ! npx_installed && npm_installed; then
      ok "npx will be available via npm (same package)."
    fi
  else
    warn "Skipping Node.js/npm installation."
    return 1
  fi
}

# -----------------------------
# First-run gate
# -----------------------------
first_run_marker() { echo "${BTOR_HOME}/.first_run_done"; }
first_run_needed() { [[ ! -f "$(first_run_marker)" ]]; }

run_first_time_setup() {
  info "First-time setup starting..."
  mkdir -p "${BTOR_HOME}"

  # 1) Tor
  install_or_update_tor || true

  # 2) Tor Browser
  install_or_update_tor_browser || true

  # 3) Node/npm/npx
  install_or_update_node_stack || true

  touch "$(first_run_marker)"
  ok "First-time setup complete."
}

# -----------------------------
# Install / Uninstall / Update
# -----------------------------
install_self() {
  info "Installing BTor to ${BTOR_HOME}..."
  mkdir -p "${BTOR_HOME}"

  if [[ -n "${BASH_SOURCE[0]:-}" && -f "${BASH_SOURCE}" ]]; then
    cp "${BASH_SOURCE}" "${BTOR_HOME}/btor"
  else
    curl -fsSL "${BTOR_RAW_URL}" -o "${BTOR_HOME}/btor"
  fi

  chmod +x "${BTOR_HOME}/btor"

  info "Linking ${BTOR_BIN_LINK} (requires sudo)..."
  need_sudo
  sudo ln -sf "${BTOR_HOME}/btor" "${BTOR_BIN_LINK}"

  ok "Installed. Launch with: btor"
}

uninstall_self() {
  warn "Uninstalling BTor..."
  need_sudo
  sudo rm -f "${BTOR_BIN_LINK}" || true
  rm -rf "${BTOR_HOME}" || true
  ok "BTor uninstalled."
}

self_update() {
  info "Updating from ${BTOR_RAW_URL}..."
  mkdir -p "${BTOR_HOME}"
  curl -fsSL "${BTOR_RAW_URL}" -o "${BTOR_HOME}/btor.new"
  chmod +x "${BTOR_HOME}/btor.new"
  mv "${BTOR_HOME}/btor.new" "${BTOR_HOME}/btor"
  ok "BTor updated."
}

# -----------------------------
# Tor service operations
# -----------------------------
start_service()   { need_sudo; sudo systemctl start   "${SERVICE_NAME}"; ok "Started ${SERVICE_NAME}."; }
stop_service()    { need_sudo; sudo systemctl stop    "${SERVICE_NAME}"; ok "Stopped ${SERVICE_NAME}."; }
restart_service() { need_sudo; sudo systemctl restart "${SERVICE_NAME}"; ok "Restarted ${SERVICE_NAME}."; }
enable_service()  { need_sudo; sudo systemctl enable  "${SERVICE_NAME}"; ok "Enabled ${SERVICE_NAME} at boot."; }
disable_service() { need_sudo; sudo systemctl disable "${SERVICE_NAME}"; ok "Disabled ${SERVICE_NAME} at boot."; }

show_status() {
  local mode="${1:-concise}"
  if ! have_systemctl; then
    err "systemctl not found; BTor requires systemd."
    return 1
  fi
  local is_active is_enabled
  is_active="$(systemctl is-active "${SERVICE_NAME}" 2>/dev/null || true)"
  is_enabled="$(systemctl is-enabled "${SERVICE_NAME}" 2>/dev/null || true)"

  local a e
  if [[ "${is_active}" == "active" ]]; then a="$(green)active$(reset)"; else a="$(red)${is_active:-unknown}$(reset)"; fi
  if [[ "${is_enabled}" == "enabled" ]]; then e="$(green)enabled$(reset)"; else e="$(yellow)${is_enabled:-unknown}$(reset)"; fi

  echo "$(bold)BTor – Tor service manager$(reset)  v${BTOR_VERSION}"
  echo "Service: $(bold)${SERVICE_NAME}$(reset)"
  echo "Status: ${a}  |  Boot: ${e}"

  if [[ "${mode}" == "full" ]]; then
    echo
    systemctl --no-pager status "${SERVICE_NAME}" || true
  fi
}

# -----------------------------
# Menu
# -----------------------------
menu_once() {
  clear 2>/dev/null || true
  show_status concise
  echo
  echo "$(bold)Options:$(reset)"
  echo "1) Start tor.service"
  echo "2) Stop tor.service"
  echo "3) Enable at boot"
  echo "4) Disable at boot"
  echo "5) Restart tor.service"
  echo "6) Show full status"
  echo "7) Update BTor"
  echo "8) Uninstall BTor"
  echo "9) Quit"
  echo
  local choice
  choice="$(tty_read "Select an option [1-9]: ")"
  echo

  case "${choice}" in
    1) start_service ;;
    2) stop_service ;;
    3) enable_service ;;
    4) disable_service ;;
    5) restart_service ;;
    6) show_status full ;;
    7) self_update ;;
    8) uninstall_self; return 1 ;;
    9) return 1 ;;
    *) err "Invalid option." ;;
  esac
  return 0
}

menu_loop() {
  while true; do
    if ! menu_once; then
      break
    fi
    echo
    press_enter
  done
}

# -----------------------------
# Usage / CLI
# -----------------------------
usage() {
  cat <<EOF
BTor – Single-file Tor service manager and installer

Usage:
  bash btor.sh install           Install to ${BTOR_HOME} and link ${BTOR_BIN_LINK}
  bash btor.sh uninstall         Remove installation
  bash btor.sh update            Update from ${BTOR_RAW_URL}
  bash btor.sh                   Launch interactive menu

  btor                           Launch interactive menu (after install)
  btor start|stop|restart|enable|disable|status [--full]
  btor update                    Update installed copy
  btor uninstall                 Uninstall BTor

Env:
  BTOR_SERVICE_NAME              Override service name (default: tor.service)
  BTOR_HOME                      Install dir (default: \$HOME/.btor)
  BTOR_BIN_LINK                  Symlink path (default: /usr/local/bin/btor)
  BTOR_REPO_RAW                  URL to fetch btor.sh for update/install
  BTOR_TOR_BROWSER_DIR           Tor Browser install/check directory (default: \$HOME/.local/tor-browser)
  BTOR_TB_URL                    Override Tor Browser tarball URL (advanced)
EOF
}

cli() {
  # If run via a pipe with no args:
  # - Prefer installing, then exec 'btor' to inherit a real TTY session if available.
  # - If /dev/tty isn't accessible, still run the menu using tty_read fallback.
  if [[ -z "${1:-}" ]] && ! is_stdin_tty; then
    if have_dev_tty; then
      install_self
      exec btor
    else
      warn "No /dev/tty detected; running menu without installing."
      # On first run in such env, still attempt setup best-effort:
      if first_run_needed; then run_first_time_setup || true; fi
      menu_loop
      exit 0
    fi
  fi

  local cmd="${1:-}"
  case "${cmd}" in
    install)   install_self ;;
    uninstall) uninstall_self ;;
    update)    self_update ;;
    start)     start_service ;;
    stop)      stop_service ;;
    restart)   restart_service ;;
    enable)    enable_service ;;
    disable)   disable_service ;;
    status)
      if [[ "${2:-}" == "--full" ]]; then show_status full; else show_status concise; fi
      ;;
    -h|--help|help) usage ;;
    "")
      if first_run_needed; then run_first_time_setup || true; fi
      menu_loop
      ;;
    *)
      err "Unknown command: ${cmd}"
      usage
      exit 1
      ;;
  esac
}

cli "$@"
