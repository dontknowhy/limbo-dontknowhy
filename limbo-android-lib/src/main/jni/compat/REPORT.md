# libcompat-limbo.so — audit, rewrite and shrink

> 2026-11-14 (later): this library no longer exists on its own. The three
> remaining entry points are compiled into `liblimbo.so`
> (`build/tools/build-limbo.sh`), and `libqemu-system-*.so` now has
> `DT_NEEDED liblimbo.so`. The audit below is kept as the record of what was
> removed and why.

`jni/compat/` used to build a 19,904-byte library exporting 30 symbols, all
inherited from QEMU 5.1: SAF path resolvers, a `valloc`/`strchrnul` fallback,
`sigtimedwait`, vendored cpufeatures and a JNI bridge. On QEMU 11 + arm64 only
one caller and one callee still matter.

Result: **19,904 → 6,288 bytes** (`text` 16,675 → 3,006), 30 → 2 exported
symbols, `DT_NEEDED` `liblog,libc,libm,libstdc++,libdl` → `liblog,libc`.
While doing it, the audit found that the SDL resolution callback had been dead
at runtime on this port (see §4).

## 1. Method

Nothing was removed on a hunch. For every symbol the old library exported, the
whole shipped `.so` set was searched for an importer:

```sh
cd limbo-dontknowhy/limbo-android-lib/src/main/jniLibs/arm64-v8a
for s in valloc strchrnul android_fopen android_open android_close android_stat \
         android_mkstemp lockf sigtimedwait android_getCpuFamily \
         android_getCpuFeatures android_getCpuCount set_sdl_res set_jni \
         Android_JNI_SetVMResolution get_fd close_fd; do
    echo "== $s"; llvm-nm -D --undefined-only *.so | grep -E " U ${s}$"
done
```

and, for the globals the old header exported:

```sh
for s in jvm jobj jcls fd_lock storage_base_dir limbo_base_dir; do …; done
```

Result: **`set_jni` is imported by `liblimbo.so`; nothing else has any
importer.** `Android_JNI_SetVMResolution` is a *weak* reference from
`libqemu-system-*.so` (`ui/sdl2-2d.c`), invisible to `nm --undefined-only`
grep patterns that look for ` U `; it was verified separately with
`llvm-readelf -r` (see §4).

The 17 shipped libraries checked: `libqemu-system-x86_64`, `liblimbo`,
`libSDL2`, `libglib-2.0`, `libgio-2.0`, `libgobject-2.0`, `libpixman-1`,
`libz`, `libzstd`, `libslirp`, `libffi`, `libintl`, `libiconv`,
`libcompat-limbo`, `libqemu-img`, `libc++_shared`, `libandroid-support`.

## 2. What was removed, and why it was safe

| Removed | Was it used? | Notes |
|---|---|---|
| `valloc()` | no | bionic has it; nothing imports ours |
| `strchrnul()` | no | bionic has it since API 24 |
| `android_fopen/open/close/stat/mkstemp`, `lockf` | no | QEMU 5.1 wired these in with `objcopy --redefine-sym`; the QEMU 11 build renames nothing |
| `get_fd`/`close_fd` + the two pthread wrappers | no | SAF now hands QEMU an fd through its own `-add-fd`/`/dev/fdset/N` protocol (see §4b) |
| `sigtimedwait()` | no | QEMU 11 on Android is TCG only; bionic exports it anyway |
| `android_getCpu*` (cpufeatures) | no | only reached 32-bit pixman/SDL; this build is arm64-only |
| `set_sdl_res`, `create_thread_set_sdl_res` | internal only | folded into `Android_JNI_SetVMResolution` |
| globals `jvm/jobj/jcls/fd_lock/storage_base_dir/limbo_base_dir` | no | only used by the files above |

The two files that are now empty (`limbo_compat_filesystem.c`,
`limbo_compat_signals.cpp`) are kept in the source list so `Android.mk` and any
downstream scripting keep working; their corrected, host-tested reference
implementations live in `legacy/` and are **not** linked.

## 3. Bugs in the code that was kept

`set_jni()` / `Android_JNI_SetVMResolution()` are the only survivors, and both
were rewritten:

1. **`jobj` global ref leak.** `NewGlobalRef(env, obj)` pinned the `VMExecutor`
   instance — and through it the `MachineController` and the activity — for the
   whole process lifetime, across machine restarts. The callback target is a
   *static* Java method, so the instance is not needed at all; only the class
   is kept.
2. **`pthread_mutex_init()` on a live mutex.** `set_jni()` is called on every
   VM start; the second call re-initialised the mutex that `set_sdl_res()` may
   hold. The replacement uses a static `PTHREAD_MUTEX_INITIALIZER` and returns
   early when already initialised.
3. **Failed init left the library half-usable.** The old code returned on
   `pthread_mutex_init()` failure but callers went on to lock the
   uninitialised mutex. The new code fails closed: `limbo_compat_jvm()` stays
   `NULL` and the callback becomes a silent no-op.
4. **One thread creation per resolution change.** Every notification did
   `malloc` + `pthread_create` + `pthread_join` + `AttachCurrentThread` +
   `GetObjectClass` + `GetStaticMethodID` + `DetachCurrentThread`, all while
   holding a mutex. `pthread_create`+`join` alone is ≥15 µs on an x86-64
   desktop (measured, 2000 iterations), and on a phone it also schedules a new
   thread. The replacement caches the class and the method id once and calls
   `GetEnv()`; it attaches only if the caller really is detached, and never
   detaches a thread it did not attach.
5. **Pending Java exception leaked into QEMU.** A throw from
   `onVMResolutionChanged` stayed pending on the calling thread, where the next
   JNI call would trip over it. Now it is described and cleared.
6. **`GetStaticMethodID` also cached**, so a missing method is detected once at
   `set_jni()` time instead of every frame.
7. **Removed handlers carried real bugs** (`android_fopen` did an unbounded
   `strcpy`/`strcat` into a 256-byte stack buffer; inverted `fd >= 0` checks;
   `printf()` on the hot path; `sigtimedwait` assumed a `sigset_t` layout
   without a static assert). Deleting the code was safer than fixing code with
   no callers; the corrected versions are in `legacy/` for reference.

## 4. The bug this audit uncovered: the SDL resolution callback was dead

`libqemu-system-x86_64.so` used to reference `Android_JNI_SetVMResolution` as a
**weak** symbol (`ui/sdl2-2d.c`), so that the standalone test binary links
without `libcompat-limbo`. `link-qemu-so.py` appended `-lcompat-limbo`, but
with `--as-needed` the linker dropped it: a weak reference does not count as a
use, so **`libcompat-limbo.so` never appeared in `DT_NEEDED`**.

At runtime bionic resolves a `dlopen`ed library's symbols against the global
group plus *its own* `DT_NEEDED` set — not against the caller's. QEMU is
`dlopen`ed by `liblimbo.so`, so the weak symbol resolved to `NULL`, the
`if (Android_JNI_SetVMResolution)` guard failed, and the guest resolution was
never reported to the Java side. Machines booted and resized without the
surface ever being told.

Fix (`build/tools/link-qemu-so.py`):

```python
args += ["-Wl,--no-as-needed", "-lcompat-limbo", "-Wl,--as-needed"]
```

Verified with `llvm-readelf -d libqemu-system-x86_64.so | grep NEEDED` →
`libcompat-limbo.so`, and on device (bench = ac97/SDL, UEFI boot):

```
I limbo_compat_qemu.c: SetVMResolution 640x480 (attached_here=0)
I limbo_compat_qemu.c: SetVMResolution 1280x800 (attached_here=0)
```

`attached_here=0` confirms the display thread was already attached, i.e. the
common case now costs one `GetEnv` + one Java call — no thread, no attach, no
detach, no locks.

A side effect worth knowing: `libqemu-system-*.so` now has
`DT_NEEDED libcompat-limbo.so`, so `limbo-smoke` (and anything else that
`dlopen`s the QEMU library) needs `libcompat-limbo.so` on `LD_LIBRARY_PATH` —
the app's `lib/arm64` directory already contains it.

## 4b. What the SAF path really is now

The old shims existed because the Java side could not hand QEMU an open file
descriptor: it mangled the URI into `/content//...^^^` and native code called
back into Java for a descriptor. The QEMU 11 port replaced that with
`/proc/self/fd/<n>` — which is **broken for SAF files on scoped storage**:

```
-drive ...,file=/proc/self/fd/190: Could not open '/proc/self/fd/190': Permission denied
```

`/proc/self/fd/N` is a symlink; re-opening it resolves back to
`/storage/emulated/0/Download/...` and the app has no grant for that path.
The descriptor we hold is fine, the path is not.

QEMU has a protocol for exactly this: `-add-fd fd=N,set=S` registers a
descriptor and `file=/dev/fdset/S` makes the block layer `dup()` it
(`qemu_open()` → `monitor_fdset_dup_fd_add()`), with no path lookup at all.
`FileUtils.encodeDocumentFilePath()` now returns `/dev/fdset/<set>` and
`VMExecutor.prepareParams()` appends the matching `-add-fd` pairs. Two
descriptors per set (`rw` + `r`) because the matcher compares the access mode
exactly; `FD_CLOEXEC` is cleared first, otherwise QEMU rejects the fd
("fd is not valid or already in use").

Verified on device with a qcow2 in `/sdcard/Download/67` picked through SAF:

```
E VMExecutor: 24: index=0,if=ide,media=disk,file=/dev/fdset/0
E VMExecutor: 66: -add-fd
E VMExecutor: 68: -add-fd
# qemu.log: no drive error, guest boots, /proc/<pid>/fd shows the dup'ed
# /storage/emulated/0/Download/67/test.qcow2 handles
```

Consequences: `limbo_compat_filesystem.*` is not needed and neither is
`get_fd()` on the Java side.

Two paths cannot use "/dev/fdset":

* `-kernel`/`-initrd` — QEMU opens them with `fopen()` and
  `g_mapped_file_new()` (`hw/i386/x86-common.c`), pure path APIs. The Java
  side copies those (small, read-once) files into `cache/limbo/saf-*.bin` and
  passes the real path. Verified on device: a SAF-picked kernel reaches
  `VFS: Unable to mount root fs` and a SAF-picked initrd prints
  `Freeing initrd memory: 9436K` followed by `/bin/sh`.
* Runtime media change (QMP hotplug) — `-add-fd` is command-line only and QMP
  `add-fd` needs `SCM_RIGHTS`. QEMU runs in this process, so `monitor/fds.c`
  exports `limbo_fdset_add()` and this library reaches it with
  `dlopen(RTLD_NOLOAD)` (`Java_com_max2idea_android_limbo_files_FileUtils_nativeAddFd`).

## 5. Size and ABI

| | before (`HEAD`) | before (working tree, 2026-11-13) | after |
|---|---|---|---|
| file size | 19,904 B | 16,488 B | **6,288 B** |
| `text` | 16,675 | 13,138 | **3,006** |
| `data` | 952 | — | 480 |
| `bss` | 101 | — | 80 |
| exported symbols | 30 | 30 | **2** |
| `DT_NEEDED` | liblog, libc, libm, libstdc++, libdl | same | **liblog, libc** |

Exported ABI (everything else is hidden with `-fvisibility=hidden` +
`--gc-sections`):

```
T set_jni(JNIEnv*, jobject, jclass, const char*, const char*)
T Android_JNI_SetVMResolution(int width, int height)
```

`set_jni` keeps its exact signature and semantics for `liblimbo.so`
(`vm-executor-jni.c:67`), including the vestigial `storage_dir`/`limbo_dir`
arguments — they are simply unused now.

## 6. Verification

Host unit tests (`build/compat-tests/`, mock `JNIEnv`; one `fork()` per case so
the one-shot globals reset for free) — **`PASS: 0 failure(s)`**:

```sh
build/compat-tests/run.sh
```

| case | asserts |
|---|---|
| notification before `set_jni()` | no Java call, no `GetEnv`, no attach |
| cached method id, attached thread | one `GetStaticMethodID`, one `NewGlobalRef`, idempotent second `set_jni`, no per-call lookup, no attach/detach, 3 forwards = 3 `GetEnv` |
| attach/detach only when needed | 1 attach + 1 detach per notification on a detached thread, balanced |
| Java exception | pending exception cleared exactly once |
| missing `onVMResolutionChanged` | `set_jni` fails closed, exception swallowed, no callback |
| NULL env / NULL receiver | rejected, no callback, logged |

Device: see §4 — the two `SetVMResolution` lines prove the JNI bridge, and the
Android-side `Log.d("VM resolution changed to WxH")`
(`LimboSDLActivity.resolutionChanged()`) sits behind them. The callback logs at
INFO on purpose: several ROMs drop DEBUG/VERBOSE, and this was the only trace
when the weak reference was still unresolved.

## 7. Building

```sh
# the sources here are built into liblimbo.so (the separate compat .so is gone)
build/tools/build-limbo.sh

# host tests (needs jdk-17/include/jni.h and clang)
build/compat-tests/run.sh
```

`Android.mk` (the legacy ndk-build path) still works and compiles the same four
files; it no longer pulls `$(NDK_ROOT)/sources/android/cpufeatures/cpu-features.c`
and now sets `-fvisibility=hidden -ffunction-sections -fdata-sections`.

The device build is plain clang from `envsetup.sh` (no meson, no ndk-build):

```
--sysroot=$SYSROOT -march=armv8-a+simd+crc+crypto -mtune=cortex-a76 -O3 -fPIC
-D__LIMBO__ -D__ANDROID__ -DANDROID -D__linux__ -DCONFIG_LINUX
-I jni/compat -include limbo_logutils.h -Wall -Wextra
-fvisibility=hidden -ffunction-sections -fdata-sections
```
