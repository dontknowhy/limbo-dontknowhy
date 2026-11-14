#!/usr/bin/env bash
# Copy the cross-built dependency libraries from $PREFIX into the app's
# jniLibs/arm64-v8a with the names Android packages (libfoo.so, no version
# suffix), stripping debug information on the way.
#
# libqemu-system-*.so / libqemu-img.so / liblimbo.so are produced by the qemu
# and liblimbo targets and are left alone.
set -euo pipefail

APP_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
# shellcheck source=/dev/null
source "$APP_ROOT/scripts/env.sh"

JLIB=$APP_ROOT/limbo-android-lib/src/main/jniLibs/arm64-v8a
mkdir -p "$JLIB"

copy_lib() {
    src=$1
    dst=$2
    if [ ! -e "$src" ]; then
        echo "error: missing $src (run 'make deps' first)" >&2
        exit 1
    fi
    cp -Lf "$src" "$JLIB/$dst"
    "$STRIP" --strip-unneeded "$JLIB/$dst" 2>/dev/null || true
    # Android addresses libraries by file name.  Set the SONAME to the packaged
    # name as well, otherwise bionic loads <name> but registers the soinfo under
    # its old SONAME and versioned references (DT_VERNEED) cannot be resolved.
    if [ "$PATCHELF" != false ]; then
        "$PATCHELF" --set-soname "$dst" "$JLIB/$dst"
    fi
    printf '  %-28s %s\n' "$dst" "$(stat -c %s "$JLIB/$dst")"
}

echo "syncing dependencies into $JLIB"
copy_lib "$PREFIX/lib/libglib-2.0.so"    libglib-2.0.so
copy_lib "$PREFIX/lib/libgio-2.0.so"     libgio-2.0.so
copy_lib "$PREFIX/lib/libgobject-2.0.so" libgobject-2.0.so
copy_lib "$PREFIX/lib/libgmodule-2.0.so" libgmodule-2.0.so
copy_lib "$PREFIX/lib/libintl.so"        libintl.so
copy_lib "$PREFIX/lib/libiconv.so"       libiconv.so
copy_lib "$PREFIX/lib/libpcre2-8.so"     libpcre2-8.so
copy_lib "$PREFIX/lib/libffi.so"         libffi.so
copy_lib "$PREFIX/lib/libpixman-1.so"    libpixman-1.so
copy_lib "$PREFIX/lib/libz.so"           libz.so
copy_lib "$PREFIX/lib/libzstd.so"        libzstd.so
copy_lib "$PREFIX/lib/libslirp.so"       libslirp.so
copy_lib "$PREFIX/lib/libSDL2.so"        libSDL2.so

# Android only loads names ending in .so; rewrite versioned DT_NEEDED entries
# (libglib-2.0.so.0, libintl.so.8, ...) to the packaged names.
"$APP_ROOT/scripts/fix-needed.sh" "$JLIB"/*.so

echo "done"
