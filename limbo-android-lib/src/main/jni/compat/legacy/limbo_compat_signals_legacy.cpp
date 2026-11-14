/*
 * Reference-only: corrected version of the old compat/ sigtimedwait().
 *
 * Not built into libcompat-limbo.so (no importer left; see REPORT.md).
 *
 * The original relied on an implicit assumption about bionic's sigset_t
 * layout: `union { sigset_t bionic; uint32_t kernel[2]; }` and passed
 * &in_set.bionic as the kernel's 64-bit sigset. That works only because
 * bionic's sigset_t is a single 64-bit word on arm64. Here the assumption is
 * checked by the compiler instead of by hope.
 */
#include <cerrno>
#include <cstdint>
#include <ctime>
#include <signal.h>
#include <sys/syscall.h>
#include <unistd.h>

#include "limbo_compat_signals_legacy.h"

namespace {

/* The kernel's rt_sigset_t for arm64 is a u64; bionic's sigset_t must match
 * bit-for-bit because it is passed straight through to the syscall. */
static_assert(sizeof(sigset_t) == sizeof(uint64_t),
              "unexpected bionic sigset_t width");

union kernel_sigset {
    sigset_t bionic;
    uint32_t word[2];
};

}  // namespace

int limbo_legacy_sigtimedwait(const sigset_t *set, siginfo_t *info,
                              const struct timespec *timeout)
{
    kernel_sigset in_set;

    if (set == nullptr) {
        errno = EINVAL;
        return -1;
    }

    in_set.bionic = *set;

    /* __rt_sigtimedwait is not usable on Android 64-bit (the original comment
     * was right about that), so go through the raw syscall. */
    return static_cast<int>(
        syscall(__NR_rt_sigtimedwait, &in_set.word[0], info, timeout,
                sizeof(uint64_t)));
}
