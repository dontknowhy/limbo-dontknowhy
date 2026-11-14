# Legacy entry point: the native build now lives in the app-level Makefile.
#
# Kept so the historical workflow still works:
#
#     cd limbo-android-lib/src/main/jni
#     make            # build all native libraries (= app-level 'native')
#     make apk        # signed release APK
#
# The QEMU 5.1-era ndk-build system (Android.mk, android-config/*.mak) was
# removed; QEMU 11 is built with meson.  See ../../../../README.developers.

APP_ROOT := $(abspath $(CURDIR)/../../../..)

.PHONY: all limbo native deps qemu liblimbo setjmp jnilibs apk apk-debug \
        install clean distclean help

all: limbo
limbo: native

native deps qemu liblimbo setjmp jnilibs apk apk-debug install clean distclean:
	@$(MAKE) -C "$(APP_ROOT)" $@

help:
	@$(MAKE) -C "$(APP_ROOT)" help
