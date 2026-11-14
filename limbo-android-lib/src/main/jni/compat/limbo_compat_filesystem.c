/*
 * Intentionally empty.
 *
 * This file used to hold the QEMU 5.1 era file-path shims:
 *
 *     android_fopen() android_open() android_close() android_stat()
 *     android_mkstemp() lockf()
 *     plus the JNI get_fd()/close_fd() bridge and the two pthread_create()
 *     wrappers around them.
 *
 * They were wired into QEMU by objcopy --redefine-sym (see the 5.1-era
 * jni/Makefile and android-qemu-build.mak), then wrapped into extra fopen()
 * attempts under storage_base_dir / limbo_base_dir for content:// URIs.
 *
 * The QEMU 11.1.3 build renames nothing and SAF now passes
 * /proc/self/fd/<n> down to QEMU (FileUtils.encodeDocumentFilePath()), so
 * `nm -D --undefined-only` over all 17 shipped .so files finds zero importers
 * for any of them. They also carried real bugs (unbounded strcpy/strcat into
 * a 256-byte stack buffer, inverted fd checks, printf() on the hot path).
 *
 * Deleting them was the safest fix. The corrected implementation is kept for
 * reference - and host-tested - in src/legacy/limbo_compat_filesystem_legacy.c
 * if a future build ever needs the mechanism back.
 *
 * The file is kept (rather than removed) so that the existing
 * compat/Android.mk source list keeps working unchanged.
 */
