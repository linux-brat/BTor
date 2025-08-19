#!/usr/bin/env bash
set -euo pipefail

# BTor - Tor manager with classic UI, first-time setup, proxy helpers,
# Tor Browser detection (launcher-aware, no direct CDN downloads),
# Tor route test, simplified menu.
# Behavior updates:
# - "Status & open check.torproject.org" opens ONLY Firefox. If Firefox is missing, auto-install it, apply proxy, and open the site.
# - After First-time setup, print a clear message: "Setup finished. Launch BTor using: btor"

# -----------------------------
# Config
# -----------------------------
SERVICE_NAME="${BTOR_SERVICE_NAME:-tor.service}"
BTOR_HOME="${BTOR_HOME:-$HOME/.btor}"
BTOR_BIN_LINK="${BTOR_BIN_LINK:-/usr/local/bin/btor}"
BTOR_RAW_URL_DEFAULT="https://raw.githubusercontent.com/linux-brat/BTor/main/btor.sh"
BTOR_RAW_URL="${BTOR_REPO_RAW:-$BTOR_RAW_URL_DEFAULT}"
BTOR_VERSION="${BTOR_VERSION:-1.6.0}"

# SOCKS settings
BTOR_SOCKS_HOST="${BTOR_SOCKS_HOST:-127.0.0.1}"
BTOR_SOCKS_PORT="${BTOR_SOCKS_PORT:-9050}"
BTOR_SOCKS_PORT_ALT="${BTOR_SOCKS_PORT_ALT:-9150}"  # Tor Browser default

# First-run marker
FIRST_RUN_MARKER="${BTOR_HOME}/.first_run_done"

# -----------------------------
# UI Helpers (classic)
# -----------------------------
bold() { tput bold 2>/dev/null || true; }
reset() { tput sgr0 2>/dev/null || true; }
green() { tput setaf 2 2>/dev/null || true; }
red() { tput setaf 1 2>/dev/null || true; }
yellow() { tput setaf 3 2>/dev/null || true; }
blue() { tput setaf 4 2>/dev/null || true; }
magenta() { tput setaf 5 2>/dev/null || true; }
cyan() { tput setaf 6 2>/dev/null || true; }

line() { printf "%s\n" "----------------------------------------------------------------"; }

info() { printf "%s\n" "$(blue)$(bold)[i]$(reset) $*"; }
ok()   { printf "%s\n" "$(green)$(bold)[ok]$(reset) $*"; }
warn() { printf "%s\n" "$(yellow)$(bold)[warn]$(reset) $*"; }
err()  { printf "%s\n" "$(red)$(bold)[err]$(reset) $*"; }

need_sudo() { if [ "${EUID:-$(id -u)}" -ne 0 ]; then sudo -v || true; fi; }
have_systemctl() { command -v systemctl >/dev/null 2>&1; }

is_tty() { [ -t 0 ] || [ -r /dev/tty ]; }
read_tty() {
  local prompt="$1"
  if [ -t 0 ]; then
    read -rp "$prompt" __ans || true
    printf "%s" "${__ans:-}"
  elif [ -r /dev/tty ]; then
    printf "%s" "$prompt" >&2
    local line_in=""; IFS= read -r line_in < /dev/tty || true
    printf "%s" "$line_in"
  else
    printf ""
  fi
}
confirm() { local ans; ans="$(read_tty "${1:-Proceed? [y/N]: }")"; case "${ans,,}" in y|yes) return 0 ;; *) return 1 ;; esac; }

header() {
  clear 2>/dev/null || true
  printf "%s\n" "$(cyan)██████╗░████████╗░█████╗░██████╗░$(reset)"
  printf "%s\n" "$(cyan)██╔══██╗╚══██╔══╝██╔══██╗██╔══██╗$(reset)"
  printf "%s\n" "$(cyan)██████╦╝░░░██║░░░██║░░██║██████╔╝$(reset)"
  printf "%s\n" "$(cyan)██╔══██╗░░░██║░░░██║░░██║██╔══██╗$(reset)"
  printf "%s\n" "$(cyan)██████╦╝░░░██║░░░╚█████╔╝██║░░██║$(reset)"
  printf "%s\n" "$(cyan)╚═════╝░░░░╚═╝░░░░╚════╝░╚═╝░░╚═╝$(reset)"
  printf "%s\n" "$(magenta)$(bold)Tor service manager · v${BTOR_VERSION}$(reset)"
  line
}

pause_once() { if is_tty; then read_tty "Press Enter to continue... > " >/dev/null; fi; }

# -----------------------------
# OS / PM
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
  local pm; pm="$(pm_detect)"; need_sudo
  case "$pm" in
    apt) sudo apt-get update -y || true; sudo apt-get install -y "$@" || true ;;
    dnf) sudo dnf install -y "$@" || true ;;
    yum) sudo yum install -y "$@" || true ;;
    pacman) sudo pacman -Sy --noconfirm "$@" || true ;;
    zypper) sudo zypper install -y "$@" || true ;;
    *) warn "Unsupported package manager. Please install manually: $*"; return 1 ;;
  esac
}

# -----------------------------
# Tor basics
# -----------------------------
tor_cli_installed() { command -v tor >/dev/null 2>&1; }
tor_service_exists() {
  systemctl list-unit-files 2>/dev/null | grep -q "^${SERVICE_NAME}\b" || systemctl status "${SERVICE_NAME}" >/dev/null 2>&1
}
tor_active() { systemctl is-active "${SERVICE_NAME}" 2>/dev/null | grep -q '^active$'; }

ensure_tor_running_with_prompt() {
  if tor_active; then return 0; fi
  if ! have_systemctl; then warn "systemctl not available; cannot control tor.service."; return 1; fi
  if confirm "tor.service is not running. Start it now? [y/N]: "; then
    need_sudo; sudo systemctl start "${SERVICE_NAME}" || true
    if tor_active; then ok "Started ${SERVICE_NAME}."; return 0; else err "Failed to start ${SERVICE_NAME}."; return 1; fi
  else
    warn "Continuing without starting tor.service."
    return 1
  fi
}

# -----------------------------
# Tor Browser detection (launcher-aware, no direct CDN downloads)
# -----------------------------
torbrowser_launcher_cache_candidates() {
  cat <<EOF
$HOME/.local/share/torbrowser/tbb/x86_64/tor-browser/Browser/start-tor-browser
$HOME/.local/share/torbrowser/tbb/*/tor-browser/Browser/start-tor-browser
$HOME/.cache/torbrowser/tbb/*/tor-browser/Browser/start-tor-browser
EOF
}
tor_browser_scan_all() {
  cat <<EOF
${BTOR_TOR_BROWSER_BIN:-}
${HOME}/tor-browser/Browser/start-tor-browser
${HOME}/tor-browser_en-US/Browser/start-tor-browser
${HOME}/Applications/Tor Browser/start-tor-browser
/opt/tor-browser/Browser/start-tor-browser
/opt/TorBrowser/Browser/start-tor-browser
/var/opt/tor-browser/Browser/start-tor-browser
$(torbrowser_launcher_cache_candidates)
EOF
  {
    find "$HOME" -maxdepth 5 -type f -name 'start-tor-browser' -perm -111 2>/dev/null || true
    find /opt /usr/local /usr /var -maxdepth 5 -type f -name 'start-tor-browser' -perm -111 2>/dev/null || true
  } | sort -u
}
tor_browser_bin() {
  local p
  while IFS= read -r p; do
    [ -z "${p:-}" ] && continue
    if [ -x "$p" ]; then printf "%s" "$p"; return 0; fi
  done <<EOF
$(tor_browser_scan_all)
EOF
  return 1
}

tb_launcher_pkg_name() {
  case "$(pm_detect)" in
    apt|dnf|yum|zypper|pacman) echo "torbrowser-launcher" ;;
    *) echo "" ;;
  esac
}
__TB_LAUNCHER_TRIED="${__TB_LAUNCHER_TRIED:-0}"
install_torbrowser_via_launcher_only() {
  local bin=""
  if bin="$(tor_browser_bin)"; then ok "Tor Browser detected at: $bin"; return 0; fi

  if [ "${__TB_LAUNCHER_TRIED}" != "1" ]; then
    local pkg; pkg="$(tb_launcher_pkg_name)"
    if [ -n "$pkg" ]; then
      info "Installing torbrowser-launcher via package manager (if available)..."
      if pm_install "$pkg"; then
        if command -v torbrowser-launcher >/dev/null 2>&1; then
          info "Launching torbrowser-launcher (GUI). Complete Tor Browser setup there."
          nohup torbrowser-launcher >/dev/null 2>&1 || true
          sleep 3
        else
          warn "torbrowser-launcher installed but not found on PATH."
        fi
      else
        warn "torbrowser-launcher not available or failed to install."
      fi
    else
      warn "No known launcher package name for this distro."
    fi
    __TB_LAUNCHER_TRIED="1"
  fi

  if bin="$(tor_browser_bin)"; then ok "Tor Browser detected at: $bin"; return 0; fi
  warn "Tor Browser not found yet. Run 'torbrowser-launcher' once, then re-run BTor."
  return 1
}
ensure_tor_browser() {
  local bin=""
  if bin="$(tor_browser_bin)"; then printf "%s" "$bin"; return 0; fi
  warn "Tor Browser not found."
  if confirm "Try installing via torbrowser-launcher now? [y/N]: "; then
    install_torbrowser_via_launcher_only || true
    if bin="$(tor_browser_bin)"; then printf "%s" "$bin"; return 0; fi
    err "Tor Browser still not detected. Complete launcher setup and retry."
    return 1
  fi
  return 1
}

# -----------------------------
# Firefox install/helper
# -----------------------------
install_firefox_if_missing() {
  if command -v firefox >/dev/null 2>&1; then return 0; fi
  info "Firefox is not installed. Installing Firefox..."
  case "$(pm_detect)" in
    apt)    pm_install firefox || { err "Failed to install Firefox."; return 1; } ;;
    dnf)    pm_install firefox || { err "Failed to install Firefox."; return 1; } ;;
    yum)    pm_install firefox || { err "Failed to install Firefox."; return 1; } ;;
    pacman) pm_install firefox || { err "Failed to install Firefox."; return 1; } ;;
    zypper) pm_install MozillaFirefox || pm_install firefox || { err "Failed to install Firefox."; return 1; } ;;
    *)      err "Unknown package manager. Please install Firefox manually."; return 1 ;;
  esac
  ok "Firefox installed."
  return 0
}

firefox_profiles_dirs() {
  local base1="$HOME/.mozilla/firefox" base2="$HOME/snap/firefox/common/.mozilla/firefox"
  if [ -d "$base1" ]; then find "$base1" -maxdepth 1 -type d -name "*.default*" 2>/dev/null; fi
  if [ -d "$base2" ]; then find "$base2" -maxdepth 1 -type d -name "*.default*" 2>/dev/null; fi
}
_ff_write_userjs() {
  local dir="${1:-}"; [ -n "$dir" ] || return 0
  cat > "$dir/user.js" <<EOF
// Set by BTor
user_pref("network.proxy.type", 1);
user_pref("network.proxy.socks", "${BTOR_SOCKS_HOST}");
user_pref("network.proxy.socks_port", ${BTOR_SOCKS_PORT});
user_pref("network.proxy.no_proxies_on", "localhost");
user_pref("network.proxy.socks_remote_dns", true);
EOF
}
_ff_touch_prefs() {
  local dir="${1:-}"; [ -n "$dir" ] || return 0
  local p="$dir/prefs.js"
  [ -f "$p" ] || touch "$p"
  cp -n "$p" "$dir/prefs.js.bak.$(date +%s)" 2>/dev/null || true
  grep -v -E 'network\.proxy\.(type|socks"|socks_port|no_proxies_on|socks_remote_dns)' "$p" 2>/dev/null > "$p.tmp" || true
  mv "$p.tmp" "$p" || true
  cat >> "$p" <<EOF
user_pref("network.proxy.type", 1);
user_pref("network.proxy.socks", "${BTOR_SOCKS_HOST}");
user_pref("network.proxy.socks_port", ${BTOR_SOCKS_PORT});
user_pref("network.proxy.no_proxies_on", "localhost");
user_pref("network.proxy.socks_remote_dns", true);
EOF
}
firefox_set_proxy_all() {
  local found=0 d
  while IFS= read -r d; do
    [ -z "${d:-}" ] && continue
    found=1; _ff_write_userjs "$d" || true; _ff_touch_prefs "$d" || true
  done < <(firefox_profiles_dirs || true)
  [ "$found" -eq 0 ] && warn "No Firefox profiles found. Start Firefox once, then re-run."
}

# -----------------------------
# GNOME proxy helpers
# -----------------------------
gnome_proxy_set() {
  if ! command -v gsettings >/dev/null 2>&1; then return 1; fi
  gsettings set org.gnome.system.proxy mode 'manual' || true
  gsettings set org.gnome.system.proxy.socks host "${BTOR_SOCKS_HOST}" || true
  gsettings set org.gnome.system.proxy.socks port "${BTOR_SOCKS_PORT}" || true
  return 0
}
gnome_proxy_unset() { if command -v gsettings >/dev/null 2>&1; then gsettings set org.gnome.system.proxy mode 'none' || true; fi; }

# -----------------------------
# First-time setup
# -----------------------------
first_run_needed() { [ ! -f "${FIRST_RUN_MARKER}" ]; }

install_nyx() {
  case "$(pm_detect)" in
    apt|dnf|yum|pacman|zypper) pm_install nyx ;;
    *) warn "Unknown package manager; install Nyx (nyx) manually if needed." ;;
  esac
}
install_node_npm() {
  case "$(pm_detect)" in
    apt|dnf|yum|pacman|zypper) pm_install nodejs npm ;;
    *) warn "Unknown package manager; install Node.js/npm manually for npx." ;;
  esac
}

first_run_setup() {
  header
  printf "%s\n" "$(bold)First-time setup$(reset)"
  line

  case "$(pm_detect)" in
    pacman)
      info "Arch/Manjaro detected: installing tor, torbrowser-launcher, nyx"
      need_sudo
      sudo pacman -Sy --noconfirm tor torbrowser-launcher nyx || warn "pacman install reported issues; continuing."
      ;;
    apt|dnf|yum|zypper)
      info "Installing Tor"
      pm_install tor || warn "Tor install reported issues."
      info "Installing torbrowser-launcher (if available)"
      pm_install torbrowser-launcher || warn "torbrowser-launcher not available or failed; you can install it later."
      info "Installing Nyx"
      pm_install nyx || warn "Nyx install reported issues."
      ;;
    *)
      warn "Unknown distro: please ensure tor, torbrowser-launcher, and nyx are installed."
      ;;
  esac

  # Node.js + npm (npx)
  if command -v node >/dev/null 2>&1 && command -v npm >/dev/null 2>&1; then
    ok "Node.js and npm are installed."
  else
    info "Installing Node.js and npm (for npx)..."
    install_node_npm
  fi

  mkdir -p "${BTOR_HOME}" || true
  echo "done" > "${FIRST_RUN_MARKER}"
  ok "First-time setup complete."
  printf "\n%s\n" "$(green)$(bold)Setup finished. Launch BTor using: btor$(reset)"
  line
}

# -----------------------------
# Install / Update / Uninstall BTor
# -----------------------------
install_self() {
  header
  printf "%s\n" "$(bold)Installing BTor$(reset)"
  line
  mkdir -p "${BTOR_HOME}" || true
  if [ -n "${BASH_SOURCE[0]-}" ] && [ -f "${BASH_SOURCE[0]}" ]; then
    cp "${BASH_SOURCE[0]}" "${BTOR_HOME}/btor" || true
  else
    curl -fsSL "${BTOR_RAW_URL}" -o "${BTOR_HOME}/btor" || true
  fi
  chmod +x "${BTOR_HOME}/btor" || true
  need_sudo; sudo ln -sf "${BTOR_HOME}/btor" "${BTOR_BIN_LINK}" || true
  ok "Installed. Use: btor"
  line

  if first_run_needed; then
    first_run_setup
  else
    info "First-time setup already completed. Skipping."
    printf "%s\n" "$(green)$(bold)Setup finished. Launch BTor using: btor$(reset)"
    line
  fi
}
uninstall_self() {
  header
  printf "%s\n" "$(bold)Uninstalling BTor$(reset)"
  line
  need_sudo; sudo rm -f "${BTOR_BIN_LINK}" || true
  rm -rf "${BTOR_HOME}" || true
  ok "Uninstalled."
  line
}
self_update() {
  header
  printf "%s\n" "$(bold)Updating BTor$(reset)"
  line
  mkdir -p "${BTOR_HOME}" || true
  if curl -fsSL "${BTOR_RAW_URL}" -o "${BTOR_HOME}/btor.new"; then
    chmod +x "${BTOR_HOME}/btor.new" || true
    mv "${BTOR_HOME}/btor.new" "${BTOR_HOME}/btor" || true
    ok "Updated."
  else
    err "Update fetch failed."
  fi
  line
}

# -----------------------------
# Service operations
# -----------------------------
start_service() {
  need_sudo; sudo systemctl start "${SERVICE_NAME}" || true
  if tor_active; then
    ok "Started ${SERVICE_NAME}."
    if confirm "Open Tor Browser now? [y/N]: "; then
      local bin=""; if bin="$(ensure_tor_browser)"; then
        nohup "$bin" >/dev/null 2>&1 & ok "Tor Browser launched."
      else
        warn "Tor Browser not available."
      fi
    fi
  else
    err "Failed to start ${SERVICE_NAME}. Check full status."
  fi
}
stop_service()    { need_sudo; sudo systemctl stop    "${SERVICE_NAME}" || true; ok "Stopped ${SERVICE_NAME}."; }
restart_service() { need_sudo; sudo systemctl restart "${SERVICE_NAME}" || true; ok "Restarted ${SERVICE_NAME}."; }
enable_service()  { need_sudo; sudo systemctl enable  "${SERVICE_NAME}" || true; ok "Enabled at boot."; }
disable_service() { need_sudo; sudo systemctl disable "${SERVICE_NAME}" || true; ok "Disabled at boot."; }

show_status() {
  if ! have_systemctl; then err "systemctl not found."; return 1; fi
  local is_active is_enabled
  is_active="$(systemctl is-active "${SERVICE_NAME}" 2>/dev/null || true)"
  is_enabled="$(systemctl is-enabled "${SERVICE_NAME}" 2>/dev/null || true)"
  local a e
  if [ "$is_active" = "active" ]; then a="$(green)active$(reset)"; else a="$(red)${is_active:-unknown}$(reset)"; fi
  if [ "$is_enabled" = "enabled" ]; then e="$(green)enabled$(reset)"; else e="$(yellow)${is_enabled:-unknown}$(reset)"; fi
  printf "Service: %s\n" "${SERVICE_NAME}"
  printf "Status:  %s | Boot: %s\n" "${a}" "${e}"
}

# -----------------------------
# Browser Proxy helper (Firefox primary; wrappers for Chromium/Brave optional)
# -----------------------------
print_manual_proxy_steps() {
  cat <<'STEPS'
Manual steps if auto-configuration is not available:
- Firefox: Preferences > Network Settings:
    - Manual proxy configuration
    - SOCKS Host: 127.0.0.1  Port: 9050
    - Check "Proxy DNS when using SOCKS v5"
- Chromium-based: launch with flags:
    --proxy-server="socks5://127.0.0.1:9050" --host-resolver-rules="MAP * ~NOTFOUND , EXCLUDE localhost"
Then visit http://check.torproject.org/
STEPS
}

# GNOME proxy (optional system-wide)
gnome_proxy_set() {
  if ! command -v gsettings >/dev/null 2>&1; then return 1; fi
  gsettings set org.gnome.system.proxy mode 'manual' || true
  gsettings set org.gnome.system.proxy.socks host "${BTOR_SOCKS_HOST}" || true
  gsettings set org.gnome.system.proxy.socks port "${BTOR_SOCKS_PORT}" || true
  return 0
}
gnome_proxy_unset() { if command -v gsettings >/dev/null 2>&1; then gsettings set org.gnome.system.proxy mode 'none' || true; fi; }

# -----------------------------
# Proxy workflows (Firefox-focused)
# -----------------------------
proxy_set_all() {
  header
  printf "%s\n" "$(bold)Setting Browser Proxy$(reset)"
  line

  # Ensure Firefox present
  install_firefox_if_missing || { err "Cannot set browser proxy without Firefox."; line; pause_once; return; }

  # GNOME proxy (best-effort)
  gnome_proxy_set || true

  # Firefox profiles: apply SOCKS proxy
  firefox_set_proxy_all

  ok "Proxy set."
  line
  pause_once
}
proxy_unset_all() {
  header
  printf "%s\n" "$(bold)Removing Browser Proxy$(reset)"
  line

  gnome_proxy_unset || true

  # Remove Firefox proxy prefs keys
  local d
  while IFS= read -r d; do
    [ -z "${d:-}" ] && continue
    local f="$d/user.js" p="$d/prefs.js"
    if [ -f "$f" ]; then grep -v -E 'network\.proxy\.(type|socks"|socks_port|no_proxies_on|socks_remote_dns)' "$f" 2>/dev/null > "$f.tmp" || true; mv "$f.tmp" "$f" || true; fi
    if [ -f "$p" ]; then grep -v -E 'network\.proxy\.(type|socks"|socks_port|no_proxies_on|socks_remote_dns)' "$p" 2>/dev/null > "$p.tmp" || true; mv "$p.tmp" "$p" || true; fi
  done < <(firefox_profiles_dirs || true)

  ok "Proxy removed."
  line
  pause_once
}
proxy_status() {
  header
  printf "%s\n" "$(bold)Proxy Status & Test (Firefox)$(reset)"
  line
  printf "Target SOCKS: %s:%s\n\n" "${BTOR_SOCKS_HOST}" "${BTOR_SOCKS_PORT}"

  # Ask to start tor
  ensure_tor_running_with_prompt || true

  # Ensure Firefox present then open test page
  if install_firefox_if_missing; then
    # Make sure Firefox has proxy applied before opening
    firefox_set_proxy_all
    nohup firefox "http://check.torproject.org/" >/dev/null 2>&1 &
    ok "Opened check.torproject.org in Firefox with proxy."
  else
    err "Firefox could not be installed automatically."
    print_manual_proxy_steps
  fi
  line
  pause_once
}

# -----------------------------
# Tor Route Test
# -----------------------------
route_test() {
  header
  printf "%s\n" "$(bold)Tor Route Test$(reset)"
  line

  ensure_tor_running_with_prompt || true
  if ! command -v curl >/dev/null 2>&1; then warn "curl not found. Install curl to run the test."; line; return; fi

  printf "Testing via %s:%s ...\n" "${BTOR_SOCKS_HOST}" "${BTOR_SOCKS_PORT}"
  local okp=0 oka=0
  if curl --socks5-hostname "${BTOR_SOCKS_HOST}:${BTOR_SOCKS_PORT}" -s https://check.torproject.org/ | grep -q "Congratulations. This browser is configured to use Tor"; then okp=1
  elif curl --socks5-hostname "${BTOR_SOCKS_HOST}:${BTOR_SOCKS_PORT_ALT}" -s https://check.torproject.org/ | grep -q "Congratulations. This browser is configured to use Tor"; then oka=1
  fi
  if [ "$okp" -eq 1 ]; then ok "Tor routing OK via ${BTOR_SOCKS_HOST}:${BTOR_SOCKS_PORT}"
  elif [ "$oka" -eq 1 ]; then ok "Tor routing OK via ${BTOR_SOCKS_HOST}:${BTOR_SOCKS_PORT_ALT}"
  else
    err "Not using Tor. Fix tips:"
    printf " - Ensure Tor is active (Start tor.service).\n"
    printf " - Ensure Firefox proxy is applied (we set it automatically in Proxy status).\n"
  fi
  line
  pause_once
}

# -----------------------------
# Menu
# -----------------------------
menu_browser_proxy() {
  while true; do
    header
    printf "%s\n" "$(bold)Browser Proxy (Firefox)$(reset)"
    line
    printf "SOCKS %s:%s\n\n" "${BTOR_SOCKS_HOST}" "${BTOR_SOCKS_PORT}"
    printf "1) Set proxy (Firefox + GNOME)\n"
    printf "2) Remove proxy\n"
    printf "3) Status & open check.torproject.org (Firefox)\n"
    printf "4) Back\n\n"
    local choice; choice="$(read_tty 'Select an option [1-4]: ')"
    case "$choice" in
      1) proxy_set_all ;;
      2) proxy_unset_all ;;
      3) proxy_status ;;
      4) break ;;
      *) err "Invalid option." ;;
    esac
  done
}

menu_once() {
  header
  show_status
  printf "\n%s\n" "$(bold)Options$(reset)"
  line
  printf "1) Start tor.service\n"
  printf "2) Stop tor.service\n"
  printf "3) Enable at boot\n"
  printf "4) Disable at boot\n"
  printf "5) Restart tor.service\n"
  printf "6) Show full status\n"
  printf "7) Browser Proxy (Set/Unset/Status)\n"
  printf "8) Tor Route Test (check.torproject.org)\n"
  printf "9) Quit\n\n"
  local choice; choice="$(read_tty 'Select an option [1-9]: ')"
  printf "\n"
  case "${choice}" in
    1) start_service ;;
    2) stop_service ;;
    3) enable_service ;;
    4) disable_service ;;
    5) restart_service ;;
    6) clear 2>/dev/null || true; header; systemctl --no-pager status "${SERVICE_NAME}" || true; line ;;
    7) menu_browser_proxy ;;
    8) route_test ;;
    9) return 1 ;;
    *) err "Invalid option." ;;
  esac
  return 0
}

menu_loop() { while true; do if ! menu_once; then break; fi; pause_once; done; }

# -----------------------------
# CLI entry
# -----------------------------
usage() {
  cat <<EOF
BTor – Single-file Tor service manager

Usage:
  bash btor.sh install           Install to ${BTOR_HOME} and link ${BTOR_BIN_LINK}
  bash btor.sh uninstall         Remove installation
  bash btor.sh update            Update from ${BTOR_RAW_URL}
  bash btor.sh                   Launch interactive menu

  btor                           After install, launch menu
  btor start|stop|restart|enable|disable|status [--full]
  btor update                    Update installed copy
  btor uninstall                 Uninstall BTor
EOF
}

cli() {
  # If piped without TTY, install then exec btor for interactive run
  if [ -z "${1:-}" ] && [ ! -t 0 ] && [ -r /dev/tty ]; then
    install_self; exec btor
  fi

  local cmd="${1:-}"
  case "$cmd" in
    install)   install_self ;;
    uninstall) uninstall_self ;;
    update)    self_update ;;
    start)     start_service ;;
    stop)      stop_service ;;
    restart)   restart_service ;;
    enable)    enable_service ;;
    disable)   disable_service ;;
    status)
      header
      if [ "${2:-}" = "--full" ]; then systemctl --no-pager status "${SERVICE_NAME}" || true
      else show_status; fi
      line ;;
    -h|--help|help) usage ;;
    "") menu_loop ;;
    *)  err "Unknown command: ${cmd}"; usage; exit 1 ;;
  esac
}

cli "$@"
