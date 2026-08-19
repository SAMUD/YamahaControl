#!/bin/bash
# Erzeugt ein lokales, selbstsigniertes Code-Signing-Zertifikat ("YamahaAVRControl Dev") und
# importiert es in den Login-Schlüsselbund. Signiert NUR Builds dieser App auf diesem Mac – hat
# keine Auswirkung auf andere Apps oder Systemvertrauenseinstellungen.
#
# Grund: Ohne Signatur behandelt macOS jeden Neubau als "neue" App, wodurch einmal erteilte
# Berechtigungen (z. B. "Eingabeüberwachung" für die Lautstärke-Tastenkombination) nach jedem
# Rebuild wieder ungültig werden. Mit einer stabilen Signatur-Identität bleiben sie erhalten.
#
# Danach übernimmt build_app.sh das Signieren automatisch bei jedem Build.

set -euo pipefail
CERT_NAME="YamahaAVRControl Dev"

if security find-certificate -c "$CERT_NAME" >/dev/null 2>&1; then
    echo "Zertifikat \"$CERT_NAME\" existiert bereits, nichts zu tun."
    exit 0
fi

WORKDIR="$(mktemp -d)"
trap 'rm -rf "$WORKDIR"' EXIT

cat > "$WORKDIR/codesign.cnf" << EOF
[req]
distinguished_name = dn
x509_extensions = v3_ext
prompt = no
[dn]
CN = $CERT_NAME
[v3_ext]
keyUsage = critical, digitalSignature
extendedKeyUsage = critical, codeSigning
basicConstraints = critical, CA:false
EOF

openssl req -x509 -newkey rsa:2048 -keyout "$WORKDIR/key.pem" -out "$WORKDIR/cert.pem" \
    -days 3650 -nodes -config "$WORKDIR/codesign.cnf"

PASS="$(openssl rand -base64 24)"
openssl pkcs12 -export -out "$WORKDIR/cert.p12" -inkey "$WORKDIR/key.pem" -in "$WORKDIR/cert.pem" \
    -passout "pass:$PASS"

security import "$WORKDIR/cert.p12" -k ~/Library/Keychains/login.keychain-db -P "$PASS" \
    -T /usr/bin/codesign -A

echo "Zertifikat \"$CERT_NAME\" erzeugt und in den Login-Schlüsselbund importiert."
echo "./Scripts/build_app.sh signiert Builds ab jetzt automatisch damit."
