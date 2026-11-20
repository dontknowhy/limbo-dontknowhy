# Build

The native build is one `Makefile` + `scripts/*.sh`; upstream Limbo's
`Android.mk`/`Application.mk` are gone (`jni/Makefile` only forwards to the root
Makefile). Everything cross-compiles into `$PREFIX` (`../prebuilt/arm64-v8a`) and is
copied into `jniLibs` as a last step.

## Toolchain

- NDK r30 (`android-ndk-r30`, clang 21), `API=29`, `ABI=arm64-v8a`,
  triple `aarch64-linux-android`.
- Host: `meson`, `ninja`, `cmake>=3.24`, `pkg-config`, `patchelf`, `python3`, `flex`,
  `bison`, `gettext`, `autoconf/automake/libtool`.
- JDK 17, Gradle 8.2.1, Android SDK platform 31, build-tools 35+ (for `zipalign -P`).

`scripts/env.sh` derives `APP_ROOT` from its own location and defaults
`LIMBO_ROOT=$APP_ROOT/..`. It exports `CC/CXX/AR/...`, `PREFIX`, `BUILD`, `DEPS`,
`PKG_CONFIG_LIBDIR=$PREFIX/lib/pkgconfig` and `ARCH_FLAGS`:

```
-march=armv8-a+simd+crc+crypto -mtune=cortex-a76 -O3 -fPIC
```

Override any of `LIMBO_ROOT/DEPS/PREFIX/BUILD/SRC/QEMU_SRC/QEMU_BUILD/JOBS/NDK_ROOT/
ANDROID_HOME` before calling make. Do not add host paths to `PKG_CONFIG_PATH`; a host
glib/pixman being picked up produces binaries that link on the host and fail on device.

## `make prepare`

- Extracts every tarball (QEMU/glib/pixman/SDL2/libffi plus zlib-ng/zstd/pcre2/
  libiconv/libslirp) into `jni/`, next to the tarballs.
- Applies `jni/patches/qemu-11.1.3/*.patch` in order; it first reverse-dry-runs patch
  0001 to detect an already-patched tree, so rerunning is safe.
- Generates `build/config-meson.cross` for the meson dependencies.

The extracted sources are gitignored. Never edit them without turning the change into a
patch (see `qemu-patches.md`).

## `make deps`

Order matters and is encoded in the Makefile:

`zlib-ng (ZLIB_COMPAT) → zstd → pcre2 → libiconv → libffi → glib → pixman →
libslirp → SDL2`

glib 2.90.1 needs pcre2 + libffi + libiconv; libslirp needs glib. All install into
`$PREFIX`. Versions live in `scripts/fetch-deps.sh` (URL + sha256):
QEMU 11.1.3, glib 2.90.1, pixman 0.46.4, SDL2 2.32.10, zlib-ng 2.3.3, zstd 1.5.7,
pcre2 10.49, libiconv 1.18, libffi 3.4.3, libslirp 4.9.7, proxy-libintl 0.5.

Failure modes worth knowing:

- libiconv refuses an out-of-tree configure if the extracted tree still has
  `config.status`; the Makefile runs `distclean` first.
- libslirp 4.9.0 does **not** link with lld (version script); use 4.9.7.
- glib/pixman/libslirp build dirs configured without `config-meson.cross` are deleted and
  reconfigured. If you change the cross file, delete the build dir explicitly.
- zlib-ng must stay in `ZLIB_COMPAT=ON` mode: it installs `libz.so`.

## `make qemu`

1. `scripts/qemu-configure.sh` writes `$QEMU_BUILD` (default `../build/qemu-build`).
2. `ninja -C $QEMU_BUILD qemu-system-x86_64 qemu-img`.
3. `scripts/link-qemu-so.py` re-links the ninja link edge as `-shared` into
   `libqemu-system-x86_64.so` / `libqemu-img.so`.
4. The libraries are moved to `limbo-android-x86/src/main/jniLibs/arm64-v8a/`,
   stripped, and `scripts/fix-needed.sh` rewrites `DT_NEEDED`.

Important configure choices (full list at the top of `scripts/qemu-configure.sh`):

- `--target-list=x86_64-softmmu` only (other guest libraries need their own build).
- `--enable-sdl --enable-vnc --enable-zstd --enable-iconv --enable-slirp`
  `--audio-drv-list=sdl,opensles,aaudio`.
- `--with-coroutine=sigaltstack`: mandatory with the aarch64 setjmp replacement.
- `--disable-opengl --disable-virglrenderer` (no virgl in this build).
- vhost/vhost-user, seccomp, curl, gnutls, spice, usb-redir, etc. are disabled because
  bionic lacks the host facilities.
- `-Db_lto=true -Db_lto_mode=default`. Extra arguments after the script name are passed
  through to QEMU's configure, so `scripts/qemu-configure.sh -Db_lto=false` gives a
  faster-linking non-LTO build. `EXTRA_CFLAGS` is the supported way to inject flags.

### PGO

PGO is on by default: `profiles/qemu-11.1.3.profdata` is a multi-image IR profile.
`make` adds `-fprofile-use=...` to both the compile flags and the LTO link
(`EXTRA_LDFLAGS`), because the real optimisation happens at link time.

- Disable with `make PGO_PROFILE=`.
- `scripts/prepare-pgo-profile.sh` rewrites the profile's source-root keys from the
  training layout to the current `QEMU_BUILD → QEMU_SRC` relative path and writes
  `../build/qemu-pgo.profdata`. If you move the workspace, delete that generated file.
- Retrain after changing QEMU sources:

```bash
export BUILD=$PWD/../build PREFIX=$PWD/../prebuilt/arm64-v8a
QEMU_BUILD=$BUILD/qemu-build-pgo \
EXTRA_CFLAGS="-fprofile-generate=/data/local/tmp/pgo" \
    scripts/qemu-configure.sh -Db_pgo=generate
ninja -C $BUILD/qemu-build-pgo qemu-system-x86_64
python3 scripts/link-qemu-so.py $BUILD/qemu-build-pgo \
    qemu-system-x86_64 libqemu-pgogen.so
scripts/fix-needed.sh libqemu-pgogen.so
# push the .so + jniLibs, boot each guest for ~30 s, pull *.profraw
llvm-profdata merge -o profiles/qemu-11.1.3.profdata *.profraw
```

`-Db_pgo=generate` is required (not just the cflag) so meson links the profiling
runtime. Train with the build directory at the same depth as `qemu-build`
(`$BUILD/qemu-build-pgo`); otherwise the rewritten keys may not cover every static
function.

## Re-linking details (`scripts/link-qemu-so.py`)

QEMU 11 has no `Makefile.target` link hook. The script parses `build.ninja`, takes the
object list and `LINK_ARGS` of the `qemu-system-*` / `qemu-img` edge, and re-links:

- objects before archives (archive scan order; otherwise `libqemuutil.a` stubs win);
- `-shared` instead of the meson `-pie`;
- `-Wl,-z,max-page-size=16384` (16 KB devices);
- `--whole-archive libandroid-setjmp.a` + `-Wl,-Bsymbolic-functions` (bind the internal
  setjmp references to the replacement);
- for QEMU only: `-Wl,--no-as-needed -llimbo -Wl,--as-needed`, because
  `Android_JNI_SetVMResolution` is a weak reference and `--as-needed` would drop
  `liblimbo.so` from `DT_NEEDED`.

## `make jnilibs`

`scripts/sync-jnilibs.sh` copies `libglib-2.0.so`, `libgio-2.0.so`, `libgobject-2.0.so`,
`libgmodule-2.0.so`, `libintl.so`, `libiconv.so`, `libpcre2-8.so`, `libffi.so`,
`libpixman-1.so`, `libz.so`, `libzstd.so`, `libslirp.so`, `libSDL2.so` into the library
module's `jniLibs`, strips them, sets each SONAME to its packaged filename, then runs
`fix-needed.sh`. The SONAME step is not optional: bionic registers the soinfo under the
SONAME, so a versioned SONAME breaks `DT_VERNEED` resolution even when the file loads.

## Stamps and cleaning

Each step has a stamp under `$BUILD/.stamps/`. Remove the stamp (or the target output) to
rerun one step. `make clean-qemu` removes the QEMU build **and** the `qemu-configured`
stamp; `make distclean` also removes the native build and `jniLibs`. `make qemu`
self-heals a missing `build.ninja` by reconfiguring.

Build logs are not captured automatically; when debugging, redirect to
`../build/logs/<step>.log` so the evidence survives.
