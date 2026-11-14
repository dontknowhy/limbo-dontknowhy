/*
 * Limbo compat: hand a Java-owned file descriptor to the running QEMU.
 *
 * The app needs this when the user changes removable media while the VM is
 * running: "-add-fd" only exists on the command line, and QMP's add-fd needs
 * SCM_RIGHTS over the monitor socket, which the Java QMP client cannot send.
 * QEMU is dlopen()ed in this very process, so we just call the exported
 * limbo_fdset_add() from monitor/fds.c after finding the library handle.
 *
 * See jni/compat/REPORT.md ("SAF") and FileUtils.encodeDocumentFilePath().
 */

#include <dlfcn.h>
#include <jni.h>

#include "limbo_logutils.h"
#include "limbo_compat.h"

typedef int (*limbo_fdset_add_fn)(int fd, int fdset_id);

LIMBO_COMPAT_EXPORT
jint Java_com_max2idea_android_limbo_files_FileUtils_nativeAddFd(
        JNIEnv *env, jclass cls, jstring qemu_library, jint fd, jint fdset_id)
{
    limbo_fdset_add_fn add;
    const char *name;
    void *handle;
    jint ret;

    (void)cls;

    if (env == NULL || qemu_library == NULL || fd < 0 || fdset_id < 0) {
        return -1;
    }

    name = (*env)->GetStringUTFChars(env, qemu_library, NULL);
    if (name == NULL) {
        return -1;
    }

    /* RTLD_NOLOAD: the library is already loaded (liblimbo dlopen()ed it
     * before qemu_init), we only want a handle to look up a symbol. */
    handle = dlopen(name, RTLD_NOLOAD | RTLD_LAZY);
    if (handle == NULL) {
        LOGE("nativeAddFd: %s is not loaded: %s", name, dlerror());
        (*env)->ReleaseStringUTFChars(env, qemu_library, name);
        return -1;
    }
    (*env)->ReleaseStringUTFChars(env, qemu_library, name);

    add = (limbo_fdset_add_fn)dlsym(handle, "limbo_fdset_add");
    dlclose(handle);
    if (add == NULL) {
        LOGE("nativeAddFd: limbo_fdset_add() missing from the QEMU library");
        return -1;
    }

    ret = add(fd, fdset_id);
    if (ret != 0) {
        LOGE("nativeAddFd: fdset %d, fd %d rejected", (int)fdset_id, (int)fd);
    }
    return ret;
}
