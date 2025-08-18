#!/bin/bash
# tor-support.sh - Interactive Tor service manager

SERVICE="tor.service"

while true; do
    clear
    echo "============================="
    echo "   Tor Service Manager"
    echo "============================="
    echo "1) Status"
    echo "2) Start"
    echo "3) Stop"
    echo "4) Enable at boot"
    echo "5) Disable at boot"
    echo "6) Exit"
    echo "-----------------------------"
    read -p "Choose an option [1-6]: " choice

    case $choice in
        1)
            systemctl status "$SERVICE" --no-pager
            ;;
        2)
            sudo systemctl start "$SERVICE" && echo "Tor service started."
            ;;
        3)
            sudo systemctl stop "$SERVICE" && echo "Tor service stopped."
            ;;
        4)
            sudo systemctl enable "$SERVICE" && echo "Tor service enabled at boot."
            ;;
        5)
            sudo systemctl disable "$SERVICE" && echo "Tor service disabled at boot."
            ;;
        6)
            echo "Exiting..."
            exit 0
            ;;
        *)
            echo "Invalid option. Try again."
            ;;
    esac

    echo ""
    read -p "Press Enter to continue..."
done
