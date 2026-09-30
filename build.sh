#!/bin/zsh
# Builds WizBar.app. Pass --install to copy it into /Applications.
set -euo pipefail
cd "$(dirname "$0")"

swift build -c release
APP=build/WizBar.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp .build/release/WizBar "$APP/Contents/MacOS/WizBar"
cp Info.plist "$APP/Contents/Info.plist"
codesign --force --sign - "$APP"
echo "Built $APP"

if [[ "${1:-}" == "--install" ]]; then
    pkill -x WizBar || true
    rm -rf /Applications/WizBar.app
    cp -R "$APP" /Applications/
    echo "Installed to /Applications/WizBar.app"
fi
