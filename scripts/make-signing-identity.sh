#!/usr/bin/env bash
# One-time: create a stable self-signed code-signing identity "Voicely Self-Signed"
# in the login keychain. Voicely is signed with this so its designated requirement
# is cert-based (identifier + certificate leaf), which macOS TCC keeps across
# rebuilds — unlike ad-hoc signing, which drops Accessibility/Input-Monitoring
# grants on every reinstall.
#
# macOS ships LibreSSL (no openssl `-legacy`), and `security import` rejects
# empty-password PKCS12, so we use a password + SHA1-3DES PBE for compatibility.
# On first `codesign`, macOS prompts once for keychain access — click "Always Allow".
set -euo pipefail
NAME="Voicely Self-Signed"
PASS="voicelypass"
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT

cat > "$tmp/cert.conf" <<'EOF'
[req]
distinguished_name=dn
x509_extensions=v3
prompt=no
[dn]
CN=Voicely Self-Signed
[v3]
basicConstraints=critical,CA:false
keyUsage=critical,digitalSignature
extendedKeyUsage=critical,codeSigning
EOF

openssl req -x509 -newkey rsa:2048 -sha256 -nodes -days 3650 \
  -keyout "$tmp/key.pem" -out "$tmp/cert.pem" -config "$tmp/cert.conf"
openssl pkcs12 -export -out "$tmp/id.p12" -inkey "$tmp/key.pem" -in "$tmp/cert.pem" \
  -name "$NAME" -passout "pass:$PASS" -keypbe PBE-SHA1-3DES -certpbe PBE-SHA1-3DES -macalg SHA1
security import "$tmp/id.p12" -k ~/Library/Keychains/login.keychain-db -P "$PASS" -T /usr/bin/codesign -A

echo "Imported identity '$NAME':"
security find-identity -p codesigning | grep -i voicely || echo "(not found — check keychain)"
