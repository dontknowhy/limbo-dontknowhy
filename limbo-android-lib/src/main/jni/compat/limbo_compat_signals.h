#ifndef LIMBO_COMPAT_SIGNALS_H
#define LIMBO_COMPAT_SIGNALS_H

/*
 * Intentionally empty: the sigtimedwait() override that used to be declared
 * here has no importers left in the QEMU 11.1.3 .so set. See
 * limbo_compat_signals.cpp and REPORT.md.
 *
 * The corrected reference implementation lives in
 * src/legacy/limbo_compat_signals_legacy.h (not built into the .so).
 */

#include <signal.h>

#endif
