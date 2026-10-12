#!/usr/bin/env bash
# One-time setup, step 1: creates a self-signed code signing identity for Twan Clean and
# exports it as a .p12 file. Step 2 is scripts/setup-signing-keychain.sh <file.p12>.
# A stable identity keeps the app's designated requirement unchanged between builds, so
# macOS keeps Full Disk Access granted across installs.
# Usage: scripts/create-signing-identity.sh <output.p12>
#        (reads the .p12 password from TWANCLEAN_P12_PASSWORD, or asks for it)
set -euo pipefail

OUTPUT="${1:?usage: create-signing-identity.sh <output.p12>}"
NAME="Twan Clean Self-Signed"

if [[ -e "$OUTPUT" ]]; then
  echo "error: $OUTPUT already exists" >&2
  exit 1
fi

p12_password="${TWANCLEAN_P12_PASSWORD:-}"
if [[ -z "$p12_password" ]]; then
  read -r -s -p "Password to protect $OUTPUT: " p12_password
  echo
fi

workdir="$(mktemp -d)"
trap 'rm -rf "$workdir"' EXIT

cat > "$workdir/openssl.cnf" <<EOF
[req]
distinguished_name = dn
x509_extensions = codesign
prompt = no
[dn]
CN = $NAME
[codesign]
basicConstraints = critical, CA:false
keyUsage = critical, digitalSignature
extendedKeyUsage = critical, codeSigning
EOF

openssl req -x509 -newkey rsa:2048 -nodes -days 3650 -config "$workdir/openssl.cnf" \
  -keyout "$workdir/key.pem" -out "$workdir/cert.pem" 2>/dev/null
openssl pkcs12 -export -inkey "$workdir/key.pem" -in "$workdir/cert.pem" -name "$NAME" \
  -out "$OUTPUT" -passout "pass:$p12_password"

echo "Created $OUTPUT with identity \"$NAME\""
echo "Next: scripts/setup-signing-keychain.sh $OUTPUT"
