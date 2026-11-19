#!/usr/bin/env bash
# Create the release signing key if it does not exist yet.
#
#   scripts/make-keystore.sh
#
# The generated keystore is a *demo* key used for this fork's release APKs.
# It lives outside the git checkout (default: $LIMBO_ROOT/keystore) so the
# signing material is never committed.  Override KEYSTORE_DIR/KEYSTORE/
# KEYSTORE_PROPERTIES for a private key.  Do not reuse the demo key for
# anything you care about; replacing it means pre-existing installs must be
# uninstalled first (signature mismatch).
set -euo pipefail

APP_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
# shellcheck source=/dev/null
source "$APP_ROOT/scripts/env.sh"

KS_DIR=${KEYSTORE_DIR:-$LIMBO_ROOT/keystore}
KS=${KEYSTORE:-$KS_DIR/limbo-release.jks}
PROPS=${KEYSTORE_PROPERTIES:-$KS_DIR/keystore.properties}
ALIAS=limbo
PASS=limbo-release

if [ -f "$KS" ] && [ -f "$PROPS" ]; then
    echo "keystore already present: $KS"
    exit 0
fi

mkdir -p "$KS_DIR"
echo "generating $KS"
"$JAVA_HOME/bin/keytool" -genkeypair \
    -keystore "$KS" -storetype PKCS12 \
    -alias "$ALIAS" -keyalg RSA -keysize 2048 -validity 10000 \
    -storepass "$PASS" -keypass "$PASS" \
    -dname "CN=Limbo, OU=Limbo, O=Limbo, L=, ST=, C=US" >/dev/null 2>&1

cat > "$PROPS" <<EOF
# Release signing key for this fork (see README.developers).
storeFile=limbo-release.jks
storePassword=$PASS
keyAlias=$ALIAS
keyPassword=$PASS
EOF
chmod 600 "$PROPS"
echo "wrote $PROPS"
