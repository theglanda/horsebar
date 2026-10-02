#!/bin/bash
# Same as 🐴 → ⚙︎ → Uninstall HorseBar…
set -uo pipefail
pkill -x HorseBar 2>/dev/null; pkill -x SlapBar 2>/dev/null
sudo launchctl bootout system/com.theglanda.slapd 2>/dev/null
sudo rm -rf /Applications/HorseBar.app "/Library/Application Support/HorseBar" \
    "$HOME/Applications/HorseBar.app" "$HOME/Applications/SlapBar.app"
sudo rm -f /Library/LaunchDaemons/com.theglanda.slapd.plist /usr/local/bin/slapd /var/run/slapd.sock /var/log/slapd.log
sudo pkgutil --forget com.theglanda.horsebar.pkg >/dev/null 2>&1
echo "Removed. Your sounds stay in ~/Library/Application Support/HorseBar/Sounds"
