#!/usr/bin/env bash
# Shared environment for the Limbo native build.
#
# Source it from a shell (or a Makefile recipe):
#     source scripts/env.sh
#
# Everything is derived from the location of this file, so the tree can be
# moved or cloned anywhere.  Override with environment variables before
# sourcing if you have a different layout.

# Works when sourced from bash and zsh (the workspace helper is used from both).
_SELF=${BASH_SOURCE[0]:-$0}
APP_ROOT=$(cd "$(dirname "$_SELF")/.." && pwd)
export APP_ROOT

# Workspace root: the parent of the app repo.  It holds deps/, build/ and
# prebuilt/ (see README.developers).
export LIMBO_ROOT=${LIMBO_ROOT:-$(dirname "$APP_ROOT")}

export LIMBO_SRC=$APP_ROOT
export JNI_ROOT=$APP_ROOT/limbo-android-lib/src/main/jni

# ---- Android NDK ---------------------------------------------------------
export NDK_ROOT=${NDK_ROOT:-$LIMBO_ROOT/android-ndk-r30}
export NDK=$NDK_ROOT
export TOOLCHAIN=$NDK_ROOT/toolchains/llvm/prebuilt/linux-x86_64
export API=${API:-21}                 # keep in sync with minSdkVersion
export ABI=${ABI:-arm64-v8a}
export TRIPLE=${TRIPLE:-aarch64-linux-android}
export CROSS_PREFIX=$TRIPLE-

export CC=$TOOLCHAIN/bin/${TRIPLE}${API}-clang
export CXX=$TOOLCHAIN/bin/${TRIPLE}${API}-clang++
export AR=$TOOLCHAIN/bin/llvm-ar
export AS=$TOOLCHAIN/bin/llvm-as
export LD=$TOOLCHAIN/bin/ld.lld
export NM=$TOOLCHAIN/bin/llvm-nm
export RANLIB=$TOOLCHAIN/bin/llvm-ranlib
export STRIP=$TOOLCHAIN/bin/llvm-strip
export OBJCOPY=$TOOLCHAIN/bin/llvm-objcopy
export OBJDUMP=$TOOLCHAIN/bin/llvm-objdump
export READELF=$TOOLCHAIN/bin/llvm-readelf
export SYSROOT=$TOOLCHAIN/sysroot

# CMake toolchain used by the CMake-based dependencies (zlib-ng, pcre2, SDL2).
export CMAKE_TOOLCHAIN_FILE=$NDK_ROOT/build/cmake/android.toolchain.cmake

# ---- Install prefixes ----------------------------------------------------
# Cross-built dependencies are installed here; jniLibs/ only ever receives
# the final renamed copies.
export PREFIX=${PREFIX:-$LIMBO_ROOT/prebuilt/arm64-v8a}
export BUILD=${BUILD:-$LIMBO_ROOT/build}
export SRC=${SRC:-$BUILD/src}
export DEPS=${DEPS:-$LIMBO_ROOT/deps}

export PKG_CONFIG_PATH=$PREFIX/lib/pkgconfig:$PREFIX/share/pkgconfig
export PKG_CONFIG_LIBDIR=$PKG_CONFIG_PATH
export PKG_CONFIG_SYSROOT_DIR=

# ---- Common cross flags --------------------------------------------------
# Pure armv8-a: NEON is baseline on AArch64, no 32-bit ARM support anywhere.
export ARCH_FLAGS="-march=armv8-a+simd+crc+crypto -mtune=cortex-a76"
export CROSS_CFLAGS="--sysroot=$SYSROOT $ARCH_FLAGS -O3 -fPIC"
export CROSS_CPPFLAGS="--sysroot=$SYSROOT -I$PREFIX/include"
export CROSS_LDFLAGS="--sysroot=$SYSROOT -L$PREFIX/lib -Wl,-rpath-link,$PREFIX/lib"

# 16 KB page size: Android 15+ requires native libraries to be compatible
# with 16 KB pages (and the APK to keep uncompressed .so files 16 KB aligned).
export CROSS_LD_16K="-Wl,-z,max-page-size=16384"

# Historical names used by scripts/manual builds.
export CFLAGS="$CROSS_CFLAGS -D__LIMBO__ -D__ANDROID__ -DANDROID -D__linux__ -DCONFIG_LINUX"
export CXXFLAGS=$CFLAGS
export CPPFLAGS=$CROSS_CPPFLAGS
export LDFLAGS=$CROSS_LDFLAGS
export LIBS=""

# ---- Host tools ----------------------------------------------------------
export JOBS=${JOBS:-$(nproc)}
export MESON=${MESON:-meson}
export NINJA=${NINJA:-ninja}
export CMAKE=${CMAKE:-cmake}
export JAVA_HOME=${JAVA_HOME:-$LIMBO_ROOT/jdk-17}
export GRADLE=${GRADLE:-$LIMBO_ROOT/gradle-8.2.1/bin/gradle}
export ANDROID_HOME=${ANDROID_HOME:-$LIMBO_ROOT/android-sdk}
export ANDROID_SDK_ROOT=$ANDROID_HOME
export PATH=$TOOLCHAIN/bin:$PREFIX/bin:$JAVA_HOME/bin:$ANDROID_HOME/platform-tools:$ANDROID_HOME/cmdline-tools/latest/bin:$PATH

# Build-tools with 16 KB zip alignment support (zipalign -P).  build-tools
# 35.0.0 is the first one that has it; override if yours lives elsewhere.
for d in 36.0.0 35.0.0 34.0.0; do
    if [ -x "$ANDROID_HOME/build-tools/$d/zipalign" ] &&
       "$ANDROID_HOME/build-tools/$d/zipalign" 2>&1 | grep -q -- "-P <pagesize"; then
        BUILD_TOOLS=$ANDROID_HOME/build-tools/$d
        break
    fi
done
export BUILD_TOOLS=${BUILD_TOOLS:-${BUILD_TOOLS:-$ANDROID_HOME/build-tools/35.0.0}}

# pkg-config must never see host libraries.
export PKG_CONFIG="pkg-config --define-variable=prefix=$PREFIX"

# patchelf is needed to rename DT_NEEDED entries (host tool).
if command -v patchelf >/dev/null 2>&1; then
    PATCHELF=$(command -v patchelf)
elif [ -x "$BUILD/tools/patchelf/bin/patchelf" ]; then
    PATCHELF=$BUILD/tools/patchelf/bin/patchelf
else
    PATCHELF=false
fi
export PATCHELF

# aarch64 sigsetjmp/siglongjmp replacement (bionic's version is PAC-signed and
# cannot be used across coroutine stacks).  Built from patches/setjmp-aarch64.
export SETJMP_DIR=$BUILD/setjmp
export SETJMP_LIB=$SETJMP_DIR/libandroid-setjmp.a

# Location of the QEMU build directory (full-LTO release build).
export QEMU_SRC=$JNI_ROOT/qemu
export QEMU_BUILD=${QEMU_BUILD:-$BUILD/qemu-build}
