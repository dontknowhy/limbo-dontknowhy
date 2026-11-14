/* Reference-only corrected legacy path resolvers. See the header. */

#include <errno.h>
#include <fcntl.h>
#include <stdarg.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

#include "limbo_compat_filesystem_legacy.h"

#define LIMBO_CONTENT_PREFIX  "/content/"
#define LIMBO_CONTENT_PREFIX_LEN (sizeof(LIMBO_CONTENT_PREFIX) - 1)

static int is_content_path(const char *path)
{
    return path != NULL &&
           strncmp(path, LIMBO_CONTENT_PREFIX, LIMBO_CONTENT_PREFIX_LEN) == 0;
}

int limbo_join_prefixed(char *dst, size_t dstsz,
                        const char *prefix, const char *path)
{
    size_t plen;
    size_t skip = 0;
    int n;

    if (dst == NULL || dstsz == 0) {
        errno = EINVAL;
        return -1;
    }

    plen = strlen(prefix);

    /* prefix "a/" + path "/b" must not become "a//b" */
    if (plen > 0 && prefix[plen - 1] == '/' && path[0] == '/') {
        skip = 1;
    }

    n = snprintf(dst, dstsz, "%s%s", prefix, path + skip);
    if (n < 0) {
        errno = EINVAL;
        return -1;
    }
    if ((size_t)n >= dstsz) {
        /* The old code strcpy()/strcat()'d here and smashed the stack. */
        errno = ENAMETOOLONG;
        return -1;
    }
    return 0;
}

FILE *limbo_legacy_fopen(const limbo_path_env *env, const char *path,
                         const char *mode)
{
    char joined[1024];
    FILE *f;

    if (path == NULL || mode == NULL) {
        errno = EINVAL;
        return NULL;
    }

    if (is_content_path(path)) {
        int fd;
        if (env == NULL || env->content_open == NULL) {
            errno = ENOENT;
            return NULL;
        }
        fd = env->content_open(path, env->content_opaque);
        if (fd < 0) {           /* fd 0 is a perfectly good descriptor */
            return NULL;
        }
        return fdopen(fd, mode);
    }

    f = fopen(path, mode);
    if (f != NULL) {
        return f;
    }

    if (env != NULL && env->storage_prefix != NULL) {
        if (limbo_join_prefixed(joined, sizeof(joined),
                                env->storage_prefix, path) == 0) {
            f = fopen(joined, mode);
            if (f != NULL) {
                return f;
            }
        }
    }

    if (env != NULL && env->limbo_prefix != NULL) {
        if (limbo_join_prefixed(joined, sizeof(joined),
                                env->limbo_prefix, path) == 0) {
            f = fopen(joined, mode);
            if (f != NULL) {
                return f;
            }
        }
    }

    return NULL;
}

int limbo_legacy_open(const limbo_path_env *env, const char *path, int flags, ...)
{
    char joined[1024];
    mode_t mode = 0;
    int fd;
    int saved_errno = ENOENT;

    if (path == NULL) {
        errno = EINVAL;
        return -1;
    }

    if (flags & O_CREAT) {
        va_list ap;
        va_start(ap, flags);
        mode = (mode_t)va_arg(ap, int);
        va_end(ap);
    }

    if (is_content_path(path)) {
        if (env == NULL || env->content_open == NULL) {
            errno = ENOENT;
            return -1;
        }
        return env->content_open(path, env->content_opaque);
    }

    fd = open(path, flags, mode);
    if (fd >= 0) {              /* the old code returned -1 for fd == 0 */
        return fd;
    }
    saved_errno = errno;

    if (env != NULL && env->storage_prefix != NULL &&
        limbo_join_prefixed(joined, sizeof(joined),
                            env->storage_prefix, path) == 0) {
        fd = open(joined, flags, mode);
        if (fd >= 0) {
            return fd;
        }
        saved_errno = errno;
    }

    if (env != NULL && env->limbo_prefix != NULL &&
        limbo_join_prefixed(joined, sizeof(joined),
                            env->limbo_prefix, path) == 0) {
        fd = open(joined, flags, mode);
        if (fd >= 0) {
            return fd;
        }
        saved_errno = errno;
    }

    errno = saved_errno;
    return -1;
}

int limbo_legacy_stat(const limbo_path_env *env, const char *path,
                      struct stat *st)
{
    char joined[1024];
    int saved_errno = ENOENT;

    if (path == NULL || st == NULL) {
        errno = EINVAL;
        return -1;
    }

    if (is_content_path(path)) {
        int fd;
        int res;
        if (env == NULL || env->content_open == NULL) {
            errno = ENOENT;
            return -1;
        }
        fd = env->content_open(path, env->content_opaque);
        if (fd < 0) {
            return -1;
        }
        res = fstat(fd, st);
        saved_errno = errno;
        close(fd);
        errno = saved_errno;
        return res;
    }

    if (stat(path, st) == 0) {
        return 0;
    }
    saved_errno = errno;

    if (env != NULL && env->storage_prefix != NULL &&
        limbo_join_prefixed(joined, sizeof(joined),
                            env->storage_prefix, path) == 0) {
        if (stat(joined, st) == 0) {
            return 0;
        }
        saved_errno = errno;
    }

    if (env != NULL && env->limbo_prefix != NULL &&
        limbo_join_prefixed(joined, sizeof(joined),
                            env->limbo_prefix, path) == 0) {
        if (stat(joined, st) == 0) {
            return 0;
        }
        saved_errno = errno;
    }

    errno = saved_errno;
    return -1;
}

int limbo_legacy_mkstemp(const limbo_path_env *env, char *template_path,
                         size_t template_size)
{
    char joined[1024];
    const char *prefix;
    int fd;
    size_t len;

    if (template_path == NULL) {
        errno = EINVAL;
        return -1;
    }

    prefix = (env != NULL && env->limbo_prefix != NULL)
                 ? env->limbo_prefix
                 : (env != NULL ? env->storage_prefix : NULL);
    if (prefix == NULL) {
        prefix = "";
    }

    if (limbo_join_prefixed(joined, sizeof(joined), prefix, template_path) != 0) {
        return -1;
    }

    fd = mkstemp(joined);
    if (fd < 0) {               /* the old code treated success as failure */
        return -1;
    }

    /* The original never told the caller the randomised name, so the file it
     * had just created could not be reopened through the compat layer. */
    len = strlen(joined);
    if (template_size > len) {
        memcpy(template_path, joined, len + 1);
    }

    return fd;
}
