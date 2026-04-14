# KRYPTON DEAUTH-COMMANDER v2.0

A comprehensive, professional-grade Deauthentication & RF-Disruption Dashboard built entirely in Bash, optimized for Intel BE200/AX211 (iwlwifi) chipsets on Samsung Book 5 Pro 360.

## Features

### 12-Module Command System

1. **Auto-Monitor & MAC Spoof** - Automated monitor mode setup with MAC randomization
2. **Recon Scan** - Background airodump-ng scanning with CSV output
3. **Target Selector** - Intelligent target selection from scan results
4. **Targeted Deauth** - Multi-threaded deauthentication attacks
5. **MDK4 Chaos** - High-speed disassociation attacks (Intel-optimized)
6. **Area-Denial** - Nuclear option with full-spectrum attacks
7. **SSID Overlord** - Beacon flood with 1000+ fake SSIDs
8. **Sweep-and-Strike** - Systematic rotation attacks
9. **Channel Lock Guardian** - Watchdog for interface stability
10. **Karma Rogue AP** - Evil Twin deployment
11. **Forensic Erasure** - Complete evidence destruction
12. **Exit & Restore** - Clean system restoration

## Requirements

### System Dependencies
- Linux with root privileges
- Intel BE200/AX211 wireless chipset (iwlwifi driver)
- Aircrack-ng suite
- macchanger
- mdk4
- iw wireless tools
- hostapd
- dnsmasq

### Installation

```bash
# Install dependencies (Ubuntu/Debian)
sudo apt update
sudo apt install aircrack-ng macchanger mdk4 iw hostapd dnsmasq

# Make script executable
chmod +x krypton-deauth-commander.sh
```

## Usage

### Basic Operation

```bash
# Run as root
sudo ./krypton-deauth-commander.sh
```

### Module Workflow

1. **Start with Module 1** - Enable monitor mode and spoof MAC
2. **Run Module 2** - Scan for targets
3. **Use Module 3** - Select specific targets
4. **Choose attack module** (4-10) based on objective
5. **Module 11** - Clean up evidence when done
6. **Module 0** - Restore system to original state

### Intel-Specific Optimizations

- **Channel Management**: Uses `iw dev` instead of deprecated methods
- **Driver Stability**: Self-healing mechanisms for iwlwifi crashes
- **Injection Optimization**: MDK4 prioritized for Intel chipsets
- **Frequency Support**: Full 2.4/5/6GHz spectrum coverage

## Safety Features

### Self-Healing
- Automatic interface recovery on driver crashes
- Channel drift detection and correction
- Background process monitoring and restart

### Forensic Protection
- Complete evidence destruction (Module 11)
- Secure file shredding with multiple passes
- Process termination and cleanup

### System Restoration
- Original MAC address restoration
- NetworkManager restart
- Interface mode reset to managed

## Attack Modules Details

### Module 4: Targeted Deauth
- Multi-threaded injection loops
- Automatic restart on failure
- Intel-optimized channel setting

### Module 5: MDK4 Chaos
- High-speed packet injection
- Primary attack method for Intel cards
- Continuous operation with healing

### Module 6: Area-Denial
- Full spectrum channel hopping
- 2.4/5/6GHz coverage
- Broadcast deauthentication

### Module 7: SSID Overlord
- 1000+ fake SSID generation
- Beacon flood attack
- Device Wi-Fi list choking

### Module 10: Karma Rogue AP
- Evil Twin deployment
- DHCP server configuration
- Captive portal capability

## Configuration

### Interface Detection
Script auto-detects wireless interface using `iw dev`.

### Logging
- Scan results: `/tmp/scan.csv`
- Log directory: `/tmp/krypton_logs/`
- Temporary files: `/tmp/`

### MAC Management
- Original MAC stored for restoration
- Random MAC generation with macchanger
- Automatic restoration on exit

## Troubleshooting

### Common Issues

1. **Monitor Mode Fails**
   - Check if interface supports monitor mode
   - Ensure no conflicting processes
   - Try manual: `iw dev wlan0 set type monitor`

2. **Injection Fails**
   - Verify chipset supports packet injection
   - Check driver version compatibility
   - Use MDK4 (Module 5) for Intel chipsets

3. **Channel Errors**
   - Use Intel-safe channel setting
   - Check regulatory domain settings
   - Verify band support

### Debug Mode
Enable verbose output by modifying script variables at top of file.

## Legal Disclaimer

This tool is for educational purposes and authorized security testing only. Users are responsible for ensuring compliance with local laws and regulations. Unauthorized wireless network attacks are illegal in most jurisdictions.

## Technical Specifications

### Supported Hardware
- Intel BE200
- Intel AX211
- Intel AX200/210
- Other iwlwifi-compatible chipsets

### Frequency Bands
- 2.4GHz: Channels 1-14
- 5GHz: Channels 36-165
- 6GHz: Channels 1-225 (where supported)

### Attack Vectors
- Deauthentication frames
- Disassociation frames
- Beacon flooding
- Evil Twin AP
- Karma attacks

## Version History

### v2.0
- Intel BE200/AX211 optimization
- Self-healing mechanisms
- Enhanced UI with tput
- 6GHz band support
- Improved error handling

### v1.0
- Basic functionality
- 12-module system
- ASCII interface

## Support

For technical support and updates, refer to the documentation and ensure all dependencies are properly installed.

---

**KRYPTON DEAUTH-COMMANDER v2.0** - Professional RF Security Testing Platform
"# shut-up" 
