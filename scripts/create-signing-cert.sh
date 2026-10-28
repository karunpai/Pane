#!/bin/zsh
# One-time setup: creates a self-signed code-signing certificate named "Pane Local Signing"
# in your login keychain. Builds signed with a stable identity keep their Accessibility
# permission across updates (ad-hoc builds lose it every time).
set -euo pipefail

NAME="Pane Local Signing"
KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"

if security find-identity -p codesigning 2>/dev/null | grep -qF "\"$NAME\""; then
  echo "\"$NAME\" already exists in your keychain — nothing to do."
  exit 0
fi

# Prefer the system LibreSSL: its PKCS#12 output is what `security import` expects.
OPENSSL=/usr/bin/openssl
[[ -x "$OPENSSL" ]] || OPENSSL="$(command -v openssl)"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

cat > "$WORK/cert.cnf" <<CNF
[ req ]
distinguished_name = dn
x509_extensions    = ext
prompt             = no

[ dn ]
CN = $NAME

[ ext ]
basicConstraints     = critical, CA:false
keyUsage             = critical, digitalSignature
extendedKeyUsage     = critical, codeSigning
subjectKeyIdentifier = hash
CNF

echo "==> Generating certificate (valid 10 years)"
"$OPENSSL" req -x509 -newkey rsa:2048 -nodes -sha256 -days 3650 \
  -config "$WORK/cert.cnf" -keyout "$WORK/key.pem" -out "$WORK/cert.pem" 2>/dev/null

# Random throwaway password for the transfer file; legacy PBE so `security import` accepts it.
P12_PASS="$("$OPENSSL" rand -hex 16)"
LEGACY=()
if "$OPENSSL" version | grep -q '^OpenSSL 3'; then LEGACY=(-legacy); fi
"$OPENSSL" pkcs12 -export "${LEGACY[@]}" -inkey "$WORK/key.pem" -in "$WORK/cert.pem" \
  -name "$NAME" -out "$WORK/identity.p12" -passout "pass:$P12_PASS"

echo "==> Importing into login keychain (macOS may ask for your password)"
security import "$WORK/identity.p12" -k "$KEYCHAIN" -P "$P12_PASS" -T /usr/bin/codesign

if security find-identity -p codesigning | grep -qF "\"$NAME\""; then
  echo "==> Done. \"$NAME\" is ready; scripts/build-app.sh will use it automatically."
  echo "    It's listed as not trusted — that's expected for a self-signed cert and fine for local signing."
  echo "    After the first signed install, grant Accessibility to Pane once more; it then sticks across updates."
else
  echo "error: import finished but the identity isn't visible to codesign" >&2
  exit 1
fi
