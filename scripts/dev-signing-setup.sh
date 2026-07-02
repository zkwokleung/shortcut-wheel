#!/bin/bash
# One-time setup: create a stable self-signed code-signing identity so the debug
# build keeps a constant signature across rebuilds. Without it, ad-hoc signing
# changes the binary's hash every build and macOS drops the Input Monitoring /
# Accessibility grants, forcing you to re-grant after every rebuild.
#
# Run once:  ./scripts/dev-signing-setup.sh
# Then build with:  ./scripts/dev-build.sh
#
# The private key is generated in a temp dir, imported into your login keychain,
# and the temp material is shredded — nothing secret is left on disk or committed.
set -euo pipefail

NAME="ShortcutWheel Dev"
KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"
# Use macOS's built-in LibreSSL: a Homebrew OpenSSL 3 writes a .p12 whose MAC the
# system `security import` can't verify ("MAC verification failed").
OPENSSL="/usr/bin/openssl"

# Not `-v`: a self-signed cert is untrusted and so absent from the valid-only list.
if security find-identity -p codesigning "$KEYCHAIN" | grep -q "$NAME"; then
    echo "Identity '$NAME' already exists — nothing to do."
    exit 0
fi

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

cat > "$TMP/req.cnf" <<'EOF'
[req]
distinguished_name = dn
x509_extensions = v3
prompt = no
[dn]
CN = ShortcutWheel Dev
[v3]
basicConstraints = critical,CA:false
keyUsage = critical,digitalSignature
extendedKeyUsage = critical,codeSigning
EOF

"$OPENSSL" req -x509 -newkey rsa:2048 -days 3650 -nodes \
    -keyout "$TMP/key.pem" -out "$TMP/cert.pem" -config "$TMP/req.cnf"

"$OPENSSL" pkcs12 -export -inkey "$TMP/key.pem" -in "$TMP/cert.pem" \
    -out "$TMP/id.p12" -passout pass:swdev -name "$NAME"

# -T pre-authorizes codesign to use the key without prompting on future signs.
security import "$TMP/id.p12" -k "$KEYCHAIN" -P swdev -T /usr/bin/codesign

echo
echo "Created code-signing identity:"
security find-identity -v -p codesigning "$KEYCHAIN" | grep "$NAME"
echo
echo "Done. Now run ./scripts/dev-build.sh to build, sign, and launch."
