/* Reference-only corrected sigtimedwait() override. See the .cpp and REPORT. */
#ifndef LIMBO_COMPAT_SIGNALS_LEGACY_H
#define LIMBO_COMPAT_SIGNALS_LEGACY_H

#include <signal.h>
#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

int limbo_legacy_sigtimedwait(const sigset_t *set, siginfo_t *info,
                              const struct timespec *timeout);

#ifdef __cplusplus
}
#endif

#endif
