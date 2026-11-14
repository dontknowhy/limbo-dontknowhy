#ifndef LIMBO_COMPAT_FD_H
#define LIMBO_COMPAT_FD_H

/*
 * Intentionally empty: the android_{fopen,open,close,stat,mkstemp}() and
 * lockf() shims that used to be declared here have no importers left in the
 * QEMU 11.1.3 .so set. See limbo_compat_filesystem.c and REPORT.md.
 *
 * The corrected reference implementation lives in
 * src/legacy/limbo_compat_filesystem_legacy.h (not built into the .so).
 */

#include <jni.h>
#include <sys/stat.h>
#include <stdio.h>

#endif
