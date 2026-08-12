#!/bin/bash
# Baut die Swift-Package-Executable und verpackt sie als doppelklickbares
# YamahaAVRControl.app-Bundle im Projekt-Root.
#
# Danach:
#   1. YamahaAVRControl.app nach /Applications ziehen.
#   2. Einmal per Doppelklick öffnen (macOS fragt ggf. wegen "nicht verifizierter
#      Entwickler" nach – im Kontextmenü "Öffnen" wählen).
#   3. Systemeinstellungen > Allgemein > Anmeldeobjekte > "+" > YamahaAVRControl.app
#      hinzufügen, damit die App automatisch im Hintergrund startet.

set -euo pipefail
cd "$(dirname "$0")/.."

echo "Baue Release-Binary..."
swift build -c release

APP_NAME="YamahaAVRControl.app"
rm -rf "$APP_NAME"
mkdir -p "$APP_NAME/Contents/MacOS"

cp ".build/release/YamahaAVRControl" "$APP_NAME/Contents/MacOS/YamahaAVRControl"
cp "Scripts/Info.plist" "$APP_NAME/Contents/Info.plist"

echo "Fertig: $APP_NAME"
echo "Weiter mit: open \"$APP_NAME\" oder ins Applications-Verzeichnis verschieben."
