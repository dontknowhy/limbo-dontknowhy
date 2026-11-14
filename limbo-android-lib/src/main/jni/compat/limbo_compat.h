#ifndef LIMBO_COMPAT_H
#define LIMBO_COMPAT_H

#include <jni.h>
#include <pthread.h>

/*
 * libcompat-limbo.so -- what is left of the QEMU 5.1 era "compat" library.
 *
 * Exported ABI (everything else is built with -fvisibility=hidden):
 *
 *   set_jni()                       called by liblimbo.so (setup_jni())
 *   Android_JNI_SetVMResolution()   weak-ref'd by libqemu-system-*.so
 *
 * See REPORT.md for the symbol audit that removed valloc/strchrnul/lockf/
 * sigtimedwait/android_{fopen,open,stat,mkstemp,close}/android_getCpu*.
 */

#if defined(__GNUC__)
#define LIMBO_COMPAT_EXPORT __attribute__((visibility("default")))
#else
#define LIMBO_COMPAT_EXPORT
#endif

#ifdef __cplusplus
extern "C" {
#endif

/*
 * Registers the JavaVM and caches VMExecutor.onVMResolutionChanged(II)V.
 *
 * The storage_dir/limbo_dir arguments are vestigial: SAF paths reach QEMU as
 * /proc/self/fd/<n> (FileUtils.encodeDocumentFilePath()), so nothing resolves
 * paths against these prefixes any more. They are kept only so that
 * liblimbo.so's existing setup_jni() call keeps working unchanged.
 *
 * Idempotent; safe to call again after a machine restart.
 */
LIMBO_COMPAT_EXPORT
void set_jni(JNIEnv *env, jobject obj, jclass cls,
             const char *storage_dir, const char *limbo_dir);

/* --- internal, hidden; used by limbo_compat_qemu.c ----------------------- */

/* NULL until set_jni() succeeded. Acquire-loads the published state. */
JavaVM *limbo_compat_jvm(void);
jclass limbo_compat_vmexecutor_class(void);
jmethodID limbo_compat_vm_resolution_method(void);

#ifdef __cplusplus
}
#endif

#endif
