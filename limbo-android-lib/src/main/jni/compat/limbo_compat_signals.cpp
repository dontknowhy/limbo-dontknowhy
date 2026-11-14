/*
 * Intentionally empty.
 *
 * This file used to define sigtimedwait() on top of
 * syscall(__NR_rt_sigtimedwait), because QEMU 5.1's KVM code path called
 * bionic's (64-bit) implementation and Limbo wanted the raw syscall. QEMU
 * 11.1.3 on Android runs TCG only and does not reference sigtimedwait; bionic
 * exports `sigtimedwait` for every API level this app supports (21+).
 *
 * `nm -D --undefined-only` over the whole shipped .so set shows no importer.
 *
 * The corrected implementation (with the kernel_sigset_t layout assumption
 * made explicit, plus a static_assert on sizeof(sigset_t)) is kept for
 * reference in src/legacy/limbo_compat_signals_legacy.cpp.
 *
 * The file is kept (rather than removed) so that the existing
 * compat/Android.mk source list keeps working unchanged.
 */
