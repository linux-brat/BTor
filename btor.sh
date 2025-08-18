#!/bin/bash
# 🚀 Brat Tor Manager (BTOR)
# Simple Tor manager that works via curl | bash

set -euo pipefail

# --- ASCII Banner ---
show_banner() {
cat << 'EOF'
██████  ████████  ██████  ██████  
██   ██    ██    ██    ██ ██   ██ 
██████     ██    ██    ██ ██████  
██   ██    ██    ██    ██ ██   ██ 
██   ██    ██     ██████  ██   ██ 

 Brat Tor Manager (BTOR)
EOF
}

# --- Tor Actions ---
cmd_action() {
    case "$1" in
        start) echo "[+] Starting Tor..."; sudo systemctl start tor.service ;;
        stop) echo "[+] Stopping Tor..."; sudo systemctl stop tor.service ;;
        restart) echo "[+] Restarting Tor..."; sudo systemctl restart tor.service ;;
        enable) echo "[+] Enabling Tor autostart..."; sudo systemctl enable tor.service ;;
        disable) echo "[+] Disabling Tor autostart..."; sudo systemctl disable tor.service ;;
        status) echo "[+] Tor Status:"; systemctl status tor.service --no-pager ;;
        *) echo "Usage: btor {start|stop|restart|enable|disable|status}"; exit 1 ;;
    esac
}

# --- Tor Control Menu ---
tor_menu() {
    while true; do
        clear
        show_banner
        echo "[ Tor Service Status ]"
        if systemctl is-active --quiet tor.service; then
            echo "✅ Tor is running"
        else
            echo "❌ Tor is stopped"
        fi
        echo "----------------------------------"
        echo "1) Start Tor"
        echo "2) Stop Tor"
        echo "3) Restart Tor"
        echo "4) Enable Tor (autostart)"
        echo "5) Disable Tor (no autostart)"
        echo "6) Status"
        echo "7) Exit"
        echo -n "Choose an option: "
        read -r choice
        case $choice in
            1) cmd_action start; sleep 1 ;;
            2) cmd_action stop; sleep 1 ;;
            3) cmd_action restart; sleep 1 ;;
            4) cmd_action enable; sleep 1 ;;
            5) cmd_action disable; sleep 1 ;;
            6) cmd_action status; read -n 1 -s -r -p "Press any key to continue..." ;;
            7) exit 0 ;;
            *) echo "Invalid option"; sleep 1 ;;
        esac
    done
}

# --- Main Execution ---
if [ $# -gt 0 ]; then
    cmd_action "$1"
    exit 0
else
    tor_menu
fi
