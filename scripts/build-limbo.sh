#!/usr/bin/env bash
# Build liblimbo.so from jni/limbo + jni/compat and install it into the app.
#
#   scripts/build-limbo.sh [--no-install]
#
# One library: the JNI control plane (start/stop, qemu-img) and the callbacks
# QEMU/SDL need (Android_JNI_SetVMResolution) live together, so
# libqemu-system-*.so depends on liblimbo.so and there is no second .so to
# keep in sync.  See jni/compat/REPORT.md.
#
# Exported: the Java_..._VMExecutor_* entry points, JNI_OnLoad, loadLib,
# setup_jni, get_qemu_var, set_qemu_var, set_jni,
# Android_JNI_SetVMResolution, Java_..._FileUtils_nativeAddFd.
set -euo pipefail

APP_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
# shellcheck source=/dev/null
source "$APP_ROOT/scripts/env.sh"

J=$JNI_ROOT
LIBDIR=$APP_ROOT/limbo-android-lib/src/main/jniLibs/arm64-v8a
OUT=$BUILD/native-build
INSTALL=1
[ "${1:-}" = "--no-install" ] && INSTALL=0

mkdir -p "$OUT" "$LIBDIR"

COMMON=(
  --sysroot="$SYSROOT"
  -march=armv8-a+simd+crc+crypto -mtune=cortex-a76
  -O3 -fPIC
  -D__LIMBO__ -D__ANDROID__ -DANDROID -D__linux__ -DCONFIG_LINUX
  -I"$J/limbo" -I"$J/compat" -I"$J/qemu/include"
  -include "$J/compat/limbo_logutils.h"
  -Wall -Wextra -Wno-unused-parameter
)

echo "== compile =="
"$CC" "${COMMON[@]}" -std=gnu11 -c "$J/limbo/vm-executor-jni.c"    -o "$OUT/vm-executor-jni.o"
"$CC" "${COMMON[@]}" -std=gnu11 -c "$J/compat/limbo_compat.c"      -o "$OUT/limbo_compat.o"
"$CC" "${COMMON[@]}" -std=gnu11 -c "$J/compat/limbo_compat_qemu.c" -o "$OUT/limbo_compat_qemu.o"
"$CC" "${COMMON[@]}" -std=gnu11 -c "$J/compat/limbo_compat_fd.c"   -o "$OUT/limbo_compat_fd.o"

echo "== link =="
"$CC" -shared -o "$OUT/liblimbo.so" \
  "$OUT/vm-executor-jni.o" "$OUT/limbo_compat.o" \
  "$OUT/limbo_compat_qemu.o" "$OUT/limbo_compat_fd.o" \
  --sysroot="$SYSROOT" -Wl,--as-needed -llog -ldl \
  "$CROSS_LD_16K" \
  -Wl,-soname,liblimbo.so -Wl,--no-undefined

"$STRIP" --strip-unneeded "$OUT/liblimbo.so"

echo "== size =="
"$TOOLCHAIN/bin/llvm-size" "$OUT/liblimbo.so"
echo "== exports =="
"$NM" -D --defined-only "$OUT/liblimbo.so"
echo "== DT_NEEDED =="
"$READELF" -d "$OUT/liblimbo.so" | grep NEEDED

if [ "$INSTALL" = 1 ]; then
  mkdir -p "$PREFIX/lib"
  cp "$OUT/liblimbo.so" "$LIBDIR/liblimbo.so"
  # link-qemu-so.py resolves -llimbo from the install prefix.
  cp "$OUT/liblimbo.so" "$PREFIX/lib/liblimbo.so"
  echo "== installed =="
  stat -c '%s bytes  %n' "$LIBDIR/liblimbo.so" "$PREFIX/lib/liblimbo.so"
fi
