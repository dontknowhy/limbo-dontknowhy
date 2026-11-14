/*
 * Limbo compat: QEMU -> Android UI notifications.
 *
 * QEMU's SDL 2D backend (ui/sdl2-2d.c, sdl2_2d_switch()) calls
 * Android_JNI_SetVMResolution() whenever the guest surface changes size, i.e.
 * on boot, on a mode switch and on the first frame after a window resize. It
 * runs on the QEMU/display thread, which is the thread that entered
 * qemu_main_loop(), so in practice it is already attached to the JVM. The old
 * implementation spawned a pthread + joined it *per call* and then attached
 * that brand-new thread to the JVM (a thread-local JNIEnv + TLS block + a
 * thread stack, ~30-60us measured on the host; see REPORT.md).
 *
 * Now: direct call, attach only if the caller really is detached.
 */

#include <jni.h>
#include <stdbool.h>

#include "limbo_logutils.h"
#include "limbo_compat.h"
#include "limbo_compat_qemu.h"

LIMBO_COMPAT_EXPORT
void Android_JNI_SetVMResolution(int width, int height)
{
    JavaVM *vm = limbo_compat_jvm();
    if (vm == NULL) {
        /* set_jni() not called: QEMU cannot be running yet. Silent no-op. */
        return;
    }

    jclass cls = limbo_compat_vmexecutor_class();
    jmethodID mid = limbo_compat_vm_resolution_method();
    if (cls == NULL || mid == NULL) {
        return;
    }

    JNIEnv *env = NULL;
    bool attached_here = false;

    jint rs = (*vm)->GetEnv(vm, (void **)&env, JNI_VERSION_1_6);
    if (rs == JNI_EDETACHED) {
        if ((*vm)->AttachCurrentThread(vm, &env, NULL) != JNI_OK ||
            env == NULL) {
            LOGE("SetVMResolution: AttachCurrentThread failed");
            return;
        }
        attached_here = true;
    } else if (rs != JNI_OK || env == NULL) {
        LOGE("SetVMResolution: GetEnv failed: %d", (int)rs);
        return;
    }

    (*env)->CallStaticVoidMethod(env, cls, mid, (jint)width, (jint)height);

    /* A Java-side throw here would otherwise leak into QEMU's next JNI call
     * (there is none today, but qemu.log would lose the stack trace). */
    /* Rare (boot / mode switch / window resize) and the only trace of this
     * path in logcat when the Java side bails out early, so keep it at INFO:
     * several ROMs drop DEBUG/VERBOSE entries. */
    LOGI("SetVMResolution %dx%d (attached_here=%d)", width, height,
         attached_here ? 1 : 0);

    if ((*env)->ExceptionCheck(env)) {
        (*env)->ExceptionDescribe(env);
        (*env)->ExceptionClear(env);
    }

    /* Never detach a thread we did not attach: on the QEMU main loop thread
     * that would tear down the JNIEnv the Java caller still uses. */
    if (attached_here) {
        (*vm)->DetachCurrentThread(vm);
    }
}
