#!/usr/bin/env bash
set -euo pipefail

# BTor - Tor manager with first-run setup, styled UI, and browser proxy helper (hardened)

# -----------------------------
# Config (overridable via env)
# -----------------------------
SERVICE_NAME="${BTOR_SERVICE_NAME:-tor.service}"
BTOR_HOME="${BTOR_HOME:-$HOME/.btor}"
BTOR_BIN_LINK="${BTOR_BIN_LINK:-/usr/local/bin/btor}"
BTOR_RAW_URL_DEFAULT="https://raw.githubusercontent.com/linux-brat/BTor/main/btor.sh"
BTOR_RAW_URL="${BTOR_REPO_RAW:-$BTOR_RAW_URL_DEFAULT}"
BTOR_VERSION="${BTOR_VERSION:-0.3.6}"

TOR_BROWSER_DIR_DEFAULT="$HOME/.local/tor-browser"
TOR_BROWSER_DIR="${BTOR_TOR_BROWSER_DIR:-$TOR_BROWSER_DIR_DEFAULT}"

BTOR_SOCKS_HOST="${BTOR_SOCKS_HOST:-127.0.0.1}"
BTOR_SOCKS_PORT="${BTOR_SOCKS_PORT:-9050}"

# UI tuning
BTOR_SPLASH_SPEED="${BTOR_SPLASH_SPEED:-0.02}"   # seconds per line delay
BTOR_SPLASH_PAUSE="${BTOR_SPLASH_PAUSE:-0.05}"   # spinner tick
BTOR_FRAME_WIDTH="${BTOR_FRAME_WIDTH:-64}"

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

need_sudo() { if [[ $EUID -ne 0 ]]; then sudo -v || true; fi; }
have_systemctl() { command -v systemctl >/dev/null 2>&1; }
is_stdin_tty() { [[ -t 0 ]]; }
have_dev_tty() { [[ -r /dev/tty ]]; }

center_line() {
  local text="$1" width="${2:-$BTOR_FRAME_WIDTH}"
  local len=${#text}
  if (( len >= width )); then
    echo "$text"
    return
  fi
  local pad=$(( (width - len) / 2 ))
  printf "%*s%s%*s\n" "$pad" "" "$text" "$pad" ""
}

box_line() {
  local char="${1:-─}" width="${2:-$BTOR_FRAME_WIDTH}"
  printf "%s\n" "$(printf "%${width}s" "" | tr " " "$char")"
}

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

press_enter_once() {
  if is_stdin_tty || have_dev_tty; then
    tty_read "Press Enter to continue..."
  fi
}

sleepf() { sleep "${1:-0.05}"; }

# -----------------------------
# ASCII UI (your block, centered)
# -----------------------------
draw_banner() {
  local w="${1:-$BTOR_FRAME_WIDTH}"
  local lines=(
"$(cyan)██████╗░████████╗░█████╗░██████╗░$(reset)"
"$(cyan)██╔══██╗╚══██╔══╝██╔══██╗██╔══██╗$(reset)"
"$(cyan)██████╦╝░░░██║░░░██║░░██║██████╔╝$(reset)"
"$(cyan)██╔══██╗░░░██║░░░██║░░██║██╔══██╗$(reset)"
"$(cyan)██████╦╝░░░██║░░░╚█████╔╝██║░░██║$(reset)"
"$(cyan)╚═════╝░░░░╚═╝░░░░╚════╝░╚═╝░░╚═╝$(reset)"
  )
  for l in "${lines[@]}"; do
    center_line "$l" "$w"
    sleepf "$BTOR_SPLASH_SPEED"
  done
  center_line "$(magenta)$(bold)Tor service manager · v${BTOR_VERSION}$(reset)" "$w"
}

splash() {
  clear 2>/dev/null || true
  local w="$BTOR_FRAME_WIDTH"
  box_line "═" "$w"
  draw_banner "$w"
  box_line "═" "$w"
  # Loading spinner (no ANSI cursor tricks to avoid weird terminals)
  local spins=('⠋' '⠙' '⠸' '⠼' '⠴' '⠦' '⠇')
  for i in $(seq 1 14); do
    local idx=$(( (i-1) % ${#spins[@]} ))
    center_line "$(bold)${spins[$idx]} Loading...$(reset)" "$w"
    sleepf "$BTOR_SPLASH_PAUSE"
  done
  center_line "$(bold)✔ Ready$(reset)" "$w"
  box_line "─" "$w"
}

header() {
  clear 2>/dev/null || true
  local w="$BTOR_FRAME_WIDTH"
  box_line "═" "$w"
  draw_banner "$w"
  box_line "─" "$w"
}
line() { box_line "─" "$BTOR_FRAME_WIDTH"; }

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
  local pkgs=("$@"); local pm; pm="$(pm_detect)"; need_sudo
  case "$pm" in
    apt) sudo apt-get update -y || true; sudo apt-get install -y "${pkgs[@]}" || true;;
    dnf) sudo dnf install -y "${pkgs[@]}" || true;;
    yum) sudo yum install -y "${pkgs[@]}" || true;;
    pacman) sudo pacman -Sy --noconfirm "${pkgs[@]}" || true;;
    zypper) sudo zypper install -y "${pkgs[@]}" || true;;
    *) warn "Unsupported package manager. Install manually: ${pkgs[*]}"; return 1;;
  esac
}

# -----------------------------
# Tor checks
# -----------------------------
tor_cli_installed() { command -v tor >/dev/null 2>&1; }
tor_service_exists() { systemctl list-unit-files 2>/dev/null | grep -q "^${SERVICE_NAME}\b" || systemctl status "${SERVICE_NAME}" >/dev/null 2>&1; }

install_or_update_tor() {
  info "Checking Tor installation..."
  tor_cli_installed && ok "Tor CLI found: $(command -v tor)" || warn "Tor CLI not found."
  tor_service_exists && ok "Tor unit found: ${SERVICE_NAME}" || warn "Tor unit ${SERVICE_NAME} not found."
  if tor_cli_installed && tor_service_exists; then
    if confirm "Tor installed. Check for updates via package manager? [y/N]: "; then
      case "$(pm_detect)" in
        apt) need_sudo; sudo apt-get update -y || true; sudo apt-get install -y tor || true;;
        dnf|yum|pacman|zypper) pm_install tor || true;;
        *) warn "Unknown package manager. Skipping Tor update.";;
      esac
    fi
    return 0
  fi
  if confirm "Tor missing/incomplete. Install Tor now? [y/N]: "; then
    case "$(pm_detect)" in
      apt|dnf|yum|pacman|zypper) pm_install tor || true;;
      *) warn "Unsupported package manager. Install Tor manually."; return 1;;
    esac
    ok "Tor install attempted."
  else
    warn "Skipped Tor installation."
    return 1
  fi
}

# -----------------------------
# Tor Browser
# -----------------------------
tor_browser_bin() {
  if [[ -x "${TOR_BROWSER_DIR}/tor-browser/Browser/start-tor-browser" ]]; then
    echo "${TOR_BROWSER_DIR}/tor-browser/Browser/start-tor-browser"; return
  fi
  local cand; cand="$(find "${TOR_BROWSER_DIR}" -type f -name start-tor-browser -perm -111 2>/dev/null | head -n1 || true)"
  [[ -n "$cand" ]] && echo "$cand" || echo ""
}
download_tor_browser() {
  local url="https://www.torproject.org/dist/torbrowser/13.5.2/tor-browser-linux64-13.5.2_ALL.tar.xz"
  url="${BTOR_TB_URL:-$url}"
  mkdir -p "${TOR_BROWSER_DIR}" || true
  info "Downloading Tor Browser..."
  curl -fL --progress-bar "$url" -o "${TOR_BROWSER_DIR}/tor-browser.tar.xz" || { warn "Download failed."; return 1; }
  info "Extracting..."
  tar -xf "${TOR_BROWSER_DIR}/tor-browser.tar.xz" -C "${TOR_BROWSER_DIR}" || { warn "Extract failed."; return 1; }
  rm -f "${TOR_BROWSER_DIR}/tor-browser.tar.xz" || true
  ok "Tor Browser ready."
}
install_or_update_tor_browser() {
  info "Checking Tor Browser..."
  local bin; bin="$(tor_browser_bin)"
  if [[ -n "$bin" ]]; then
    ok "Tor Browser found."
    return 0
  fi
  warn "Tor Browser not found."
  if confirm "Download Tor Browser now? [y/N]: "; then
    download_tor_browser || true
  else
    warn "Skipped Tor Browser."
    return 1
  fi
}

# -----------------------------
# First-run
# -----------------------------
first_run_marker() { echo "${BTOR_HOME}/.first_run_done"; }
first_run_needed() { [[ ! -f "$(first_run_marker)" ]]; }
run_first_time_setup() {
  header; center_line "$(bold)First-time setup$(reset)"; line
  mkdir -p "${BTOR_HOME}" || true
  install_or_update_tor || true
  echo
  install_or_update_tor_browser || true
  touch "$(first_run_marker)" || true
  ok "Setup complete."; line
  press_enter_once
}

# -----------------------------
# Install / Update
# -----------------------------
install_self() {
  header; center_line "$(bold)Installing BTor$(reset)"; line
  mkdir -p "${BTOR_HOME}" || true
  if [[ -n "${BASH_SOURCE[0]:-}" && -f "${BASH_SOURCE}" ]]; then
    cp "${BASH_SOURCE}" "${BTOR_HOME}/btor" || true
  else
    curl -fsSL "${BTOR_RAW_URL}" -o "${BTOR_HOME}/btor" || true
  fi
  chmod +x "${BTOR_HOME}/btor" || true
  need_sudo; sudo ln -sf "${BTOR_HOME}/btor" "${BTOR_BIN_LINK}" || true
  ok "Installed. Use: btor"; line
}
uninstall_self() {
  header; center_line "$(bold)Uninstalling BTor$(reset)"; line
  need_sudo; sudo rm -f "${BTOR_BIN_LINK}" || true
  rm -rf "${BTOR_HOME}" || true
  ok "Uninstalled."; line
}
self_update() {
  header; center_line "$(bold)Updating BTor$(reset)"; line
  mkdir -p "${BTOR_HOME}" || true
  curl -fsSL "${BTOR_RAW_URL}" -o "${BTOR_HOME}/btor.new" || true
  chmod +x "${BTOR_HOME}/btor.new" || true
  mv "${BTOR_HOME}/btor.new" "${BTOR_HOME}/btor" || true
  ok "Updated."; line
}

# -----------------------------
# Service ops (with open browser prompt)
# -----------------------------
start_service() {
  need_sudo; sudo systemctl start "${SERVICE_NAME}" || true
  ok "Started ${SERVICE_NAME}."
  if confirm "Open Tor Browser now? [y/N]: "; then
    local bin; bin="$(tor_browser_bin || true)"
    if [[ -n "$bin" ]]; then
      nohup "$bin" >/dev/null 2>&1 &
      ok "Tor Browser launched."
    else
      warn "Tor Browser not found; run Browser setup from main menu."
    fi
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
  [[ "${is_active}" == "active" ]] && a="$(green)active$(reset)" || a="$(red)${is_active:-unknown}$(reset)"
  [[ "${is_enabled}" == "enabled" ]] && e="$(green)enabled$(reset)" || e="$(yellow)${is_enabled:-unknown}$(reset)"
  center_line "Service: ${SERVICE_NAME}"
  center_line "Status: ${a} | Boot: ${e}"
}

# -----------------------------
# Browser Proxy helper
# -----------------------------
# GNOME system proxy
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

# Firefox per-profile (user.js + ensure prefs.js has the same)
firefox_profiles_dirs() {
  local base1="$HOME/.mozilla/firefox" base2="$HOME/snap/firefox/common/.mozilla/firefox"
  for b in "$base1" "$base2"; do [[ -d "$b" ]] && find "$b" -maxdepth 1 -type d -name "*.default*" 2>/dev/null; done
}
_ff_write_userjs() {
  local dir="$1" f="$dir/user.js"
  cat > "$f" <<EOF
// Set by BTor
user_pref("network.proxy.type", 1);
user_pref("network.proxy.socks", "${BTOR_SOCKS_HOST}");
user_pref("network.proxy.socks_port", ${BTOR_SOCKS_PORT});
user_pref("network.proxy.no_proxies_on", "localhost, 127.0.0.1, ::1");
user_pref("network.proxy.socks_remote_dns", true);
EOF
}
_ff_touch_prefs() {
  local dir="$1" p="$dir/prefs.js"
  [[ -f "$p" ]] || touch "$p"
  cp -n "$p" "$dir/prefs.js.bak.$(date +%s)" 2>/dev/null || true
  grep -v -E 'network\.proxy\.(type|socks"|socks_port|no_proxies_on|socks_remote_dns)' "$p" 2>/dev/null > "$p.tmp" || true
  mv "$p.tmp" "$p" || true
  cat >> "$p" <<EOF
user_pref("network.proxy.type", 1);
user_pref("network.proxy.socks", "${BTOR_SOCKS_HOST}");
user_pref("network.proxy.socks_port", ${BTOR_SOCKS_PORT});
user_pref("network.proxy.no_proxies_on", "localhost, 127.0.0.1, ::1");
user_pref("network.proxy.socks_remote_dns", true);
EOF
}
firefox_set_proxy() {
  local d="$1"
  _ff_write_userjs "$d" || true
  _ff_touch_prefs "$d" || true
  ok "Firefox proxy configured in: $d"
}
firefox_unset_proxy() {
  local d="$1" f="$d/user.js" p="$d/prefs.js"
  if [[ -f "$f" ]]; then
    grep -v -E 'network\.proxy\.(type|socks"|socks_port|no_proxies_on|socks_remote_dns)' "$f" 2>/dev/null > "$f.tmp" || true
    mv "$f.tmp" "$f" || true
  fi
  if [[ -f "$p" ]]; then
    grep -v -E 'network\.proxy\.(type|socks"|socks_port|no_proxies_on|socks_remote_dns)' "$p" 2>/dev/null > "$p.tmp" || true
    mv "$p.tmp" "$p" || true
  fi
  ok "Firefox proxy removed in: $d"
}

# Chromium/Chrome/Brave via wrappers (--proxy-server)
browser_wrapper_dir="${BTOR_HOME}/proxy-wrappers"
make_wrapper() {
  local app="$1" bin; bin="$(command -v "$app" || true)"
  [[ -z "$bin" ]] && return 1
  mkdir -p "$browser_wrapper_dir" || true
  local wrapper="${browser_wrapper_dir}/${app}"
  cat > "$wrapper" <<EOF
#!/usr/bin/env bash
exec "$bin" --proxy-server="socks5://${BTOR_SOCKS_HOST}:${BTOR_SOCKS_PORT}" "\$@"
EOF
  chmod +x "$wrapper" || true
  ok "Wrapper created: $wrapper"
}
remove_wrapper() { rm -f "${browser_wrapper_dir}/${1}" 2>/dev/null || true; }

proxy_set_all() {
  header; center_line "$(bold)Setting Browser Proxy$(reset)"; line
  gnome_proxy_set || true
  local found_ff=0
  for d in $(firefox_profiles_dirs 2>/dev/null || true); do
    found_ff=1
    firefox_set_proxy "$d" || true
  done
  [[ $found_ff -eq 0 ]] && warn "No Firefox profiles detected."
  local apps=(chromium google-chrome google-chrome-stable brave brave-browser microsoft-edge-stable vivaldi)
  local created=0
  for a in "${apps[@]}"; do
    if command -v "$a" >/dev/null 2>&1; then
      make_wrapper "$a" && created=1
    fi
  done
  if [[ $created -eq 1 ]]; then
    echo
    center_line "Use the wrapper to launch with proxy:"
    center_line "${browser_wrapper_dir}/chromium (example)"
  else
    warn "Chromium/Chrome/Brave not found or wrappers not created."
  fi
  line
  press_enter_once
}

proxy_unset_all() {
  header; center_line "$(bold)Removing Browser Proxy$(reset)"; line
  gnome_proxy_unset || true
  local found_ff=0
  for d in $(firefox_profiles_dirs 2>/dev/null || true); do
    found_ff=1
    firefox_unset_proxy "$d" || true
  done
  [[ $found_ff -eq 0 ]] && warn "No Firefox profiles detected."
  local apps=(chromium google-chrome google-chrome-stable brave brave-browser microsoft-edge-stable vivaldi)
  for a in "${apps[@]}"; do remove_wrapper "$a" || true; done
  [[ -d "$browser_wrapper_dir" ]] && rmdir "$browser_wrapper_dir" 2>/dev/null || true
  ok "Proxy cleaned."
  line
  press_enter_once
}

proxy_status() {
  header; center_line "$(bold)Proxy Status$(reset)"; line
  center_line "Target: ${BTOR_SOCKS_HOST}:${BTOR_SOCKS_PORT}"
  echo
  if command -v gsettings >/dev/null 2>&1; then
    local mode host port
    mode="$(gsettings get org.gnome.system.proxy mode 2>/dev/null || echo unknown)"
    host="$(gsettings get org.gnome.system.proxy.socks host 2>/dev/null || echo '')"
    port="$(gsettings get org.gnome.system.proxy.socks port 2>/dev/null || echo '')"
    center_line "GNOME: mode=$mode socks=${host//\'/}:${port}"
  else
    center_line "GNOME: gsettings not available"
  fi
  echo
  local any=0
  for d in $(firefox_profiles_dirs 2>/dev/null || true); do
    any=1
    center_line "Firefox profile: $d"
    if [[ -f "$d/user.js" ]]; then
      grep -E 'network\.proxy\.(type|socks|socks_port|socks_remote_dns)' "$d/user.js" 2>/dev/null | sed 's/^/  /' || true
    else
      center_line "  user.js not present"
    fi
    echo
  done
  [[ $any -eq 0 ]] && center_line "Firefox: no profiles detected"
  echo
  center_line "Wrappers dir: $browser_wrapper_dir"
  ls -1 "$browser_wrapper_dir" 2>/dev/null | sed 's/^/  /' || center_line "(no wrappers)"
  line
  press_enter_once
}

browser_proxy_menu() {
  while true; do
    header
    center_line "$(bold)Browser Proxy$(reset)"
    center_line "SOCKS ${BTOR_SOCKS_HOST}:${BTOR_SOCKS_PORT}"
    line
    center_line "1) Set proxy (GNOME + Firefox + wrappers)"
    center_line "2) Remove proxy"
    center_line "3) Status"
    center_line "4) Back"
    echo
    local choice; choice="$(tty_read "Select an option [1-4]: ")"
    case "$choice" in
      1) proxy_set_all ;;
      2) proxy_unset_all ;;
      3) proxy_status ;;
      4) break ;;
      *) err "Invalid option." ;;
    esac
  done
}

# -----------------------------
# Menu
# -----------------------------
menu_once() {
  header
  show_status
  echo
  center_line "$(bold)Options$(reset)"
  line
  center_line "1) Start tor.service"
  center_line "2) Stop tor.service"
  center_line "3) Enable at boot"
  center_line "4) Disable at boot"
  center_line "5) Restart tor.service"
  center_line "6) Show full status"
  center_line "7) Update BTor"
  center_line "8) Browser Proxy (Set/Unset)"
  center_line "9) Quit"
  echo
  local choice; choice="$(tty_read "Select an option [1-9]: ")"
  echo
  case "${choice}" in
    1) start_service ;;
    2) stop_service ;;
    3) enable_service ;;
    4) disable_service ;;
    5) restart_service ;;
    6) clear 2>/dev/null || true; header; systemctl --no-pager status "${SERVICE_NAME}" || true; line ;;
    7) self_update ;;
    8) browser_proxy_menu ;;
    9) return 1 ;;
    *) err "Invalid option." ;;
  esac
  return 0
}

menu_loop() {
  while true; do
    if ! menu_once; then break; fi
    press_enter_once
  done
}

# -----------------------------
# Usage / CLI
# -----------------------------
usage() {
  cat <<EOF
BTor – Single-file Tor service manager

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
  BTOR_SERVICE_NAME              Service name (default: tor.service)
  BTOR_HOME                      Install dir (default: \$HOME/.btor)
  BTOR_BIN_LINK                  Symlink path (default: /usr/local/bin/btor)
  BTOR_REPO_RAW                  Update URL (raw btor.sh)
  BTOR_TOR_BROWSER_DIR           Tor Browser dir (default: \$HOME/.local/tor-browser)
  BTOR_TB_URL                    Tor Browser tarball URL
  BTOR_SOCKS_HOST                SOCKS host (default: 127.0.0.1)
  BTOR_SOCKS_PORT                SOCKS port (default: 9050)
  BTOR_FRAME_WIDTH               UI width (default: ${BTOR_FRAME_WIDTH})
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
