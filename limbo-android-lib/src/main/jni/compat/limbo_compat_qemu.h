#ifndef LIMBO_COMPAT_QEMU_H
#define LIMBO_COMPAT_QEMU_H

#include <jni.h>
#include "limbo_compat.h"   /* LIMBO_COMPAT_EXPORT */

typedef struct sdl_res_t {
	int width;
	int height;
} sdl_res_t;

/* Weakly referenced by libqemu-system-*.so (ui/sdl2-2d.c), so this must stay
 * exported with default visibility. Forwards to
 * VMExecutor.onVMResolutionChanged(II)V. */
LIMBO_COMPAT_EXPORT
void Android_JNI_SetVMResolution(int width, int height);

#endif
