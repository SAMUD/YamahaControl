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
mkdir -p "$APP_NAME/Contents/Resources"

cp ".build/release/YamahaAVRControl" "$APP_NAME/Contents/MacOS/YamahaAVRControl"
cp "Scripts/Info.plist" "$APP_NAME/Contents/Info.plist"
cp "Scripts/AppIcon.icns" "$APP_NAME/Contents/Resources/AppIcon.icns"

# Mit einem stabilen (selbstsignierten) Zertifikat signieren, falls eines im Schlüsselbund
# vorhanden ist – ohne das würde macOS jeden Neubau als "neue" App behandeln und Berechtigungen
# wie "Eingabeüberwachung" (für die Lautstärke-Tastenkombination) müssten nach jedem Rebuild neu
# erteilt werden. Zertifikat erzeugen: siehe Scripts/create_dev_cert.sh.
SIGN_IDENTITY="YamahaAVRControl Dev"
if security find-certificate -c "$SIGN_IDENTITY" >/dev/null 2>&1; then
    codesign --force --sign "$SIGN_IDENTITY" "$APP_NAME"
    echo "Signiert mit \"$SIGN_IDENTITY\"."
else
    echo "Hinweis: Kein Zertifikat \"$SIGN_IDENTITY\" gefunden – App bleibt unsigniert."
    echo "Ohne Signatur muss z. B. die Eingabeüberwachungs-Berechtigung nach jedem Rebuild neu erteilt werden."
    echo "Zum Einrichten: ./Scripts/create_dev_cert.sh"
fi

echo "Fertig: $APP_NAME"
echo "Weiter mit: open \"$APP_NAME\" oder ins Applications-Verzeichnis verschieben."
