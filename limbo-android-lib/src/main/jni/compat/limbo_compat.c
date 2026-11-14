/*
 * Limbo compat: the JNI bridge between liblimbo.so and QEMU's display code.
 *
 * liblimbo.so (setup_jni(), called once per VM start, before qemu_init) hands
 * us the JavaVM and the VMExecutor class; QEMU's SDL backend calls
 * Android_JNI_SetVMResolution() whenever the guest surface is (re)created.
 *
 * What used to live here and no longer does:
 *   - valloc()        -- bionic has it; nothing in the .so set imports ours
 *   - strchrnul()     -- bionic has it since API 24; nothing imports ours
 *   - the /content//...^^^ path resolvers and their JNI get_fd()/close_fd()
 *     round-trip -- SAF now hands QEMU /proc/self/fd/<n> directly
 *   - cpufeatures (android_getCpu*) -- only needed by 32-bit ARM pixman/SDL,
 *     and this project is arm64-only
 * Every removal is backed by `nm -D --undefined-only` evidence in REPORT.md.
 */

#include <jni.h>
#include <pthread.h>

#include "limbo_logutils.h"
#include "limbo_compat.h"

/*
 * Published a single time by set_jni(). Readers never take the lock: g_vm is
 * stored last with release semantics, and the callback fields are written
 * before it, so an acquire load of g_vm also publishes them.
 */
static JavaVM *g_vm;
static jclass g_vmexecutor_class;
static jmethodID g_vm_resolution_method;

/* Statically initialised: no init step that can fail and leave a broken lock
 * behind (the old code returned early on pthread_mutex_init() failure and the
 * callers happily kept using the uninitialised mutex). */
static pthread_mutex_t g_jni_lock = PTHREAD_MUTEX_INITIALIZER;

JavaVM *limbo_compat_jvm(void)
{
    return __atomic_load_n(&g_vm, __ATOMIC_ACQUIRE);
}

jclass limbo_compat_vmexecutor_class(void)
{
    return g_vmexecutor_class;
}

jmethodID limbo_compat_vm_resolution_method(void)
{
    return g_vm_resolution_method;
}

void set_jni(JNIEnv *env, jobject obj, jclass cls,
             const char *storage_dir, const char *limbo_dir)
{
    (void)storage_dir;
    (void)limbo_dir;

    if (env == NULL) {
        LOGE("set_jni: NULL JNIEnv");
        return;
    }

    pthread_mutex_lock(&g_jni_lock);

    if (__atomic_load_n(&g_vm, __ATOMIC_RELAXED) != NULL) {
        /* Second call (machine restart / re-entrant start): nothing to do.
         * The old code re-ran pthread_mutex_init() on a live mutex here. */
        LOGW("set_jni: already initialised, keeping existing state");
        pthread_mutex_unlock(&g_jni_lock);
        return;
    }

    JavaVM *vm = NULL;
    if ((*env)->GetJavaVM(env, &vm) != JNI_OK || vm == NULL) {
        LOGE("set_jni: GetJavaVM failed");
        pthread_mutex_unlock(&g_jni_lock);
        return;
    }

    /* The callback is a *static* Java method, so the receiver instance is not
     * needed. The old code took a NewGlobalRef() on it, which pinned a
     * VMExecutor (and through it its controller/activity) for the lifetime of
     * the process even across machine restarts. */
    if (obj == NULL) {
        LOGE("set_jni: NULL receiver, cannot resolve VMExecutor class");
        pthread_mutex_unlock(&g_jni_lock);
        return;
    }

    jclass local_cls = cls;
    if (local_cls == NULL) {
        local_cls = (*env)->GetObjectClass(env, obj);
        if (local_cls == NULL) {
            (*env)->ExceptionClear(env);
            LOGE("set_jni: GetObjectClass failed");
            pthread_mutex_unlock(&g_jni_lock);
            return;
        }
    }

    jmethodID mid = (*env)->GetStaticMethodID(env, local_cls,
                                             "onVMResolutionChanged", "(II)V");
    if (mid == NULL) {
        /* JNI leaves a pending NoSuchMethodError/ExceptionInInitializerError
         * behind; swallow it, otherwise it surfaces later on an unrelated JNI
         * call made by whoever owns this thread. */
        (*env)->ExceptionClear(env);
        LOGE("set_jni: VMExecutor.onVMResolutionChanged(II)V not found");
        pthread_mutex_unlock(&g_jni_lock);
        return;
    }

    jclass global_cls = (jclass)(*env)->NewGlobalRef(env, local_cls);
    if (global_cls == NULL) {
        (*env)->ExceptionClear(env);
        LOGE("set_jni: NewGlobalRef failed");
        pthread_mutex_unlock(&g_jni_lock);
        return;
    }

    g_vmexecutor_class = global_cls;
    g_vm_resolution_method = mid;
    __atomic_store_n(&g_vm, vm, __ATOMIC_RELEASE);

    pthread_mutex_unlock(&g_jni_lock);

    LOGV("set_jni: JNI bridge ready");
}
