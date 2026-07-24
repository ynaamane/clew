#!/usr/bin/env bash
set -euo pipefail

CERT_NAME="MeetingScribeDev"
KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"

if security find-identity -v -p codesigning "$KEYCHAIN" 2>/dev/null | grep -q "\"$CERT_NAME\""; then
  echo "$CERT_NAME identity already exists in $KEYCHAIN. Nothing to do."
  security find-identity -v -p codesigning "$KEYCHAIN" | grep "$CERT_NAME"
  exit 0
fi

if openssl version | grep -qi libressl; then
  echo "Error: this script requires real OpenSSL (LibreSSL lacks -addext)." >&2
  echo "Install with: brew install openssl" >&2
  echo "Then re-run with: OPENSSL_BIN=\$(brew --prefix openssl)/bin/openssl $0" >&2
  exit 1
fi
OPENSSL="${OPENSSL_BIN:-openssl}"

TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

echo "Generating self-signed certificate and key..."
"$OPENSSL" req -x509 -newkey rsa:2048 -nodes \
  -keyout "$TMPDIR/key.pem" \
  -out "$TMPDIR/cert.pem" \
  -days 3650 \
  -subj "/CN=$CERT_NAME" \
  -addext "keyUsage=critical,digitalSignature" \
  -addext "extendedKeyUsage=codeSigning"

P12_PASS="$CERT_NAME"
echo "Packaging as PKCS12..."
"$OPENSSL" pkcs12 -export -legacy \
  -macalg sha1 \
  -keypbe PBE-SHA1-3DES \
  -certpbe PBE-SHA1-3DES \
  -out "$TMPDIR/$CERT_NAME.p12" \
  -inkey "$TMPDIR/key.pem" \
  -in "$TMPDIR/cert.pem" \
  -name "$CERT_NAME" \
  -passout "pass:$P12_PASS"

echo "Importing into login keychain..."
security import "$TMPDIR/$CERT_NAME.p12" \
  -k "$KEYCHAIN" \
  -P "$P12_PASS" \
  -A \
  -T /usr/bin/codesign

security set-key-partition-list \
  -S "apple-tool:,apple:,codesign:" \
  -s -k "" "$KEYCHAIN" >/dev/null 2>&1 || true

echo "Trusting the certificate for code signing (user-domain trust only)..."
security add-trusted-cert -p codeSign -k "$KEYCHAIN" "$TMPDIR/cert.pem"

echo
echo "$CERT_NAME identity created and trusted."
echo "Verify with: security find-identity -v -p codesigning | grep $CERT_NAME"
echo
echo "IMPORTANT: this identity is what TCC (Screen/System Audio Recording,"
echo "Microphone) grants are anchored to. Deleting and recreating it changes"
echo "the certificate's hash, which resets every permission grant. Create it"
echo "ONCE per machine and never delete it from the login keychain."
