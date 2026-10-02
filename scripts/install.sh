#!/bin/bash
# Builds the installer and installs it on this Mac (asks for your password).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
"$ROOT/scripts/build-pkg.sh"
VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$ROOT/Resources/Info.plist")

# leftovers from the early dev installs
pkill -x HorseBar 2>/dev/null || true
rm -rf "$HOME/Applications/HorseBar.app" "$HOME/Applications/SlapBar.app"
sudo rm -f /usr/local/bin/slapd

sudo installer -pkg "$ROOT/dist/HorseBar-$VERSION.pkg" -target /
echo "Done. Look for 🐴 in the menu bar."
