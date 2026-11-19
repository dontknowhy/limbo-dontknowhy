# QEMU patch series

QEMU sources are not committed. The authoritative record of every QEMU change is
`limbo-android-lib/src/main/jni/patches/qemu-11.1.3/` (plus the separate
`patches/setjmp-aarch64/`). `jni/qemu` is an extracted, patched, gitignored tree.

## Series

Apply in numerical order with GNU `patch -p1` **or** `git apply`; both must work. New
files carry `new file mode 100644` / `--- /dev/null` headers so `git apply` creates them.

| patch | topic |
|---|---|
| `0001-android-build-meson.patch` | meson/configure for bionic: no librt/shm_open, never probe X11, skip signalfd/ivshmem, build `util/limbo-openpty.c`, define `SDL_MAIN_HANDLED` in `system/main.c`. |
| `0002-android-libc-compat.patch` | bionic gaps: `/tmp`/`/var/tmp` replacement paths, statx `DIOALIGN`, `telldir`/`seekdir` replacement, SCSI/9p name clashes, openpty declaration, `mmap_min_addr`, `<linux/soundcard.h>`, no `<glob.h>`, shm_open emulation in `$TMPDIR`/app cache. |
| `0003-limbo-ui-hooks.patch` | UI hooks: VGA full repaint, tunable SDL/VNC refresh intervals, SDL scale hint, weak `Android_JNI_SetVMResolution` callback from sdl2-2d. |
| `0004-android-audio-backends.patch` | OpenSL ES + AAudio drivers (`audio/openslesaudio.c`, `audio/aaudioaudio.c`), QAPI, meson probes; both input and output. |
| `0005-qemu-img-inprocess.patch` | `limbo_img_create()` calls `bdrv_create()` directly, avoiding `qemu-img`'s `main()`/`exit()`. |
| `0006-fdset-hotplug.patch` | `limbo_fdset_add()` registers an fd without a monitor/`SCM_RIGHTS`, for live media changes. |

New QEMU files: `audio/openslesaudio.c`, `audio/aaudioaudio.c`,
`util/limbo-openpty.c`.

Limbo-specific hooks are guarded by `__LIMBO__`; Android compatibility changes use
`__ANDROID__` where possible. Keep that split when adding a hook.

### Audio dispatch trap

A new audio driver must be wired into **all three** dispatch points:
`audio_create_pdos`, `audio_get_pdo_out/in` in `audio/audio.c`, and the same-named
functions in `audio/audio_template.h`. Missing one makes QEMU `abort()`. AAudio must stay
`dlopen("libaaudio.so")` (API 26+) so the library still loads on older devices.

## setjmp replacement

`patches/setjmp-aarch64/{setjmp.S,private/*.h}` is the AOSP `sigsetjmp`/`siglongjmp`
implementation, not a QEMU patch. bionic's versions carry PAC signatures and crash with
`SIGILL` / `ESR 0x72000000` when a coroutine switches stacks or threads. The Makefile
builds it into `../build/setjmp/libandroid-setjmp.a`; `link-qemu-so.py` links it
`--whole-archive` and uses `-Bsymbolic-functions` so QEMU's internal calls bind to it.
Do not remove either flag, and keep `--with-coroutine=sigaltstack`.

## Editing QEMU

Preferred workflow (a git checkout makes `git diff` usable):

```bash
cd ../                 # workspace root
git clone https://github.com/qemu/qemu
cd qemu && git checkout v11.1.3
git submodule update --init --recursive --depth=1
# add the repo's patches with `git add -N` for new files, then edit
```

Build from that tree with:

```bash
make QEMU_SRC=$PWD/../qemu QEMU_BUILD=$PWD/../build/qemu-build-git qemu
```

Remember to remove `../build/.stamps/qemu-configured` when switching `QEMU_SRC` or
`QEMU_BUILD`, otherwise the old configuration is reused.

After editing, split the diff by topic into the six patches (or add a new numbered
patch), then verify.

## Regenerating and verifying

```bash
cd /tmp && rm -rf qemu-pristine && mkdir qemu-pristine
tar -xf "$LIMBO_ROOT/deps/qemu-11.1.3.tar.xz" -C qemu-pristine --strip-components=1
cd qemu-pristine
for p in "$JNI_ROOT"/patches/qemu-11.1.3/*.patch; do patch -p1 < "$p"; done
# or: git init && git add -A && for p in ...; do git apply "$p"; done
diff -rq /tmp/qemu-pristine "$JNI_ROOT"/qemu
```

The only acceptable differences are build artifacts and submodule/extracted content:
`build/`, `__pycache__/`, `subprojects/`, `roms/` (if the checkout initialized
submodules). A clean tarball plus the series must reproduce `jni/qemu` byte-for-byte.

Rules:

- Never leave edits in `jni/qemu` outside the patch series; `make prepare` will not
  preserve them on a fresh clone and the diff is invisible to review.
- `patches/qemu-11.1.3/README` mirrors the topic list above; update it when adding a
  patch.
- The series is against `deps/qemu-11.1.3.tar.xz` (sha256 in `scripts/fetch-deps.sh`).
