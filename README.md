# WIFI-ZERO
### Advanced Wireless Disruption & Area-Denial Framework

```text
 __       __ _____ ________  __        ________ _______  _______   ______  
|  \  _  |  \     \        \|  \      |        \       \|       \ /      \ 
| $$ / \ | $$  \$$| $$$$$$$$ \$$______ \$$$$$$$$ $$$$$$$\ $$$$$$$\  $$$$$$\
| $$/  $\| $$ |  \| $$__    |  \|      \ /    $$ $$__| $$ $$__| $$ $$  | $$
| $$  $$$\ $$ | $$| $$  \   | $$ \$$$$$$/  $$$$_ $$    $$ $$    $$ $$  | $$
| $$ $$\$$\$$ | $$| $$$$$   | $$       |  $$    \$$$$$$$\ $$$$$$$\ $$  | $$
| $$$$  \$$$$ | $$| $$      | $$       | $$_____| $$  | $$ $$  | $$ $$__/ $$
| $$$    \$$$ | $$| $$      | $$       | $$     \ $$  | $$ $$  | $$\$$    $$
 \$$      \$$  \$$ \$$       \$$        \$$$$$$$$\$$   \$$\$$   \$$ \$$$$$$ 
```

---

## ⚠️ Disclaimer
**WIFI-ZERO is an offensive security tool designed STRICTLY for authorized Red-Team engagements, academic research, and wireless penetration testing. Unauthorized deployment against networks you do not own or have explicit permission to test is illegal.**

---

## 🛠 Modular Architecture Breakdown

The `WIFI-ZERO` suite utilizes an interconnected 8-module pipeline that dynamically adapts to target environments to ensure maximum disruption while maintaining deep operational persistence.

*   **Module 1: RF-Environment Engine (Interface Dominance)**
    Forces your target wireless interface into Monitor Mode while initiating a background watchdog loop. Suppresses `wpa_supplicant` and `NetworkManager` to prevent OS-level interference.

*   **Module 2: Tactical Recon & Target Pinpointing**
    A `tput` powered UI that leverages `airodump-ng` in the background to capture surrounding RF data. Extracts Access Points based on the highest active client counts (Smart-Targeting).

*   **Module 3: The Black-Out Engine (Multi-Vector Deauth)**
    The core injection system. Executes destructive `mdk4` floods and multi-threaded `aireplay-ng` injections.

*   **Module 4: The Channel-Lock & Persistence Guardian**
    Protects injection threads. Enforces "Deep Locking" via `iwconfig` and `systemctl mask` to prevent channel drift. Runs a background Keep-Alive process to instantly resurrect any dropped attack threads.

*   **Module 5: SSID Overlord (Mass Beacon Flooding)**
    Executes Mass Beacon Floods via `mdk4`. Capable of generating 1000+ random networks to clutter scanners, or dynamically cloning real networks from Module 2's CSV data to cause client confusion.

*   **Module 6: Karma AP (Evil Twin)**
    Automatically spawns a virtual interface (`mon0_ap`), configures `hostapd` and `dnsmasq`, and broadcasts a rogue access point parallel to your offensive injections.

*   **Module 7: The "Area-Denial" Rotation Loop**
    A "Sweep-and-Strike" protocol. Sorts all discovered APs by signal strength (RSSI) and systematically rotates targeted `mdk4` disruption across every network within range for total localized area denial. *(Supports simultaneous background SSID cloning).*

*   **Module 8: The Forensic Eraser & Exit Protocol**
    The Kill-Switch (`Ctrl+C` / `Ctrl+\`). Securely shreds all `/tmp/` logs and CSVs, instantly tears down virtual interfaces, restores original hardware MAC addresses, and unmasks/restarts standard OS networking services.

---

## 📦 Dependencies & Installation

WIFI-ZERO operates on native Bash but requires a standard suite of wireless auditing tools to be present on your host.

### Required Packages:
*   `aircrack-ng` (airodump-ng, aireplay-ng, airmon-ng)
*   `mdk4`
*   `macchanger`
*   `hostapd`
*   `dnsmasq`

### Deployment:
```bash
git clone https://github.com/your-repo/WIFI-ZERO.git
cd WIFI-ZERO
chmod +x deauth_engine.sh
sudo ./deauth_engine.sh <interface>
```

---

## 🎯 Usage Guide

### The Area-Denial Mode
When initiating the engine, proceed through the **Recon Phase** to allow the script to capture nearby targets. Once complete, select **Attack Vector D**.
The Area-Denial loop will sort the targets by RSSI (closest first). You will be prompted:
`Enable simultaneous SSID Overlord (Mass Beacon Flood) during rotation? [y/N]`
Selecting `Y` will run a simultaneous cloned beacon flood in the background while the main thread systematically locks onto each channel and injects deauthentication packets for 30 seconds before moving to the next.

### The Nuclear Option
Select **Nuclear Option** from the execution menu. This does not require prior recon. The engine will rapidly hop across 23 standard 2.4GHz and 5GHz channels, firing 50 broadcast deauth packets per second on every frequency.

### The Kill-Switch
At any point during the operation, press `Ctrl+C` or `Ctrl+\`. The Forensic Eraser (Module 8) will instantly intercept the signal, kill all rogue APs, stop injection threads, shred capture data, and restore your interface.

---

## 📡 Hardware Compatibility

For `WIFI-ZERO` to function correctly, your wireless network adapter **MUST** support Monitor Mode and Packet Injection.

**Recommended Chipsets:**
*   **Atheros** (AR9271, AR9287) - *Highly Recommended*
*   **Ralink** (RT3070, RT5370)
*   **Realtek** (RTL8812AU) - *Requires specific patched driver for stable injection*

*Note: While Module 6 (Karma AP) attempts to spin up a secondary virtual interface using `iw dev interface add`, some chipsets/drivers cannot simultaneously support AP and Monitor mode. If Evil Twin fails to broadcast, use a secondary physical USB adapter.*"# let-me-kick-2" 
