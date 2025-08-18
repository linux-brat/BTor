#!/usr/bin/env bash
set -euo pipefail

# BTor single-file installer + manager
# File: btor.sh
# Purpose: Provide a single sh file that can be curl-installed and also acts as the runtime manager.
# Requirements: bash, curl, systemd (systemctl), sudo for service actions.

# -----------------------------
# Config (can be overridden via env)
# -----------------------------
SERVICE_NAME="${BTOR_SERVICE_NAME:-tor.service}"
BTOR_HOME="${BTOR_HOME:-$HOME/.btor}"
BTOR_BIN_LINK="${BTOR_BIN_LINK:-/usr/local/bin/btor}"
# Point this to the raw location of this same file in your GitHub repo:
BTOR_RAW_URL_DEFAULT="https://raw.githubusercontent.com/linux-brat/BTor/main/btor.sh"
BTOR_RAW_URL="${BTOR_REPO_RAW:-$BTOR_RAW_URL_DEFAULT}"
BTOR_VERSION="${BTOR_VERSION:-0.1.1}"

# -----------------------------
# Helpers
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

need_sudo() {
  if [[ $EUID -ne 0 ]]; then
    sudo -v
  fi
}

have_systemctl() {
  command -v systemctl >/dev/null 2>&1
}

is_tty() { [[ -t 0 ]]; }

tty_read() {
  # Usage: choice="$(tty_read "Prompt: ")"
  if is_tty; then
    read -rp "$1" choice
  else
    if exec 3</dev/tty 2>/dev/null; then
      printf "%s" "$1" >&2
      IFS= read -r choice <&3 || true
      exec 3<&-
    else
      err "No TTY available for interactive menu."
      exit 1
    fi
  fi
  echo "${choice:-}"
}

# -----------------------------
# Install / Uninstall / Update
# -----------------------------
install_self() {
  info "Installing BTor to ${BTOR_HOME}..."
  mkdir -p "${BTOR_HOME}"

  # If the script is being executed from a file, copy that file; else fetch from URL
  if [[ -n "${BASH_SOURCE[0]:-}" && -f "${BASH_SOURCE}" ]]; then
    cp "${BASH_SOURCE}" "${BTOR_HOME}/btor"
  else
    curl -fsSL "${BTOR_RAW_URL}" -o "${BTOR_HOME}/btor"
  fi

  chmod +x "${BTOR_HOME}/btor"

  info "Linking command to ${BTOR_BIN_LINK} (requires sudo)..."
  need_sudo
  sudo ln -sf "${BTOR_HOME}/btor" "${BTOR_BIN_LINK}"

  ok "Installed. Use: btor"
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
start_service() { need_sudo; sudo systemctl start "${SERVICE_NAME}"; ok "Started ${SERVICE_NAME}."; }
stop_service() { need_sudo; sudo systemctl stop "${SERVICE_NAME}"; ok "Stopped ${SERVICE_NAME}."; }
restart_service(){ need_sudo; sudo systemctl restart "${SERVICE_NAME}"; ok "Restarted ${SERVICE_NAME}."; }
enable_service() { need_sudo; sudo systemctl enable "${SERVICE_NAME}"; ok "Enabled ${SERVICE_NAME} at boot."; }
disable_service(){ need_sudo; sudo systemctl disable "${SERVICE_NAME}"; ok "Disabled ${SERVICE_NAME} at boot."; }

show_status() {
  local mode="${1:-concise}"
  if ! have_systemctl; then
    err "systemctl not found; systemd is required."
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
# Menu and CLI
# -----------------------------
menu() {
  clear || true
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
    8) uninstall_self ;;
    9) exit 0 ;;
    *) err "Invalid option." ;;
  esac
}

usage() {
  cat <<EOF
BTor – Single-file Tor service manager and installer

Usage:
  bash btor.sh install           Install to ${BTOR_HOME} and link ${BTOR_BIN_LINK}
  bash btor.sh uninstall         Remove installation
  bash btor.sh update            Update from ${BTOR_RAW_URL}
  bash btor.sh                   Launch interactive menu (if installed or running locally)

  btor                           Launch interactive menu (after install)
  btor start|stop|restart|enable|disable|status [--full]
  btor update                    Update installed copy
  btor uninstall                 Uninstall BTor

Env:
  BTOR_SERVICE_NAME              Override service name (default: tor.service)
  BTOR_HOME                      Install dir (default: \$HOME/.btor)
  BTOR_BIN_LINK                  Symlink path (default: /usr/local/bin/btor)
  BTOR_REPO_RAW                  URL to fetch btor.sh for update/install
EOF
}

cli() {
  # If run via a pipe with no args, install then launch the installed command to ensure TTY
  if [[ -z "${1:-}" ]] && ! is_tty; then
    install_self
    exec btor
  fi

  local cmd="${1:-}"
  case "${cmd}" in
    install) install_self ;;
    uninstall) uninstall_self ;;
    update) self_update ;;
    start) start_service ;;
    stop) stop_service ;;
    restart) restart_service ;;
    enable) enable_service ;;
    disable) disable_service ;;
    status)
      if [[ "${2:-}" == "--full" ]]; then show_status full; else show_status concise; fi
      ;;
    -h|--help|help) usage ;;
    "")
      menu
      ;;
    *)
      err "Unknown command: ${cmd}"
      usage
      exit 1
      ;;
  esac
}

cli "${@}"
