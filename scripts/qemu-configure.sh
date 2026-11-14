#!/usr/bin/env bash
# Configure the QEMU 11 build for Android arm64-v8a.
#
#   scripts/qemu-configure.sh [--clean]
#
# Produces $BUILD/qemu-build (Ninja) with the full-LTO configuration used for
# release builds.  Build it with `make qemu` (or ninja -C $BUILD/qemu-build).
#
# QEMU's configure generates config-host.mak (target list) and the meson
# cross/native files; it needs a cross-prefix whose tools exist, so we
# materialise a small symlink farm instead of requiring NDK-style binutils.
set -euo pipefail

APP_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
# shellcheck source=/dev/null
source "$APP_ROOT/scripts/env.sh"

QEMU_BUILD=${QEMU_BUILD:-$BUILD/qemu-build}
QEMU_SRC=${QEMU_SRC:-$JNI_ROOT/qemu}

if [ "${1:-}" = "--clean" ]; then
    rm -rf "$QEMU_BUILD"
    shift
fi

if [ ! -x "$QEMU_SRC/configure" ]; then
    echo "error: $QEMU_SRC is missing; run 'make prepare' first" >&2
    exit 1
fi

# ---- cross-prefix symlink farm ------------------------------------------
TP=$BUILD/toolchain-prefix/bin
mkdir -p "$TP"
ln -snf "$CC"      "$TP/aarch64-linux-android-gcc"
ln -snf "$CXX"     "$TP/aarch64-linux-android-g++"
ln -snf "$AR"      "$TP/aarch64-linux-android-ar"
ln -snf "$AS"      "$TP/aarch64-linux-android-as"
ln -snf "$LD"      "$TP/aarch64-linux-android-ld"
ln -snf "$NM"      "$TP/aarch64-linux-android-nm"
ln -snf "$OBJCOPY" "$TP/aarch64-linux-android-objcopy"
ln -snf "$OBJDUMP" "$TP/aarch64-linux-android-objdump"
ln -snf "$RANLIB"  "$TP/aarch64-linux-android-ranlib"
ln -snf "$READELF" "$TP/aarch64-linux-android-readelf"
ln -snf "$STRIP"   "$TP/aarch64-linux-android-strip"
ln -snf /usr/bin/pkg-config "$TP/aarch64-linux-android-pkg-config"
if [ -x "$PREFIX/bin/sdl2-config" ]; then
    ln -snf "$PREFIX/bin/sdl2-config" "$TP/aarch64-linux-android-sdl2-config"
fi

mkdir -p "$QEMU_BUILD"

GDB_BIN=$(command -v gdb-multiarch || command -v gdb || true)

# The option list mirrors the configuration validated on device.  Keep in
# sync with README.developers ("QEMU options").
CONFIGURE_OPTS=(
    --target-list=x86_64-softmmu
    --prefix="$PREFIX"
    --cross-prefix="$TP/aarch64-linux-android-"
    --disable-werror
    --disable-guest-agent
    --disable-install-blobs
    --enable-tools
    # display / audio
    --enable-sdl
    --disable-sdl-image
    --audio-drv-list=sdl,opensles,aaudio
    --disable-alsa
    --disable-pa
    --disable-jack
    --disable-sndio
    --disable-pipewire
    --disable-oss
    --disable-dsound
    --disable-coreaudio
    # UI backends
    --enable-vnc
    --disable-vnc-jpeg
    --disable-vnc-sasl
    --disable-png
    --disable-curses
    --disable-gtk
    --disable-cocoa
    --disable-opengl
    --disable-virglrenderer
    --disable-dbus-display
    # host facilities that do not exist under bionic
    --disable-numa
    --disable-vhost-kernel
    --disable-vhost-net
    --disable-vhost-user
    --disable-vhost-vdpa
    --disable-vhost-user-blk-server
    --disable-vhost-crypto
    --disable-linux-aio
    --disable-linux-io-uring
    --disable-libiscsi
    --disable-libnfs
    --disable-curl
    --disable-rdma
    --disable-brlapi
    --disable-vde
    --disable-netmap
    --disable-cap-ng
    --disable-attr
    --disable-seccomp
    --disable-lzo
    --disable-snappy
    --disable-bzip2
    --disable-xen
    --disable-spice
    --disable-usb-redir
    --disable-smartcard
    --disable-tpm
    --disable-gnutls
    --disable-nettle
    --disable-libdw
    --disable-valgrind
    --disable-u2f
    --disable-libudev
    --disable-libusb
    # misc
    --enable-zstd
    --enable-iconv
    --enable-slirp
    --with-coroutine=sigaltstack
    --enable-trace-backends=nop
    --disable-modules
    --disable-pie
    --disable-docs
    # Full LTO release build (meson option passthrough).
    -Db_lto=true
    -Db_lto_mode=default
)
if [ -n "$GDB_BIN" ]; then
    CONFIGURE_OPTS+=(--gdb="$GDB_BIN")
fi

# Optional extra optimisation flags (experiments; see README §4).
EXTRA_CFLAGS=${EXTRA_CFLAGS:-}

cd "$QEMU_BUILD"
env \
    CC="$CC" \
    CXX="$CXX" \
    AR="$AR" \
    NM="$NM" \
    RANLIB="$RANLIB" \
    STRIP="$STRIP" \
    OBJCOPY="$OBJCOPY" \
    CFLAGS="$CROSS_CFLAGS -D__LIMBO__ -D__ANDROID__ -DANDROID -D__linux__ -DCONFIG_LINUX $EXTRA_CFLAGS" \
    CXXFLAGS="$CROSS_CFLAGS -D__LIMBO__ -D__ANDROID__ -DANDROID -D__linux__ -DCONFIG_LINUX $EXTRA_CFLAGS" \
    LDFLAGS="$CROSS_LDFLAGS -liconv" \
    "$QEMU_SRC/configure" "${CONFIGURE_OPTS[@]}" "$@"

echo
echo "configured: $QEMU_BUILD"
echo "next:       make qemu"
