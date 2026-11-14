/*
 * Reference-only: the *corrected* version of the old compat/ path resolvers.
 *
 * This file is NOT part of libcompat-limbo.so (see REPORT.md: the QEMU 11.1.3
 * .so set imports none of these symbols). It is kept so that
 *   (a) the bugs of the original code have a documented, reviewed fix, and
 *   (b) tests/test_legacy_paths.c can exercise the pure path/probe logic on
 *       the host.
 *
 * Differences from the 5.1 original, in the order they appear:
 *   - no JNI: the content:// branch takes a callback instead of reaching for
 *     a global JNIEnv, so the logic is testable and free of global state
 *   - bounded path assembly (limbo_join_prefixed): no strcpy/strcat into a
 *     256-byte stack buffer; truncation becomes ENAMETOOLONG
 *   - fd tests are `>= 0` (fd 0 is a valid descriptor) and `!fd` is gone
 *   - no printf() on any path (the original logged every android_close())
 *   - mkstemp() failures are detected with `res < 0` instead of `if (res)`
 *   - caller-supplied prefixes instead of mutable global strings
 */
#ifndef LIMBO_COMPAT_FILESYSTEM_LEGACY_H
#define LIMBO_COMPAT_FILESYSTEM_LEGACY_H

#include <stddef.h>
#include <stdio.h>
#include <sys/stat.h>
#include <sys/types.h>

#ifdef __cplusplus
extern "C" {
#endif

/* Resolves a legacy "/content/..." path to a raw fd, or -1. */
typedef int (*limbo_content_fd_fn)(const char *path, void *opaque);

typedef struct {
    const char *storage_prefix;      /* trailing '/' optional; NULL = unused */
    const char *limbo_prefix;        /* trailing '/' optional; NULL = unused */
    limbo_content_fd_fn content_open; /* NULL -> content:// unsupported */
    void *content_opaque;
} limbo_path_env;

/*
 * dst = prefix + '/' + path (+ NUL), collapsing a duplicate separator.
 * Returns 0, or -1 with errno = ENAMETOOLONG when the result does not fit.
 */
int limbo_join_prefixed(char *dst, size_t dstsz,
                        const char *prefix, const char *path);

FILE *limbo_legacy_fopen(const limbo_path_env *env, const char *path,
                         const char *mode);
int limbo_legacy_open(const limbo_path_env *env, const char *path, int flags, ...);
int limbo_legacy_stat(const limbo_path_env *env, const char *path,
                      struct stat *st);
/* template_path is rewritten in place, exactly like mkstemp(3). */
int limbo_legacy_mkstemp(const limbo_path_env *env, char *template_path,
                         size_t template_size);

#ifdef __cplusplus
}
#endif

#endif
