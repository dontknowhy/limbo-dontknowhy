#!/usr/bin/env bash
# Build and package an APK.
#
#   scripts/package-apk.sh release   # unsigned Gradle APK -> 16 KB zipalign -> apksigner
#   scripts/package-apk.sh debug     # debug-signed APK (Gradle)
#
# The release path deliberately zipaligns *before* signing: AGP 8.1 only aligns
# to 4 KB, while Android 15+ needs uncompressed native libraries at 16 KB
# boundaries.  build-tools 35.0.0 (zipalign -P 16) is required.
set -euo pipefail

MODE=${1:-release}
APP_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
# shellcheck source=/dev/null
source "$APP_ROOT/scripts/env.sh"

if [ ! -x "$GRADLE" ]; then
    GRADLE=$(command -v gradle || true)
fi
if [ -z "$GRADLE" ] || [ ! -x "$GRADLE" ]; then
    echo "error: gradle not found (set GRADLE=/path/to/gradle)" >&2
    exit 1
fi
if [ ! -x "$BUILD_TOOLS/zipalign" ]; then
    echo "error: $BUILD_TOOLS/zipalign not found" >&2
    exit 1
fi
ZIPALIGN_HELP=$("$BUILD_TOOLS/zipalign" 2>&1 || true)
case "$ZIPALIGN_HELP" in
    *"-P <pagesize"*) ;;
    *)
        echo "error: zipalign with -P support not found in $BUILD_TOOLS" >&2
        echo "       install build-tools 35.0.0: sdkmanager 'build-tools;35.0.0'" >&2
        exit 1
        ;;
esac

mkdir -p "$BUILD"

if [ "$MODE" = debug ]; then
    "$GRADLE" -p "$APP_ROOT" :limbo-android-x86:assembleDebug
    OUT=$BUILD/limbo-x86-qemu11-arm64-debug.apk
    cp -f "$APP_ROOT/limbo-android-x86/build/outputs/apk/debug/limbo-android-x86-debug.apk" "$OUT"
else
    "$GRADLE" -p "$APP_ROOT" :limbo-android-x86:assembleRelease
    UNSIGNED=$(find "$APP_ROOT/limbo-android-x86/build/outputs/apk/release" \
        -name '*release-unsigned.apk' -o -name '*release.apk' | head -1)
    if [ -z "$UNSIGNED" ]; then
        echo "error: Gradle did not produce a release APK" >&2
        exit 1
    fi

    # 16 KB page alignment for uncompressed .so entries.
    ALIGNED=$BUILD/limbo-x86-qemu11-arm64-release-aligned.apk
    "$BUILD_TOOLS/zipalign" -P 16 -f 4 "$UNSIGNED" "$ALIGNED"

    # Sign (v1+v2+v3) with the fork's published demo key.
    OUT=$BUILD/limbo-x86-qemu11-arm64-release.apk
    (
        # shellcheck source=/dev/null
        source "$APP_ROOT/keystore/keystore.properties"
        "$BUILD_TOOLS/apksigner" sign \
            --ks "$APP_ROOT/keystore/$storeFile" \
            --ks-key-alias "$keyAlias" \
            --ks-pass "pass:$storePassword" \
            --key-pass "pass:$keyPassword" \
            --min-sdk-version 24 \
            --out "$OUT" "$ALIGNED"
        rm -f "$ALIGNED"

        "$BUILD_TOOLS/zipalign" -c -P 16 4 "$OUT"
        "$BUILD_TOOLS/apksigner" verify --print-certs "$OUT" | head -6
    )
fi

echo
echo "APK: $OUT"
ls -l "$OUT"
sha256sum "$OUT"
