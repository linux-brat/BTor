#!/usr/bin/env bash
set -euo pipefail

# BTor - Tor manager with robust UI, proxy helpers, and Tor route test

# -----------------------------
# Config
# -----------------------------
SERVICE_NAME="${BTOR_SERVICE_NAME:-tor.service}"
BTOR_HOME="${BTOR_HOME:-$HOME/.btor}"
BTOR_BIN_LINK="${BTOR_BIN_LINK:-/usr/local/bin/btor}"
BTOR_RAW_URL_DEFAULT="https://raw.githubusercontent.com/linux-brat/BTor/main/btor.sh"
BTOR_RAW_URL="${BTOR_REPO_RAW:-$BTOR_RAW_URL_DEFAULT}"
BTOR_VERSION="${BTOR_VERSION:-0.5.0}"

TOR_BROWSER_DIR_DEFAULT="$HOME/.local/tor-browser"
TOR_BROWSER_DIR="${BTOR_TOR_BROWSER_DIR:-$TOR_BROWSER_DIR_DEFAULT}"

BTOR_SOCKS_HOST="${BTOR_SOCKS_HOST:-127.0.0.1}"
BTOR_SOCKS_PORT="${BTOR_SOCKS_PORT:-9050}"
BTOR_SOCKS_PORT_ALT="${BTOR_SOCKS_PORT_ALT:-9150}" # Tor Browser default

BTOR_FRAME_WIDTH="${BTOR_FRAME_WIDTH:-64}"

# -----------------------------
# UI Helpers
# -----------------------------
bold() { tput bold 2>/dev/null || true; }
reset() { tput sgr0 2>/dev/null || true; }
green() { tput setaf 2 2>/dev/null || true; }
red() { tput setaf 1 2>/dev/null || true; }
yellow() { tput setaf 3 2>/dev/null || true; }
blue() { tput setaf 4 2>/dev/null || true; }
magenta() { tput setaf 5 2>/dev/null || true; }
cyan() { tput setaf 6 2>/dev/null || true; }

term_cols() { tput cols 2>/dev/null || echo 80; }
clamp_width() {
  local w="${1:-$BTOR_FRAME_WIDTH}"
  local cols
  cols="$(term_cols)"
  if [ "$w" -gt $((cols-2)) ]; then w=$((cols-2)); fi
  if [ "$w" -lt 48 ]; then w=48; fi
  echo "$w"
}

center_line() {
  local text="$1"
  local width="$2"
  local len="${#text}"
  if [ "$len" -ge "$width" ]; then
    printf "%s\n" "$text"
    return
  fi
  local pad=$(( (width - len) / 2 ))
  printf "%*s%s%*s\n" "$pad" "" "$text" "$pad" ""
}

box_line() {
  local char="${1:-─}"
  local width="$2"
  printf "%s\n" "$(printf "%${width}s" "" | tr " " "$char")"
}

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
    local line=""
    IFS= read -r line < /dev/tty || true
    printf "%s" "$line"
  else
    printf ""
  fi
}
confirm() {
  local ans
  ans="$(read_tty "${1:-Proceed? [y/N]: }")"
  case "${ans,,}" in
    y|yes) return 0 ;;
    *)     return 1 ;;
  esac
}

# -----------------------------
# Header / Layout
# -----------------------------
header() {
  clear 2>/dev/null || true
  local w
  w="$(clamp_width "$BTOR_FRAME_WIDTH")"
  export BTOR_W="$w"
  box_line "═" "$w"
  center_line "$(cyan)██████╗░████████╗░█████╗░██████╗░$(reset)" "$w"
  center_line "$(cyan)██╔══██╗╚══██╔══╝██╔══██╗██╔══██╗$(reset)" "$w"
  center_line "$(cyan)██████╦╝░░░██║░░░██║░░██║██████╔╝$(reset)" "$w"
  center_line "$(cyan)██╔══██╗░░░██║░░░██║░░██║██╔══██╗$(reset)" "$w"
  center_line "$(cyan)██████╦╝░░░██║░░░╚█████╔╝██║░░██║$(reset)" "$w"
  center_line "$(cyan)╚═════╝░░░░╚═╝░░░░╚════╝░╚═╝░░╚═╝$(reset)" "$w"
  center_line "$(magenta)$(bold)Tor service manager · v${BTOR_VERSION}$(reset)" "$w"
  box_line "─" "$w"
}
line() { box_line "─" "${BTOR_W:-64}"; }

pause_once() {
  if is_tty; then
    read_tty "Press Enter to continue... > " >/dev/null
  fi
}

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
  local pm; pm="$(pm_detect)"
  need_sudo
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

install_or_update_tor() {
  header
  center_line "$(bold)Check Tor$(reset)" "$BTOR_W"
  line
  if tor_cli_installed; then ok "Tor CLI found: $(command -v tor)"; else warn "Tor CLI not found."; fi
  if tor_service_exists; then ok "Tor unit found: ${SERVICE_NAME}"; else warn "Tor unit ${SERVICE_NAME} not found."; fi

  if tor_cli_installed && tor_service_exists; then
    if confirm "Tor installed. Check for updates via package manager? [y/N]: "; then
      case "$(pm_detect)" in
        apt) pm_install tor ;;
        dnf|yum|pacman|zypper) pm_install tor ;;
        *) warn "Unknown package manager. Skipping update." ;;
      esac
    fi
  else
    if confirm "Tor missing/incomplete. Install Tor now? [y/N]: "; then
      case "$(pm_detect)" in
        apt|dnf|yum|pacman|zypper) pm_install tor ;;
        *) warn "Unsupported package manager. Install Tor manually." ;;
      esac
    fi
  fi
  line
}

# -----------------------------
# Tor Browser
# -----------------------------
tor_browser_bin() {
  if [ -x "${TOR_BROWSER_DIR}/tor-browser/Browser/start-tor-browser" ]; then
    printf "%s" "${TOR_BROWSER_DIR}/tor-browser/Browser/start-tor-browser"
    return
  fi
  local cand=""
  cand="$(find "${TOR_BROWSER_DIR}" -type f -name start-tor-browser -perm -111 2>/dev/null | head -n1 || true)"
  if [ -n "$cand" ]; then
    printf "%s" "$cand"
  else
    printf ""
  fi
}
download_tor_browser() {
  header
  center_line "$(bold)Install Tor Browser$(reset)" "$BTOR_W"
  line
  local url
  url="${BTOR_TB_URL:-https://www.torproject.org/dist/torbrowser/13.5.2/tor-browser-linux64-13.5.2_ALL.tar.xz}"
  mkdir -p "${TOR_BROWSER_DIR}" || true
  info "Downloading Tor Browser..."
  if curl -fL --progress-bar "$url" -o "${TOR_BROWSER_DIR}/tor-browser.tar.xz"; then
    info "Extracting..."
    if tar -xf "${TOR_BROWSER_DIR}/tor-browser.tar.xz" -C "${TOR_BROWSER_DIR}"; then
      rm -f "${TOR_BROWSER_DIR}/tor-browser.tar.xz" || true
      ok "Tor Browser ready at ${TOR_BROWSER_DIR}"
    else
      err "Extraction failed."
    fi
  else
    err "Download failed."
  fi
  line
}

# -----------------------------
# Install / Update / Uninstall BTor
# -----------------------------
install_self() {
  header
  center_line "$(bold)Installing BTor$(reset)" "$BTOR_W"
  line
  mkdir -p "${BTOR_HOME}" || true
  if [ -n "${BASH_SOURCE[0]-}" ] && [ -f "${BASH_SOURCE}" ]; then
    cp "${BASH_SOURCE}" "${BTOR_HOME}/btor" || true
  else
    curl -fsSL "${BTOR_RAW_URL}" -o "${BTOR_HOME}/btor" || true
  fi
  chmod +x "${BTOR_HOME}/btor" || true
  need_sudo
  sudo ln -sf "${BTOR_HOME}/btor" "${BTOR_BIN_LINK}" || true
  ok "Installed. Use: btor"
  line
}

uninstall_self() {
  header
  center_line "$(bold)Uninstalling BTor$(reset)" "$BTOR_W"
  line
  need_sudo
  sudo rm -f "${BTOR_BIN_LINK}" || true
  rm -rf "${BTOR_HOME}" || true
  ok "Uninstalled."
  line
}

self_update() {
  header
  center_line "$(bold)Updating BTor$(reset)" "$BTOR_W"
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
  need_sudo
  sudo systemctl start "${SERVICE_NAME}" || true
  if tor_active; then
    ok "Started ${SERVICE_NAME}."
    if confirm "Open Tor Browser now? [y/N]: "; then
      local bin
      bin="$(tor_browser_bin || true)"
      if [ -n "$bin" ]; then
        nohup "$bin" >/dev/null 2>&1 &
        ok "Tor Browser launched."
      else
        warn "Tor Browser not found. Use 'Install Tor Browser' from the menu."
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
  center_line "Service: ${SERVICE_NAME}" "$BTOR_W"
  center_line "Status: ${a} | Boot: ${e}" "$BTOR_W"
}

# -----------------------------
# Browser Proxy helper
# -----------------------------
gnome_proxy_set() {
  if ! command -v gsettings >/dev/null 2>&1; then warn "gsettings not found (GNOME proxy not available)."; return 1; fi
  gsettings set org.gnome.system.proxy mode 'manual' || true
  gsettings set org.gnome.system.proxy.socks host "${BTOR_SOCKS_HOST}" || true
  gsettings set org.gnome.system.proxy.socks port "${BTOR_SOCKS_PORT}" || true
  ok "GNOME SOCKS proxy set to ${BTOR_SOCKS_HOST}:${BTOR_SOCKS_PORT}"
}
gnome_proxy_unset() {
  if command -v gsettings >/dev/null 2>&1; then
    gsettings set org.gnome.system.proxy mode 'none' || true
    ok "GNOME proxy disabled"
  fi
}

firefox_profiles_dirs() {
  local base1="$HOME/.mozilla/firefox"
  local base2="$HOME/snap/firefox/common/.mozilla/firefox"
  if [ -d "$base1" ]; then find "$base1" -maxdepth 1 -type d -name "*.default*" 2>/dev/null; fi
  if [ -d "$base2" ]; then find "$base2" -maxdepth 1 -type d -name "*.default*" 2>/dev/null; fi
}
_ff_write_userjs() {
  local dir="$1" f="$dir/user.js"
  cat > "$f" <<EOF
// Set by BTor
user_pref("network.proxy.type", 1);
user_pref("network.proxy.socks", "${BTOR_SOCKS_HOST}");
user_pref("network.proxy.socks_port", ${BTOR_SOCKS_PORT});
user_pref("network.proxy.no_proxies_on", "localhost");
user_pref("network.proxy.socks_remote_dns", true);
EOF
}
_ff_touch_prefs() {
  local dir="$1" p="$dir/prefs.js"
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
  local found=0
  for d in $(firefox_profiles_dirs || true); do
    found=1
    _ff_write_userjs "$d" || true
    _ff_touch_prefs "$d" || true
    ok "Firefox proxy set for: $d"
  done
  if [ "$found" -eq 0 ]; then
    warn "No Firefox profiles found. Start Firefox once, then re-run."
  else
    warn "Ensure Firefox was fully closed before applying; restart Firefox to use Tor."
  fi
}
firefox_unset_proxy_all() {
  local found=0
  for d in $(firefox_profiles_dirs || true); do
    found=1
    local f="$d/user.js" p="$d/prefs.js"
    if [ -f "$f" ]; then
      grep -v -E 'network\.proxy\.(type|socks"|socks_port|no_proxies_on|socks_remote_dns)' "$f" 2>/dev/null > "$f.tmp" || true
      mv "$f.tmp" "$f" || true
    fi
    if [ -f "$p" ]; then
      grep -v -E 'network\.proxy\.(type|socks"|socks_port|no_proxies_on|socks_remote_dns)' "$p" 2>/dev/null > "$p.tmp" || true
      mv "$p.tmp" "$p" || true
    fi
    ok "Firefox proxy removed for: $d"
  done
  [ "$found" -eq 0 ] && warn "No Firefox profiles found."
}

browser_wrapper_dir="${BTOR_HOME}/proxy-wrappers"
chromium_candidates() {
  cat <<EOF
chromium
chromium-browser
google-chrome
google-chrome-stable
brave
brave-browser
microsoft-edge
microsoft-edge-stable
vivaldi
EOF
}
make_wrapper() {
  local app="$1" bin=""
  bin="$(command -v "$app" 2>/dev/null || true)"
  [ -z "$bin" ] && return 1
  mkdir -p "$browser_wrapper_dir" || true
  local wrapper="${browser_wrapper_dir}/${app}"
  cat > "$wrapper" <<EOF
#!/usr/bin/env bash
exec "$bin" --proxy-server="socks5://${BTOR_SOCKS_HOST}:${BTOR_SOCKS_PORT}" --host-resolver-rules="MAP * ~NOTFOUND , EXCLUDE localhost" "\$@"
EOF
  chmod +x "$wrapper" || true
  ok "Wrapper: $wrapper"
}
remove_wrappers() { rm -rf "$browser_wrapper_dir" 2>/dev/null || true; }

proxy_set_all() {
  header
  center_line "$(bold)Setting Browser Proxy$(reset)" "$BTOR_W"
  line
  gnome_proxy_set || true
  firefox_set_proxy_all
  local any=0
  while read -r c; do
    [ -z "${c:-}" ] && continue
    if command -v "$c" >/dev/null 2>&1; then
      make_wrapper "$c" && any=1 || true
    fi
  done <<EOF
$(chromium_candidates)
EOF
  if [ "$any" -eq 1 ]; then
    center_line "Use wrappers from: ${browser_wrapper_dir}" "$BTOR_W"
  else
    warn "No Chromium-family browsers detected for wrappers."
  fi
  line
}

proxy_unset_all() {
  header
  center_line "$(bold)Removing Browser Proxy$(reset)" "$BTOR_W"
  line
  gnome_proxy_unset || true
  firefox_unset_proxy_all
  remove_wrappers
  ok "Proxy settings removed."
  line
}

proxy_status() {
  header
  center_line "$(bold)Proxy Status$(reset)" "$BTOR_W"
  line
  center_line "Target: ${BTOR_SOCKS_HOST}:${BTOR_SOCKS_PORT}" "$BTOR_W"
  printf "\n"
  if command -v gsettings >/dev/null 2>&1; then
    local mode host port
    mode="$(gsettings get org.gnome.system.proxy mode 2>/dev/null || echo unknown)"
    host="$(gsettings get org.gnome.system.proxy.socks host 2>/dev/null || echo '')"
    port="$(gsettings get org.gnome.system.proxy.socks port 2>/dev/null || echo '')"
    center_line "GNOME: mode=$mode socks=${host//\'/}:${port}" "$BTOR_W"
  else
    center_line "GNOME: gsettings not available" "$BTOR_W"
  fi
  printf "\n"
  local any=0
  for d in $(firefox_profiles_dirs || true); do
    any=1
    center_line "Firefox profile: $d" "$BTOR_W"
    if [ -f "$d/user.js" ]; then
      grep -E 'network\.proxy\.(type|socks|socks_port|socks_remote_dns)' "$d/user.js" 2>/dev/null | sed 's/^/  /' || true
    else
      center_line "  user.js not present" "$BTOR_W"
    fi
    printf "\n"
  done
  [ "$any" -eq 0 ] && center_line "Firefox: no profiles detected" "$BTOR_W"
  printf "\n"
  center_line "Wrappers dir: $browser_wrapper_dir" "$BTOR_W"
  ls -1 "$browser_wrapper_dir" 2>/dev/null | sed 's/^/  /' || center_line "(no wrappers)" "$BTOR_W"
  line
}

# -----------------------------
# Tor Route Test
# -----------------------------
route_test() {
  header
  center_line "$(bold)Tor Route Test$(reset)" "$BTOR_W"
  line
  if ! tor_active; then
    warn "Tor service is not active. Start it first."
    line
    return
  fi
  if ! command -v curl >/dev/null 2>&1; then
    warn "curl not found. Install curl to run the test."
    line
    return
  fi
  center_line "Testing via ${BTOR_SOCKS_HOST}:${BTOR_SOCKS_PORT} ..." "$BTOR_W"
  local okp=0 oka=0
  if curl --socks5-hostname "${BTOR_SOCKS_HOST}:${BTOR_SOCKS_PORT}" -s https://check.torproject.org/ | grep -q "Congratulations. This browser is configured to use Tor"; then
    okp=1
  elif curl --socks5-hostname "${BTOR_SOCKS_HOST}:${BTOR_SOCKS_PORT_ALT}" -s https://check.torproject.org/ | grep -q "Congratulations. This browser is configured to use Tor"; then
    oka=1
  fi
  if [ "$okp" -eq 1 ]; then
    ok "Tor routing OK via ${BTOR_SOCKS_HOST}:${BTOR_SOCKS_PORT}"
  elif [ "$oka" -eq 1 ]; then
    ok "Tor routing OK via ${BTOR_SOCKS_HOST}:${BTOR_SOCKS_PORT_ALT}"
  else
    err "Not using Tor. Fix tips:"
    printf "%s\n" " - Ensure Tor is active (Start tor.service)."
    printf "%s\n" " - Ensure browser uses SOCKS ${BTOR_SOCKS_HOST}:${BTOR_SOCKS_PORT} (or 9150 for Tor Browser)."
    printf "%s\n" " - Firefox: fully close before applying proxy; then restart."
    printf "%s\n" " - Chromium: launch using wrapper from ${browser_wrapper_dir}."
  fi
  line
}

# -----------------------------
# Menu
# -----------------------------
menu_browser_proxy() {
  while true; do
    header
    center_line "$(bold)Browser Proxy$(reset)" "$BTOR_W"
    line
    center_line "SOCKS ${BTOR_SOCKS_HOST}:${BTOR_SOCKS_PORT}" "$BTOR_W"
    printf "\n"
    center_line "1) Set proxy (GNOME + Firefox + wrappers)" "$BTOR_W"
    center_line "2) Remove proxy" "$BTOR_W"
    center_line "3) Status" "$BTOR_W"
    center_line "4) Back" "$BTOR_W"
    printf "\n"
    local choice
    choice="$(read_tty "Select an option [1-4]: ")"
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
  printf "\n"
  center_line "$(bold)Options$(reset)" "$BTOR_W"
  line
  center_line "1) Start tor.service" "$BTOR_W"
  center_line "2) Stop tor.service" "$BTOR_W"
  center_line "3) Enable at boot" "$BTOR_W"
  center_line "4) Disable at boot" "$BTOR_W"
  center_line "5) Restart tor.service" "$BTOR_W"
  center_line "6) Show full status" "$BTOR_W"
  center_line "7) Browser Proxy (Set/Unset/Status)" "$BTOR_W"
  center_line "8) Tor Route Test (check.torproject.org)" "$BTOR_W"
  center_line "9) Quit" "$BTOR_W"
  printf "\n"
  local choice
  choice="$(read_tty "Select an option [1-9]: ")"
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

menu_loop() {
  while true; do
    if ! menu_once; then break; fi
    pause_once
  done
}

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
  # If invoked via pipe without TTY: install then re-exec as btor
  if [ -z "${1:-}" ] && [ ! -t 0 ] && [ -r /dev/tty ]; then
    install_self
    exec btor
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
      if [ "${2:-}" = "--full" ]; then
        systemctl --no-pager status "${SERVICE_NAME}" || true
      else
        show_status
      fi
      line
      ;;
    -h|--help|help) usage ;;
    "") menu_loop ;;
    *)  err "Unknown command: ${cmd}"; usage; exit 1 ;;
  esac
}

cli "$@"
