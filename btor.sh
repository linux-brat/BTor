#!/usr/bin/env bash
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

# --- Tor Control Menu ---
tor_menu() {
    while true; do
        clear
        show_banner
        echo "[ Tor Service Status ]"
        if systemctl is-active --quiet tor; then
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
            1) sudo systemctl start tor || true ;;
            2) sudo systemctl stop tor || true ;;
            3) sudo systemctl restart tor || true ;;
            4) sudo systemctl enable tor || true ;;
            5) sudo systemctl disable tor || true ;;
            6) systemctl status tor --no-pager || true; read -n 1 -s -r -p "Press any key to continue..." ;;
            7) exit 0 ;;
            *) echo "Invalid option"; sleep 1 ;;
        esac
    done
}

# --- Main Execution ---
tor_menu
