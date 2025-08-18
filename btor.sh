#!/usr/bin/env bash
set -euo pipefail

# BTor - Simple Tor service manager
# Requires: bash, systemd (systemctl), curl
# Optional: jq (for nicer update checks; not required)
# Service name can be overridden via BTOR_SERVICE_NAME env var
SERVICE_NAME="${BTOR_SERVICE_NAME:-tor.service}"
BTOR_HOME="${BTOR_HOME:-$HOME/.btor}"
BTOR_BIN_LINK="/usr/local/bin/btor"
REPO_REMOTE="${BTOR_REPO:-https://raw.githubusercontent.com/youruser/btor/main}"
VERSION_FILE_LOCAL="${BTOR_HOME}/VERSION"
VERSION_FILE_REMOTE="${REPO_REMOTE}/VERSION"
SELF_PATH="$(readlink -f "${BASH_SOURCE[0]}")"

# Colors (fail gracefully if tput not available)
if command -v tput >/dev/null 2>&1; then
  BOLD="$(tput bold)"; RESET="$(tput sgr0)"; GREEN="$(tput setaf 2)"; RED="$(tput setaf 1)"; YELLOW="$(tput setaf 3)"; BLUE="$(tput setaf 4)"
else
  BOLD=""; RESET=""; GREEN=""; RED=""; YELLOW=""; BLUE=""
fi

need_sudo() {
  if [[ $EUID -ne 0 ]]; then
    echo "This action requires sudo."
    sudo -v
  fi
}

print_header() {
  echo "${BOLD}BTor – Tor service manager${RESET}"
  echo "Service: ${BOLD}${SERVICE_NAME}${RESET}"
  echo
  show_status concise || true
  echo
}

show_status() {
  local mode="${1:-full}"
  if ! command -v systemctl >/dev/null 2>&1; then
    echo "${RED}systemctl not found. This tool requires systemd.${RESET}"
    return 1
  fi
  if ! systemctl list-unit-files | grep -q "^tor\\.service\\b" && ! systemctl status "${SERVICE_NAME}" >/dev/null 2>&1; then
    echo "${YELLOW}Warning: ${SERVICE_NAME} not found. Install Tor or adjust BTOR_SERVICE_NAME.${RESET}"
  fi

  local is_active is_enabled
  is_active="$(systemctl is-active "${SERVICE_NAME}" 2>/dev/null || true)"
  is_enabled="$(systemctl is-enabled "${SERVICE_NAME}" 2>/dev/null || true)"

  local active_txt enabled_txt
  if [[ "${is_active}" == "active" ]]; then active_txt="${GREEN}active${RESET}"; else active_txt="${RED}${is_active:-unknown}${RESET}"; fi
  if [[ "${is_enabled}" == "enabled" ]]; then enabled_txt="${GREEN}enabled${RESET}"; else enabled_txt="${YELLOW}${is_enabled:-unknown}${RESET}"; fi

  echo "Status: ${active_txt}  |  Boot: ${enabled_txt}"

  if [[ "${mode}" != "concise" ]]; then
    echo
    systemctl --no-pager status "${SERVICE_NAME}" || true
  fi
}

start_service() { need_sudo; sudo systemctl start "${SERVICE_NAME}"; echo "${GREEN}Started ${SERVICE_NAME}.${RESET}"; }
stop_service() { need_sudo; sudo systemctl stop "${SERVICE_NAME}"; echo "${GREEN}Stopped ${SERVICE_NAME}.${RESET}"; }
restart_service(){ need_sudo; sudo systemctl restart "${SERVICE_NAME}"; echo "${GREEN}Restarted ${SERVICE_NAME}.${RESET}"; }
enable_service() { need_sudo; sudo systemctl enable "${SERVICE_NAME}"; echo "${GREEN}Enabled ${SERVICE_NAME} at boot.${RESET}"; }
disable_service(){ need_sudo; sudo systemctl disable "${SERVICE_NAME}"; echo "${GREEN}Disabled ${SERVICE_NAME} at boot.${RESET}"; }

self_update() {
  echo "Checking for updates..."
  local local_v remote_v
  if [[ -f "${VERSION_FILE_LOCAL}" ]]; then
    local_v="$(cat "${VERSION_FILE_LOCAL}" | tr -d ' \t\r\n')"
  else
    local_v="0.0.0"
  fi
  remote_v="$(curl -fsSL "${VERSION_FILE_REMOTE}" | tr -d ' \t\r\n' || true)"

  if [[ -z "${remote_v}" ]]; then
    echo "${YELLOW}Unable to fetch remote version. Skipping update.${RESET}"
    return 0
  fi

  if [[ "${remote_v}" == "${local_v}" ]]; then
    echo "Already up to date (version ${local_v})."
    return 0
  fi

  echo "Updating BTor from ${local_v} to ${remote_v}..."
  mkdir -p "${BTOR_HOME}"
  curl -fsSL "${REPO_REMOTE}/btor" -o "${BTOR_HOME}/btor.new"
  chmod +x "${BTOR_HOME}/btor.new"
  mv "${BTOR_HOME}/btor.new" "${BTOR_HOME}/btor"
  curl -fsSL "${VERSION_FILE_REMOTE}" -o "${VERSION_FILE_LOCAL}"
  if [[ -w "${SELF_PATH}" ]]; then
    # Running directly from BTOR_HOME
    :
  else
    # If running from symlink in /usr/local/bin, nothing else to do
    :
  fi
  echo "${GREEN}BTor updated to version ${remote_v}.${RESET}"
}

uninstall_btor() {
  echo "${YELLOW}Uninstalling BTor...${RESET}"
  need_sudo
  sudo rm -f "${BTOR_BIN_LINK}" || true
  rm -rf "${BTOR_HOME}" || true
  echo "${GREEN}BTor uninstalled.${RESET}"
}

menu() {
  print_header
  echo "${BOLD}Options:${RESET}"
  echo "1) Start tor.service"
  echo "2) Stop tor.service"
  echo "3) Enable at boot"
  echo "4) Disable at boot"
  echo "5) Restart tor.service"
  echo "6) Show full status"
  echo "7) Self-update BTor"
  echo "8) Uninstall BTor"
  echo "9) Quit"
  echo
  read -rp "Select an option [1-9]: " choice
  echo
  case "$choice" in
    1) start_service ;;
    2) stop_service ;;
    3) enable_service ;;
    4) disable_service ;;
    5) restart_service ;;
    6) show_status full ;;
    7) self_update ;;
    8) uninstall_btor ;;
    9) exit 0 ;;
    *) echo "${RED}Invalid option.${RESET}" ;;
  esac
}

usage() {
  cat <<EOF
BTor – Tor service manager

Usage:
  btor                  Launch interactive menu
  btor status           Show concise status
  btor status --full    Show full systemctl status
  btor start|stop|restart|enable|disable
  btor update           Self-update from GitHub
  btor uninstall        Remove BTor files

Env:
  BTOR_SERVICE_NAME     Override service name (default: tor.service)
  BTOR_HOME             Override BTor home (default: \$HOME/.btor)
  BTOR_REPO             Override raw repo URL base
EOF
}

main() {
  local cmd="${1:-}"
  case "${cmd}" in
    start) start_service ;;
    stop) stop_service ;;
    restart) restart_service ;;
    enable) enable_service ;;
    disable) disable_service ;;
    status)
      if [[ "${2:-}" == "--full" ]]; then show_status full; else show_status concise; fi
      ;;
    update) self_update ;;
    uninstall) uninstall_btor ;;
    -h|--help|help) usage ;;
    "") menu ;;
    *) echo "Unknown command: ${cmd}"; usage; exit 1 ;;
  esac
}

main "$@"
