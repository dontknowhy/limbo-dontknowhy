#!/usr/bin/env bash
# Create the release signing key if it does not exist yet.
#
#   scripts/make-keystore.sh
#
# The generated keystore is a *demo* key: it is published in this repository
# so that every build of this fork can upgrade the previous one.  Do not reuse
# it for anything you care about.  Delete the files and run this script again
# to get a private key (pre-existing installs then need a reinstall).
set -euo pipefail

APP_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
# shellcheck source=/dev/null
source "$APP_ROOT/scripts/env.sh"

KS_DIR=$APP_ROOT/keystore
KS=$KS_DIR/limbo-release.jks
PROPS=$KS_DIR/keystore.properties
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
