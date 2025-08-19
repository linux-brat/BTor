#!/usr/bin/env bash
set -euo pipefail

# BTor single-file installer + manager with first-run setup and fancy UI + Browser Proxy helper
# File: btor.sh

# -----------------------------
# Config (overridable via env)
# -----------------------------
SERVICE_NAME="${BTOR_SERVICE_NAME:-tor.service}"
BTOR_HOME="${BTOR_HOME:-$HOME/.btor}"
BTOR_BIN_LINK="${BTOR_BIN_LINK:-/usr/local/bin/btor}"
BTOR_RAW_URL_DEFAULT="https://raw.githubusercontent.com/linux-brat/BTor/main/btor.sh"
BTOR_RAW_URL="${BTOR_REPO_RAW:-$BTOR_RAW_URL_DEFAULT}"
BTOR_VERSION="${BTOR_VERSION:-0.3.1}"

# Tor Browser defaults
TOR_BROWSER_DIR_DEFAULT="$HOME/.local/tor-browser"
TOR_BROWSER_DIR="${BTOR_TOR_BROWSER_DIR:-$TOR_BROWSER_DIR_DEFAULT}"

# UI timing
BTOR_SPLASH_SPEED="${BTOR_SPLASH_SPEED:-0.01}"
BTOR_SPLASH_PAUSE="${BTOR_SPLASH_PAUSE:-0.3}"

# Proxy defaults
BTOR_SOCKS_HOST="${BTOR_SOCKS_HOST:-127.0.0.1}"
BTOR_SOCKS_PORT="${BTOR_SOCKS_PORT:-9050}"

# -----------------------------
# UI helpers
# -----------------------------
bold() { tput bold 2>/dev/null || true; }
reset() { tput sgr0 2>/dev/null || true; }
green() { tput setaf 2 2>/dev/null || true; }
red() { tput setaf 1 2>/dev/null || true; }
yellow() { tput setaf 3 2>/dev/null || true; }
blue() { tput setaf 4 2>/dev/null || true; }
magenta() { tput setaf 5 2>/dev/null || true; }
cyan() { tput setaf 6 2>/dev/null || true; }

info() { echo "$(blue)$(bold)[i]$(reset) $*"; }
ok() { echo "$(green)$(bold)[ok]$(reset) $*"; }
warn() { echo "$(yellow)$(bold)[warn]$(reset) $*"; }
err() { echo "$(red)$(bold)[err]$(reset) $*"; }

need_sudo() { if [[ $EUID -ne 0 ]]; then sudo -v; fi; }
have_systemctl() { command -v systemctl >/dev/null 2>&1; }
is_stdin_tty() { [[ -t 0 ]]; }
have_dev_tty() { [[ -r /dev/tty ]]; }

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
  err "No interactive TTY available."
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

line() { printf "%s\n" "──────────────────────────────────────────────────────────────────────────────"; }

# -----------------------------
# ASCII UI
# -----------------------------
ascii_btor() {
  cat <<'BTOR_ASCII'
   ____  _______
  | __ )|_   _|_ __   ___   ___
  |  _ \  | | | '_ \ / _ \ / _ \
  | |_) | | | | | | | (_) | (_) |
  |____/  |_| |_| |_|\___/ \___/

                 B T o r
BTOR_ASCII
}
ascii_subtitle() { printf "%s\n" "$(magenta)$(bold)Tor service manager · v${BTOR_VERSION}$(reset)"; }

type_line() {
  local s="$1"; local i ch
  for ((i=0; i<${#s}; i++)); do ch="${s:$i:1}"; printf "%s" "$ch"; sleep "${BTOR_SPLASH_SPEED}"; done
  printf "\n"; sleep "${BTOR_SPLASH_PAUSE}"
}
splash() {
  clear 2>/dev/null || true
  local lines=(
"   ____  _______"
"  | __ )|_   _|_ __   ___   ___"
"  |  _ \\  | | | '_ \\ / _ \\ / _ \\"
"  | |_) | | | | | | | (_) | (_) |"
"  |____/  |_| |_| |_|\\___/ \\___/"
""
"                 B T o r"
""
  )
  printf "%s" "$(cyan)"; for l in "${lines[@]}"; do type_line "$l"; done; printf "%s" "$(reset)"
  ascii_subtitle; line
}
header() { clear 2>/dev/null || true; ascii_btor; ascii_subtitle; line; }

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
  local pkgs=("$@"); local pm; pm="$(pm_detect)"; need_sudo
  case "$pm" in
    apt) sudo apt-get update -y; sudo apt-get install -y "${pkgs[@]}";;
    dnf) sudo dnf install -y "${pkgs[@]}";;
    yum) sudo yum install -y "${pkgs[@]}";;
    pacman) sudo pacman -Sy --noconfirm "${pkgs[@]}";;
    zypper) sudo zypper install -y "${pkgs[@]}";;
    *) err "Unsupported package manager. Please install: ${pkgs[*]}"; return 1;;
  esac
}

# -----------------------------
# Tor CLI / service checks
# -----------------------------
tor_cli_installed() { command -v tor >/dev/null 2>&1; }
tor_service_exists() { systemctl list-unit-files | grep -q "^${SERVICE_NAME}\b" || systemctl status "${SERVICE_NAME}" >/dev/null 2>&1; }

install_or_update_tor() {
  info "Checking Tor installation..."
  if tor_cli_installed; then ok "Tor CLI found: $(command -v tor)"; else warn "Tor CLI not found."; fi
  if tor_service_exists; then ok "Tor systemd unit found: ${SERVICE_NAME}"; else warn "Tor unit ${SERVICE_NAME} not found."; fi

  if tor_cli_installed && tor_service_exists; then
    if confirm "Tor seems installed. Check for updates via package manager? [y/N]: "; then
      case "$(pm_detect)" in
        apt) need_sudo; sudo apt-get update -y && sudo apt-get install -y tor ;;
        dnf|yum|pacman|zypper) pm_install tor ;;
        *) warn "Unknown package manager. Skipping Tor update." ;;
      esac
    fi
    return 0
  fi

  if confirm "Tor is missing or incomplete. Install Tor now? [y/N]: "; then
    case "$(pm_detect)" in
      apt|dnf|yum|pacman|zypper) pm_install tor ;;
      *) err "Unsupported package manager. Please install Tor manually."; return 1 ;;
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
  if [[ -x "${TOR_BROWSER_DIR}/tor-browser/Browser/start-tor-browser" ]]; then
    echo "${TOR_BROWSER_DIR}/tor-browser/Browser/start-tor-browser"; return
  fi
  local cand; cand="$(find "${TOR_BROWSER_DIR}" -type f -name start-tor-browser -perm -111 2>/dev/null | head -n1 || true)"
  [[ -n "$cand" ]] && echo "$cand" || echo ""
}
tor_browser_installed() { [[ -n "$(tor_browser_bin)" ]] }
download_tor_browser() {
  local url="https://www.torproject.org/dist/torbrowser/13.5.2/tor-browser-linux64-13.5.2_ALL.tar.xz"
  url="${BTOR_TB_URL:-$url}"; mkdir -p "${TOR_BROWSER_DIR}"
  info "Downloading Tor Browser to ${TOR_BROWSER_DIR}..."
  curl -fL --progress-bar "$url" -o "${TOR_BROWSER_DIR}/tor-browser.tar.xz"
  info "Extracting..."; tar -xf "${TOR_BROWSER_DIR}/tor-browser.tar.xz" -C "${TOR_BROWSER_DIR}"
  rm -f "${TOR_BROWSER_DIR}/tor-browser.tar.xz"; ok "Tor Browser downloaded."
}
install_or_update_tor_browser() {
  info "Checking Tor Browser..."; local bin; bin="$(tor_browser_bin)"
  if [[ -n "$bin" ]]; then
    ok "Tor Browser found: $bin"
    if confirm "Launch Tor Browser updater (GUI) now? [y/N]: "; then nohup "$bin" >/dev/null 2>&1 & info "Launched updater."; fi
    return 0
  fi
  warn "Tor Browser not found under ${TOR_BROWSER_DIR}."
  if confirm "Download Tor Browser now? [y/N]: "; then
    download_tor_browser; bin="$(tor_browser_bin || true)"
    [[ -n "$bin" ]] && ok "Tor Browser ready: $bin" || warn "Could not validate Tor Browser installation."
  else
    warn "Skipping Tor Browser."; return 1
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
        dnf|yum|pacman|zypper) pm_install nodejs npm ;;
        *) warn "Unsupported package manager. Skipping Node update." ;;
      esac
    fi
    return 0
  fi
  warn "Node/npm/npx not fully available."
  if confirm "Install Node.js and npm now? [y/N]: "; then
    case "$(pm_detect)" in
      apt|dnf|yum|pacman|zypper) pm_install nodejs npm ;;
      *) err "Unsupported package manager. Please install Node.js/npm manually."; return 1 ;;
    esac
    ! npx_installed && npm_installed && ok "npx available via npm."
  else
    warn "Skipping Node.js/npm installation."; return 1
  fi
}

# -----------------------------
# First-run gate
# -----------------------------
first_run_marker() { echo "${BTOR_HOME}/.first_run_done"; }
first_run_needed() { [[ ! -f "$(first_run_marker)" ]]; }
run_first_time_setup() {
  header; info "First-time setup starting..."; mkdir -p "${BTOR_HOME}"
  install_or_update_tor || true; echo
  install_or_update_tor_browser || true; echo
  install_or_update_node_stack || true
  touch "$(first_run_marker)"; ok "First-time setup complete."; line; press_enter
}

# -----------------------------
# Install / Uninstall / Update
# -----------------------------
install_self() {
  header; info "Installing BTor to ${BTOR_HOME}..."; mkdir -p "${BTOR_HOME}"
  if [[ -n "${BASH_SOURCE[0]:-}" && -f "${BASH_SOURCE}" ]]; then cp "${BASH_SOURCE}" "${BTOR_HOME}/btor"; else curl -fsSL "${BTOR_RAW_URL}" -o "${BTOR_HOME}/btor"; fi
  chmod +x "${BTOR_HOME}/btor"; info "Linking ${BTOR_BIN_LINK} (requires sudo)..."; need_sudo; sudo ln -sf "${BTOR_HOME}/btor" "${BTOR_BIN_LINK}"
  ok "Installed. Launch with: btor"; line
}
uninstall_self() { header; warn "Uninstalling BTor..."; need_sudo; sudo rm -f "${BTOR_BIN_LINK}" || true; rm -rf "${BTOR_HOME}" || true; ok "BTor uninstalled."; line; }
self_update() {
  header; info "Updating from ${BTOR_RAW_URL}..."; mkdir -p "${BTOR_HOME}"
  curl -fsSL "${BTOR_RAW_URL}" -o "${BTOR_HOME}/btor.new"; chmod +x "${BTOR_HOME}/btor.new"; mv "${BTOR_HOME}/btor.new" "${BTOR_HOME}/btor"
  ok "BTor updated."; line
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
  if ! have_systemctl; then err "systemctl not found; BTor requires systemd."; return 1; fi
  local is_active is_enabled; is_active="$(systemctl is-active "${SERVICE_NAME}" 2>/dev/null || true)"; is_enabled="$(systemctl is-enabled "${SERVICE_NAME}" 2>/dev/null || true)"
  local a e; [[ "${is_active}" == "active" ]] && a="$(green)active$(reset)" || a="$(red)${is_active:-unknown}$(reset)"
  [[ "${is_enabled}" == "enabled" ]] && e="$(green)enabled$(reset)" || e="$(yellow)${is_enabled:-unknown}$(reset)"
  echo "Service: $(bold)${SERVICE_NAME}$(reset)"; echo "Status: ${a}  |  Boot: ${e}"
}

# -----------------------------
# Browser Proxy helper (GNOME, Firefox, Chromium/Chrome/Brave)
# -----------------------------

# GNOME system proxy via gsettings
gnome_proxy_set() {
  if ! command -v gsettings >/dev/null 2>&1; then warn "gsettings not found (GNOME proxy not available)."; return 1; fi
  gsettings set org.gnome.system.proxy mode 'manual'
  gsettings set org.gnome.system.proxy.socks host "${BTOR_SOCKS_HOST}"
  gsettings set org.gnome.system.proxy.socks port "${BTOR_SOCKS_PORT}"
  ok "GNOME system SOCKS proxy set to ${BTOR_SOCKS_HOST}:${BTOR_SOCKS_PORT}"
}
gnome_proxy_unset() {
  if ! command -v gsettings >/dev/null 2>&1; then return 0; fi
  gsettings set org.gnome.system.proxy mode 'none'
  ok "GNOME system proxy disabled"
}

# Firefox per-profile proxy (prefs.js). We prefer user.js injection to avoid clobbering.
firefox_profiles_dirs() {
  local base1="$HOME/.mozilla/firefox" base2="$HOME/snap/firefox/common/.mozilla/firefox"
  for b in "$base1" "$base2"; do [[ -d "$b" ]] && find "$b" -maxdepth 1 -type d -name "*.default*" 2>/dev/null; done
}
firefox_set_proxy_userjs() {
  local dir="$1"; local f="$dir/user.js"
  cp -n "$dir/prefs.js" "$dir/prefs.js.bak.$(date +%s)" 2>/dev/null || true
  cat > "$f" <<EOF
// Set by BTor
user_pref("network.proxy.type", 1);
user_pref("network.proxy.socks", "${BTOR_SOCKS_HOST}");
user_pref("network.proxy.socks_port", ${BTOR_SOCKS_PORT});
user_pref("network.proxy.no_proxies_on", "localhost, 127.0.0.1, ::1");
user_pref("network.proxy.socks_remote_dns", true);
EOF
  ok "Firefox proxy set via $f"
}
firefox_unset_proxy_userjs() {
  local dir="$1"; local f="$dir/user.js"
  if [[ -f "$f" ]]; then
    # Remove only the prefs we added; preserve other lines
    grep -v -E 'network\.proxy\.(type|socks|socks_port|no_proxies_on|socks_remote_dns)' "$f" > "$f.tmp" || true
    mv "$f.tmp" "$f"
    ok "Firefox user.js cleaned at $f"
  fi
}

# Chromium/Chrome/Brave via wrapper with --proxy-server
browser_wrapper_dir="${BTOR_HOME}/proxy-wrappers"
make_wrapper() {
  local app="$1" bin; bin="$(command -v "$app" || true)"
  [[ -z "$bin" ]] && return 1
  mkdir -p "$browser_wrapper_dir"
  local wrapper="${browser_wrapper_dir}/${app}"
  cat > "$wrapper" <<EOF
#!/usr/bin/env bash
exec "$bin" --proxy-server="socks5://${BTOR_SOCKS_HOST}:${BTOR_SOCKS_PORT}" "\$@"
EOF
  chmod +x "$wrapper"
  ok "Wrapper created: $wrapper"
  echo "$wrapper"
}
remove_wrapper() {
  local app="$1"; rm -f "${browser_wrapper_dir}/${app}" 2>/dev/null || true
}

# High-level set/unset
proxy_set_all() {
  header
  info "Setting browser proxies to SOCKS ${BTOR_SOCKS_HOST}:${BTOR_SOCKS_PORT}"
  echo; line

  # GNOME
  gnome_proxy_set || true

  # Firefox (all detected profiles)
  local d; for d in $(firefox_profiles_dirs); do
    firefox_set_proxy_userjs "$d" || true
  done
  [[ -z "$(firefox_profiles_dirs || true)" ]] && warn "No Firefox profiles detected."

  # Chromium family wrappers
  local apps=(chromium google-chrome google-chrome-stable brave brave-browser microsoft-edge-stable vivaldi)
  local created=0
  for a in "${apps[@]}"; do
    if command -v "$a" >/dev/null 2>&1; then
      make_wrapper "$a" >/dev/null && created=1
    fi
  done
  if [[ $created -eq 1 ]]; then
    echo
    info "To use SOCKS proxy in Chromium/Chrome/Brave:"
    echo "  - Run via wrapper, e.g.: ${browser_wrapper_dir}/chromium"
    echo "  - Or add --proxy-server=\"socks5://${BTOR_SOCKS_HOST}:${BTOR_SOCKS_PORT}\" to your launcher"
  else
    warn "Chromium/Chrome/Brave not found or wrappers not created."
  fi

  line; press_enter
}

proxy_unset_all() {
  header
  info "Removing browser/system proxy settings"
  echo; line

  # GNOME
  gnome_proxy_unset || true

  # Firefox user.js cleanup
  local d; for d in $(firefox_profiles_dirs); do
    firefox_unset_proxy_userjs "$d" || true
  done

  # Remove wrappers
  local apps=(chromium google-chrome google-chrome-stable brave brave-browser microsoft-edge-stable vivaldi)
  for a in "${apps[@]}"; do remove_wrapper "$a" || true; done
  [[ -d "$browser_wrapper_dir" ]] && rmdir "$browser_wrapper_dir" 2>/dev/null || true

  ok "Proxy disabled/cleaned."
  line; press_enter
}

proxy_status() {
  header
  echo "$(bold)Proxy target:$(reset) ${BTOR_SOCKS_HOST}:${BTOR_SOCKS_PORT}"
  echo
  if command -v gsettings >/dev/null 2>&1; then
    local mode; mode="$(gsettings get org.gnome.system.proxy mode 2>/dev/null || echo unknown)"
    local host port
    host="$(gsettings get org.gnome.system.proxy.socks host 2>/dev/null || echo '')"
    port="$(gsettings get org.gnome.system.proxy.socks port 2>/dev/null || echo '')"
    echo "GNOME: mode=$mode socks=${host//\'/}:${port}"
  else
    echo "GNOME: gsettings not available"
  fi
  echo
  local fcount=0
  for d in $(firefox_profiles_dirs); do
    fcount=1
    echo "Firefox profile: $d"
    if [[ -f "$d/user.js" ]]; then
      grep -E 'network\.proxy\.(type|socks|socks_port|socks_remote_dns)' "$d/user.js" || echo "  (no proxy prefs by BTor)"
    else
      echo "  user.js not present"
    fi
    echo
  done
  [[ $fcount -eq 0 ]] && echo "Firefox: no profiles detected"
  echo
  echo "Wrappers dir: $browser_wrapper_dir"
  ls -1 "$browser_wrapper_dir" 2>/dev/null || echo "(no wrappers)"
  line; press_enter
}

browser_proxy_menu() {
  header
  echo "$(bold)Browser Proxy Helper$(reset)"
  echo "Target: SOCKS ${BTOR_SOCKS_HOST}:${BTOR_SOCKS_PORT}"
  echo
  echo "1) Set proxy (GNOME + Firefox + wrappers for Chromium/Chrome/Brave)"
  echo "2) Remove proxy"
  echo "3) Status"
  echo "4) Back"
  echo
  local choice; choice="$(tty_read "Select an option [1-4]: ")"
  case "$choice" in
    1) proxy_set_all ;;
    2) proxy_unset_all ;;
    3) proxy_status ;;
    4) return 0 ;;
    *) err "Invalid option." ;;
  esac
}

# -----------------------------
# Menu
# -----------------------------
menu_once() {
  header
  show_status
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
  echo "10) Browser Proxy (Set/Unset)"
  echo
  local choice; choice="$(tty_read "Select an option [1-10]: ")"
  echo
  case "${choice}" in
    1) start_service ;;
    2) stop_service ;;
    3) enable_service ;;
    4) disable_service ;;
    5) restart_service ;;
    6) clear 2>/dev/null || true; header; systemctl --no-pager status "${SERVICE_NAME}" || true ;;
    7) self_update ;;
    8) uninstall_self; return 1 ;;
    9) return 1 ;;
    10) browser_proxy_menu ;;
    *) err "Invalid option." ;;
  esac
  return 0
}

menu_loop() {
  while true; do
    if ! menu_once; then break; fi
    echo; press_enter
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
  BTOR_TOR_BROWSER_DIR           Tor Browser directory (default: \$HOME/.local/tor-browser)
  BTOR_TB_URL                    Override Tor Browser tarball URL
  BTOR_SOCKS_HOST                SOCKS host (default: 127.0.0.1)
  BTOR_SOCKS_PORT                SOCKS port (default: 9050)

UI:
  BTOR_SPLASH_SPEED              Typing delay per char
  BTOR_SPLASH_PAUSE              Pause per line in splash
EOF
}

# -----------------------------
# Entry
# -----------------------------
cli() {
  if is_stdin_tty || have_dev_tty; then splash; fi

  if [[ -z "${1:-}" ]] && ! is_stdin_tty; then
    if have_dev_tty; then install_self; exec btor
    else warn "No /dev/tty; running menu without installing."
         if first_run_needed; then run_first_time_setup || true; fi
         menu_loop; exit 0
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
    status)    header; if [[ "${2:-}" == "--full" ]]; then systemctl --no-pager status "${SERVICE_NAME}" || true; else show_status; fi; line ;;
    -h|--help|help) usage ;;
    "")        if first_run_needed; then run_first_time_setup || true; fi; menu_loop ;;
    *)         err "Unknown command: ${cmd}"; usage; exit 1 ;;
  esac
}

cli "$@"
