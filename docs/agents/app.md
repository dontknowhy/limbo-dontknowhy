# App and JNI

## Modules

- `limbo-android-lib` — everything reusable: Activities, machine model, JNI control
  plane, `jni/compat`, resources/assets. Builds `liblimbo.so`.
- `limbo-android-x86` — thin application module: `LimboEmuActivity` entry point, manifest,
  app id/version, and the `jniLibs` directory that receives the QEMU libraries.

Java packages keep the upstream split: `com.max2idea.android.limbo.*` (implementation)
and `com.limbo.emu.dontknowhy.LimboEmuActivity` (the fork's entry point, sets
`Config.Arch.x86_64`, `enableKVM`, and loads the QEMU library). Do not merge them.

## Start / stop path

```
LimboEmuActivity (extends LimboActivity)
  → MachineController (singleton state, owns MachineExecutor)
    → MachineService (foreground Service; QEMU runs on "LimboThread",
       Config.stackSize, optional MAX_PRIORITY)
      → VMExecutor.start()
        → jni/limbo/vm-executor-jni.c: dlopen(libqemu-system-x86_64.so)
          dlsym(qemu_init / qemu_main_loop / qemu_cleanup)
```

QEMU runs **in the app process**. `VMExecutor.start()` calls the native `start()` with
`(Config.storagedir, basefileDir, libName, libPath, SDLHintScale, params)`. The JNI side
redirects stdout/stderr to `<basefileDir>/qemu.log` (`cache/limbo/qemu.log`).

`stop(restart)` either calls `qemu_system_reset_request()` (restart) or
`qemu_system_shutdown_request()` (stop). `MachineService` clears `limboThread` and calls
`MachineController.onServiceStopped()`; status is derived from `getCurrStatus()`, not from
a boolean field.

`qemu_init()` cannot run twice in one process. `VMExecutor.qemuInitializedOnce` refuses
the second start; the UI must tell the user to force-stop/reopen the app. Do not remove
this guard or attempt same-process stop→start.

## QEMU command line

`VMExecutor.prepareParams()` appends groups in this order: UI, CPU/board, drives,
removable drives, boot, graphics, audio, network, generic, state, advanced, acceleration,
then the collected SAF `-add-fd` arguments. New options belong in the matching
`add*Options()` method; `printParams()` logs the final argv.

Sources of configuration:

- `Config` — paths, defaults, VNC/QMP ports, SDL scale hint.
- `Machine` / `MachineController` — per-VM settings.
- `LimboSettingsManager` — app preferences.
- `LimboApplication.getBasefileDir()` — `cacheDir/limbo/`, passed as QEMU `-L` and used
  for firmware/temp files. `Config.storagedir` is the external storage root.

## SAF / content:// disks

`FileUtils.encodeDocumentFilePath()` opens a `ParcelFileDescriptor`, clears
`FD_CLOEXEC`, keeps the fd open in a static list, and returns `/dev/fdset/<set>`. The
matching `-add-fd fd=N,set=S` lines are accumulated in `FileUtils.getSafFdArgs()` and
appended by `prepareParams()`.

`/proc/self/fd/N` is not usable under scoped storage: the magic link resolves back to the
content URI and QEMU gets `EACCES`. Do not reintroduce the old
`/content//...^^^` encoding either.

Running-VM media changes go through `FileUtils.nativeAddFd()` →
`limbo_fdset_add()` (patch 0006), because QMP's `add-fd` needs `SCM_RIGHTS` and the Java
socket client cannot send fds. `-kernel`/`-initrd` cannot use fdsets (QEMU fopen/mmap by
path), so they are copied into `cache/limbo/saf-*.bin` first.

## Display modes and QMP

- SDL: `LimboSDLActivity extends org.libsdl.app.SDLActivity`. QEMU gets `-display sdl`
  (via the SDL build) and the SDL surface is the UI.
- VNC: `LimboActivity` starts QEMU with `-vnc <host:port>` and `-monitor vc`. Without a
  password it binds localhost; with a password it uses `:1,password` and the password is
  changed after startup.
- `QmpClient` talks QMP either over a unix socket
  (`cacheDir/qmpsocket`, default) or TCP `127.0.0.1:4444` when external QMP is enabled.
  It is used for `sendkey` (VNC special keys), status, password changes and removable
  media. QMP can be disabled in settings; code paths must tolerate that.

## Audio

`-audiodev aaudio|opensles,id=sdl,out.buffer-length=12000`. AAudio is chosen on API 26+
when enabled, otherwise OpenSL ES. Both are native QEMU drivers
(`audio/openslesaudio.c`, `audio/aaudioaudio.c`) and support capture; SDL's Android audio
driver is not used because VNC has no SDL video context.

## qemu-img

`libqemu-img.so` exports `limbo_img_create()` (patch 0005) which calls `bdrv_create()`
directly. JNI: `VMExecutor.nativeCreateImage(path, fmt, ...)`. Supports creating
qcow2/raw/vmdk/vdi/vhdx/qed/vpc/parallels; bochs/cloop/dmg are open/convert-only.
Java-side UI defaults raw images to `.img`.

## Firmware, assets and the pflash rule

`FileInstaller` copies assets to `cache/limbo/`. For `.fd/.bin/.rom` it validates size and
CRC32, and compares `cache/limbo/.assets-tag` (`versionCode-lastUpdateTime`) to decide
whether to re-verify everything. `*xbzj*` files are user-supplied and always skipped.
`.fd` files are only size-checked because QEMU writes NVRAM variables into them.

Attach **one** `-pflash` only. If both `ENABLE_32_UEFI` and `ENABLE_64_UEFI` are set,
`VMExecutor` picks per architecture (`edk2-i386-code.fd` for 32-bit,
`edk2-x86_64-code.fd` otherwise). Two pflash devices explode the mapping count past
`vm.max_map_count` and Scudo-OOM under SDL. `-bios bios-xbzj.bin` is added only when both
UEFI options are off.

## UI extras

- `ScreenSaver` (`ui/`) runs after `screensaverTimeout` seconds (default 30, 0 disables).
  SDL hides system bars; VNC shows the bouncing DVD logo (`dvd-logo.svg`). Tap wakes it.
  It must not trigger while the IME is visible (`KeyboardUtils.isKeyboardVisible()`).
- `SpecialKeysBar` (`ui/`) is attached to `android.R.id.content` above the IME:
  modifiers (Ctrl/Alt/Shift/Win) latch until the next key from any source, then release;
  VNC falls back to one-shot because QMP `sendkey` is atomic.
- The window must use `SOFT_INPUT_ADJUST_RESIZE`: targetSdk 29 means Android 11+ does not
  dispatch IME insets (`WindowInsets.Type.ime()` stays 0), so bottom-docked views would
  otherwise sit under the keyboard.

## Where to change what

| Change | Start here |
|---|---|
| Add/alter a QEMU option | `VMExecutor.prepareParams()` + the matching `add*` |
| Machine lifecycle/status | `MachineController`, `MachineService` |
| Disk/SAF | `FileUtils`, `DrivesDialogBox`, patch 0006 |
| VNC/QMP behaviour | `QmpClient`, `addUIOptions()` |
| Screen/keys UI | `LimboActivity`, `LimboSDLActivity`, `ui/` |
| Native entry/symbols | `jni/limbo/vm-executor-jni.c`, `jni/compat/` |
