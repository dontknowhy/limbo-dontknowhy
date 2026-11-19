# Limbo (QEMU 11.1.3) native + APK build
# =======================================
#
# Everything is driven from this directory (the limbo-dontknowhy repo):
#
#   make prepare        extract sources and apply the QEMU patch series
#   make deps           cross-compile glib/libffi/pixman/SDL2/zlib/zstd/...
#   make qemu           configure + build QEMU, relink as libqemu-system-*.so
#   make liblimbo       build the JNI/callback library
#   make native         prepare + deps + qemu + liblimbo (default)
#   make apk            signed release APK (native + gradle + zipalign + apksign)
#   make apk-debug      debug APK (debug-signed by Gradle)
#   make install        adb install the release APK
#   make clean          remove app build outputs (keeps native deps)
#   make distclean      remove native build dirs and jniLibs as well
#
# Useful overrides (also honoured by scripts/env.sh):
#   LIMBO_ROOT=/path/to/workspace   DEPS=/path/to/deps   PREFIX=...   BUILD=...
#   JOBS=8   NDK_ROOT=...   ANDROID_HOME=...
#
# See README.developers for prerequisites and the whole story.

SHELL := /bin/bash
.DEFAULT_GOAL := native

APP_ROOT    := $(patsubst %/,%,$(dir $(abspath $(lastword $(MAKEFILE_LIST)))))
LIMBO_ROOT  ?= $(abspath $(APP_ROOT)/..)
JNI         := $(APP_ROOT)/limbo-android-lib/src/main/jni
DEPS        ?= $(LIMBO_ROOT)/deps
PREFIX      ?= $(LIMBO_ROOT)/prebuilt/arm64-v8a
BUILD       ?= $(LIMBO_ROOT)/build
SRC         ?= $(BUILD)/src
JOBS        ?= $(shell nproc)
PATCHES     := $(JNI)/patches/qemu-11.1.3
JLIB        := $(APP_ROOT)/limbo-android-lib/src/main/jniLibs/arm64-v8a
GRADLE      ?= $(LIMBO_ROOT)/gradle-8.2.1/bin/gradle
KEYSTORE    ?= $(APP_ROOT)/keystore/limbo-release.jks
KEYSTORE_PROPERTIES ?= $(APP_ROOT)/keystore/keystore.properties

STAMPS      := $(BUILD)/.stamps
# QEMU source tree.  Defaults to the tree `make prepare` extracts into jni/;
# point it at a git checkout (e.g. QEMU_SRC=$LIMBO_ROOT/qemu) to build from
# version-controlled sources instead.  Use a separate QEMU_BUILD per source
# tree and delete the qemu-configured stamp when switching.
QEMU_SRC    ?= $(JNI)/qemu
QEMU_BUILD  ?= $(BUILD)/qemu-build

# Profile-guided optimisation.  The checked-in profile was trained on the
# TCG/softmmu hot paths of a multi-image workload (see README "PGO"); the
# compiler still targets generic armv8-a, so one build serves every device.
# Build without it with `make PGO_PROFILE=`.
PGO_PROFILE ?= $(APP_ROOT)/profiles/qemu-11.1.3.profdata
ifneq ($(strip $(PGO_PROFILE)),)
ifeq ($(wildcard $(PGO_PROFILE)),)
$(error PGO_PROFILE=$(PGO_PROFILE) does not exist; pass PGO_PROFILE= to disable PGO)
endif
PGO_FLAGS := -fprofile-use=$(PGO_PROFILE) -Wno-profile-instr-unprofiled -Wno-profile-instr-out-of-date
else
PGO_FLAGS :=
endif

# One shell environment for every recipe.
ENV = source "$(APP_ROOT)/scripts/env.sh"

.PHONY: help prepare deps deps-fetch qemu qemu-configure liblimbo native jnilibs \
        apk apk-release apk-debug install clean clean-qemu clean-jnilibs \
        distclean keystore setjmp

help:
	@sed -n 's/^#   /  /p' $(firstword $(MAKEFILE_LIST)) | head -30

# ---------------------------------------------------------------------------
# Source preparation
# ---------------------------------------------------------------------------

define extract
	@mkdir -p "$(SRC)"
	@if [ ! -d "$(SRC)/$(1)" ]; then \
	    echo "extracting $(notdir $(2))"; \
	    tar -xf "$(2)" -C "$(SRC)"; \
	fi
endef

prepare: $(STAMPS)/prepare-setjmp $(STAMPS)/prepare-qemu $(STAMPS)/prepare-glib \
         $(STAMPS)/prepare-pixman $(STAMPS)/prepare-sdl2 $(STAMPS)/prepare-ffi \
         $(STAMPS)/cross-file
	@echo "sources ready"

$(STAMPS)/prepare-setjmp:
	@mkdir -p "$(STAMPS)" "$(BUILD)/setjmp"
	@touch $@

$(STAMPS)/prepare-qemu: $(DEPS)/qemu-11.1.3.tar.xz
	@mkdir -p "$(STAMPS)"
	@if [ ! -d "$(JNI)/qemu" ]; then \
	    echo "extracting qemu-11.1.3"; \
	    tar -xf "$<" -C "$(JNI)"; \
	    mv "$(JNI)/qemu-11.1.3" "$(JNI)/qemu"; \
	fi
	@if patch -d "$(JNI)/qemu" -p1 --dry-run -R \
	      < "$(PATCHES)/0001-android-build-meson.patch" >/dev/null 2>&1; then \
	    echo "qemu patches already applied"; \
	else \
	    for p in "$(PATCHES)"/*.patch; do \
	        echo "applying $$(basename $$p)"; \
	        patch -d "$(JNI)/qemu" -p1 --batch --forward < "$$p"; \
	    done; \
	fi
	@touch $@

$(STAMPS)/prepare-glib: $(DEPS)/glib-2.90.1.tar.xz
	@mkdir -p "$(STAMPS)"
	@if [ ! -d "$(JNI)/glib" ]; then \
	    echo "extracting glib-2.90.1"; \
	    tar -xf "$<" -C "$(JNI)"; \
	    mv "$(JNI)/glib-2.90.1" "$(JNI)/glib"; \
	fi
	# glib's intl fallback is a wrap subproject; ship it offline.
	@if [ ! -d "$(JNI)/glib/subprojects/proxy-libintl-0.5" ]; then \
	    mkdir -p "$(JNI)/glib/subprojects"; \
	    tar -xf "$(DEPS)/proxy-libintl-0.5.tar.gz" -C "$(JNI)/glib/subprojects"; \
	fi
	@mkdir -p "$(JNI)/glib/subprojects/packagecache"
	@cp -n "$(DEPS)/proxy-libintl-0.5.tar.gz" \
	    "$(JNI)/glib/subprojects/packagecache/" 2>/dev/null || true
	@touch $@

$(STAMPS)/prepare-pixman: $(DEPS)/pixman-0.46.4.tar.xz
	@mkdir -p "$(STAMPS)"
	@if [ ! -d "$(JNI)/pixman" ]; then \
	    echo "extracting pixman-0.46.4"; \
	    tar -xf "$<" -C "$(JNI)"; \
	    mv "$(JNI)/pixman-0.46.4" "$(JNI)/pixman"; \
	fi
	@touch $@

$(STAMPS)/prepare-sdl2: $(DEPS)/SDL2-2.32.10.tar.gz
	@mkdir -p "$(STAMPS)"
	@if [ ! -d "$(JNI)/SDL2" ]; then \
	    echo "extracting SDL2-2.32.10"; \
	    tar -xf "$<" -C "$(JNI)"; \
	    mv "$(JNI)/SDL2-2.32.10" "$(JNI)/SDL2"; \
	fi
	@touch $@

$(STAMPS)/prepare-ffi: $(DEPS)/libffi-3.4.3.tar.gz
	@mkdir -p "$(STAMPS)"
	@if [ ! -d "$(JNI)/libffi" ]; then \
	    echo "extracting libffi-3.4.3"; \
	    tar -xf "$<" -C "$(JNI)"; \
	    mv "$(JNI)/libffi-3.4.3" "$(JNI)/libffi"; \
	fi
	@touch $@

$(STAMPS)/cross-file:
	@mkdir -p "$(STAMPS)"
	@$(ENV); "$(APP_ROOT)/scripts/gen-cross-file.sh" "$(BUILD)/config-meson.cross"
	@touch $@

# Tarballs that are not in the workspace deps/ dir by default.
deps-fetch:
	@$(ENV); "$(APP_ROOT)/scripts/fetch-deps.sh"

# ---------------------------------------------------------------------------
# Dependencies
# ---------------------------------------------------------------------------

deps: $(STAMPS)/zlib $(STAMPS)/zstd $(STAMPS)/pcre2 $(STAMPS)/iconv \
      $(STAMPS)/ffi $(STAMPS)/glib $(STAMPS)/pixman $(STAMPS)/slirp $(STAMPS)/sdl2
	@echo "dependencies installed in $(PREFIX)"

# zlib-ng in zlib-compat mode provides libz.so for QEMU.
$(STAMPS)/zlib: $(DEPS)/zlib-ng-2.3.3.tar.gz $(STAMPS)/cross-file
	$(call extract,zlib-ng-2.3.3,$<)
	@$(ENV); $$CMAKE --fresh -S "$(SRC)/zlib-ng-2.3.3" -B "$(BUILD)/zlib-ng-build" -G Ninja \
	    -DCMAKE_TOOLCHAIN_FILE="$$CMAKE_TOOLCHAIN_FILE" \
	    -DANDROID_ABI="$$ABI" -DANDROID_PLATFORM="android-$$API" \
	    -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX="$(PREFIX)" \
	    -DCMAKE_C_FLAGS="$$ARCH_FLAGS -O3 -fPIC" \
	    -DBUILD_SHARED_LIBS=ON -DZLIB_COMPAT=ON -DZLIB_ALIASES=ON >/dev/null
	@$(ENV); $$CMAKE --build "$(BUILD)/zlib-ng-build" --parallel $(JOBS) >/dev/null
	@$(ENV); $$CMAKE --install "$(BUILD)/zlib-ng-build" >/dev/null
	@mkdir -p "$(STAMPS)"; touch $@

$(STAMPS)/zstd: $(DEPS)/zstd-1.5.7.tar.gz
	$(call extract,zstd-1.5.7,$<)
	@$(ENV); $(MAKE) -C "$(SRC)/zstd-1.5.7" -j$(JOBS) >/dev/null
	@$(ENV); $(MAKE) -C "$(SRC)/zstd-1.5.7/lib" install PREFIX="$(PREFIX)" >/dev/null
	@mkdir -p "$(STAMPS)"; touch $@

$(STAMPS)/pcre2: $(DEPS)/pcre2-10.49.tar.gz
	$(call extract,pcre2-10.49,$<)
	@$(ENV); $$CMAKE --fresh -S "$(SRC)/pcre2-10.49" -B "$(BUILD)/pcre2-build" -G Ninja \
	    -DCMAKE_TOOLCHAIN_FILE="$$CMAKE_TOOLCHAIN_FILE" \
	    -DANDROID_ABI="$$ABI" -DANDROID_PLATFORM="android-$$API" \
	    -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX="$(PREFIX)" \
	    -DCMAKE_C_FLAGS="$$ARCH_FLAGS -O3 -fPIC" \
	    -DBUILD_SHARED_LIBS=ON \
	    -DPCRE2_BUILD_PCRE2_8=ON -DPCRE2_BUILD_PCRE2_16=OFF \
	    -DPCRE2_BUILD_PCRE2_32=OFF -DPCRE2_BUILD_PCRE2GREP=OFF \
	    -DPCRE2_BUILD_TESTS=OFF -DPCRE2_SUPPORT_JIT=ON >/dev/null
	@$(ENV); $$CMAKE --build "$(BUILD)/pcre2-build" --parallel $(JOBS) >/dev/null
	@$(ENV); $$CMAKE --install "$(BUILD)/pcre2-build" >/dev/null
	@mkdir -p "$(STAMPS)"; touch $@

$(STAMPS)/iconv: $(DEPS)/libiconv-1.18.tar.gz
	$(call extract,libiconv-1.18,$<)
	# libiconv refuses out-of-tree configure if the source tree was configured
	# in place by an older build; clean it first.
	@if [ -f "$(SRC)/libiconv-1.18/config.status" ]; then \
	    $(MAKE) -C "$(SRC)/libiconv-1.18" distclean >/dev/null 2>&1 || true; \
	fi
	@$(ENV); mkdir -p "$(BUILD)/libiconv-build"
	@cd "$(BUILD)/libiconv-build" && $(ENV) && \
	    "$(SRC)/libiconv-1.18/configure" \
	    --build=x86_64-pc-linux-gnu --host=aarch64-linux-android \
	    --prefix="$(PREFIX)" --enable-shared --disable-static --disable-nls \
	    CC="$$CC" CXX="$$CXX" AR="$$AR" RANLIB="$$RANLIB" \
	    CFLAGS="$$ARCH_FLAGS -O3 -fPIC" \
	    CPPFLAGS="$$CROSS_CPPFLAGS" >/dev/null
	@$(ENV); $(MAKE) -C "$(BUILD)/libiconv-build" -j$(JOBS) >/dev/null
	@$(ENV); $(MAKE) -C "$(BUILD)/libiconv-build" install >/dev/null
	@mkdir -p "$(STAMPS)"; touch $@

$(STAMPS)/ffi: $(DEPS)/libffi-3.4.3.tar.gz $(STAMPS)/prepare-ffi
	@mkdir -p "$(BUILD)/libffi-build"
	@cd "$(BUILD)/libffi-build" && $(ENV) && \
	    "$(JNI)/libffi/configure" --build=x86_64-pc-linux-gnu \
	    --host=aarch64-linux-android --prefix="$(PREFIX)" \
	    --enable-shared --disable-static --disable-docs \
	    --disable-exec-static-tramp \
	    CC="$$CC" CXX="$$CXX" AR="$$AR" RANLIB="$$RANLIB" \
	    CFLAGS="$$ARCH_FLAGS -O3 -fPIC" CPPFLAGS="$$CROSS_CPPFLAGS" >/dev/null
	@$(ENV); $(MAKE) -C "$(BUILD)/libffi-build" -j$(JOBS) >/dev/null
	@$(ENV); $(MAKE) -C "$(BUILD)/libffi-build" install >/dev/null
	@mkdir -p "$(STAMPS)"; touch $@

$(STAMPS)/glib: $(DEPS)/glib-2.90.1.tar.xz $(STAMPS)/prepare-glib \
                 $(STAMPS)/pcre2 $(STAMPS)/ffi $(STAMPS)/iconv $(STAMPS)/cross-file
	@if [ -f "$(BUILD)/glib-build/meson-private/cmd_line.txt" ] && \
	    ! grep -q "config-meson.cross" "$(BUILD)/glib-build/meson-private/cmd_line.txt"; then \
	    rm -rf "$(BUILD)/glib-build"; fi
	@$(ENV); $$MESON setup --reconfigure "$(BUILD)/glib-build" "$(JNI)/glib" \
	    --cross-file "$(BUILD)/config-meson.cross" \
	    --prefix="$(PREFIX)" --buildtype=release \
	    -Dtests=false -Dglib_debug=disabled -Dglib_assert=false \
	    -Dglib_checks=false -Dintrospection=disabled -Ddocumentation=false \
	    -Dman-pages=disabled -Dnls=disabled -Dlibmount=disabled \
	    -Dselinux=disabled -Dxattr=false -Dbsymbolic_functions=false \
	    -Dforce_posix_threads=true -Dwrap_mode=nodownload >/dev/null
	@$(ENV); $$NINJA -C "$(BUILD)/glib-build" install >/dev/null
	@mkdir -p "$(STAMPS)"; touch $@

$(STAMPS)/pixman: $(DEPS)/pixman-0.46.4.tar.xz $(STAMPS)/prepare-pixman $(STAMPS)/cross-file
	@if [ -f "$(BUILD)/pixman-build/meson-private/cmd_line.txt" ] && \
	    ! grep -q "config-meson.cross" "$(BUILD)/pixman-build/meson-private/cmd_line.txt"; then \
	    rm -rf "$(BUILD)/pixman-build"; fi
	@$(ENV); $$MESON setup --reconfigure "$(BUILD)/pixman-build" "$(JNI)/pixman" \
	    --cross-file "$(BUILD)/config-meson.cross" \
	    --prefix="$(PREFIX)" --buildtype=release \
	    -Dtests=disabled -Ddemos=disabled -Dopenmp=disabled -Dgtk=disabled >/dev/null
	@$(ENV); $$NINJA -C "$(BUILD)/pixman-build" install >/dev/null
	@mkdir -p "$(STAMPS)"; touch $@

$(STAMPS)/slirp: $(DEPS)/libslirp-4.9.7.tar.gz $(STAMPS)/glib $(STAMPS)/cross-file
	$(call extract,libslirp-4.9.7,$<)
	@if [ -d "$(SRC)/libslirp-v4.9.7" ] && [ ! -d "$(SRC)/libslirp-4.9.7" ]; then \
	    mv "$(SRC)/libslirp-v4.9.7" "$(SRC)/libslirp-4.9.7"; fi
	# An older tree may have this build dir configured for libslirp 4.9.0,
	# which meson refuses to reconfigure for a different source dir.
	@if [ -f "$(BUILD)/slirp-build/meson-private/coredata.dat" ] && \
	    ! grep -aq "libslirp-4.9.7" "$(BUILD)/slirp-build/meson-private/coredata.dat"; then \
	    rm -rf "$(BUILD)/slirp-build"; fi
	@$(ENV); $$MESON setup --reconfigure "$(BUILD)/slirp-build" "$(SRC)/libslirp-4.9.7" \
	    --cross-file "$(BUILD)/config-meson.cross" \
	    --prefix="$(PREFIX)" --buildtype=release >/dev/null
	@$(ENV); $$NINJA -C "$(BUILD)/slirp-build" install >/dev/null
	@mkdir -p "$(STAMPS)"; touch $@

$(STAMPS)/sdl2: $(DEPS)/SDL2-2.32.10.tar.gz $(STAMPS)/prepare-sdl2
	@$(ENV); $$CMAKE --fresh -S "$(JNI)/SDL2" -B "$(BUILD)/sdl2-build" -G Ninja \
	    -DCMAKE_TOOLCHAIN_FILE="$$CMAKE_TOOLCHAIN_FILE" \
	    -DANDROID_ABI="$$ABI" -DANDROID_PLATFORM="android-$$API" \
	    -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX="$(PREFIX)" \
	    -DCMAKE_C_FLAGS="$$ARCH_FLAGS -O3 -fPIC" \
	    -DSDL_SHARED=ON -DSDL_STATIC=OFF -DSDL_TEST=OFF >/dev/null
	@$(ENV); $$CMAKE --build "$(BUILD)/sdl2-build" --parallel $(JOBS) >/dev/null
	@$(ENV); $$CMAKE --install "$(BUILD)/sdl2-build" >/dev/null
	@mkdir -p "$(STAMPS)"; touch $@

# ---------------------------------------------------------------------------
# sigsetjmp replacement (aarch64/bionic PAC issue)
# ---------------------------------------------------------------------------

setjmp: $(BUILD)/setjmp/libandroid-setjmp.a

$(BUILD)/setjmp/libandroid-setjmp.a: $(JNI)/patches/setjmp-aarch64/setjmp.S
	@$(ENV); mkdir -p "$(BUILD)/setjmp"
	@$(ENV); "$$CC" --sysroot="$$SYSROOT" -I"$(JNI)/patches/setjmp-aarch64" \
	    -c "$(JNI)/patches/setjmp-aarch64/setjmp.S" \
	    -o "$(BUILD)/setjmp/setjmp.o"
	@$(ENV); "$$AR" rcs "$(BUILD)/setjmp/libandroid-setjmp.a" \
	    "$(BUILD)/setjmp/setjmp.o"
	@echo "built $@"

# ---------------------------------------------------------------------------
# QEMU
# ---------------------------------------------------------------------------

qemu-configure: $(STAMPS)/qemu-configured
	@echo "qemu configured in $(QEMU_BUILD)"

$(STAMPS)/qemu-configured: $(STAMPS)/zlib $(STAMPS)/zstd $(STAMPS)/glib \
                $(STAMPS)/pixman $(STAMPS)/slirp $(STAMPS)/sdl2 \
                $(STAMPS)/iconv $(STAMPS)/ffi $(STAMPS)/prepare-qemu \
                $(APP_ROOT)/scripts/qemu-configure.sh $(PGO_PROFILE)
	@$(ENV); EXTRA_CFLAGS="$(PGO_FLAGS) $${EXTRA_CFLAGS:-}" \
	    QEMU_SRC="$(QEMU_SRC)" \
	    "$(APP_ROOT)/scripts/qemu-configure.sh"
	@mkdir -p "$(STAMPS)"; touch $@

qemu: $(STAMPS)/qemu-configured $(BUILD)/setjmp/libandroid-setjmp.a liblimbo
	@if [ ! -f "$(QEMU_BUILD)/build.ninja" ]; then \
	    echo "== $@: $(QEMU_BUILD) is missing, reconfiguring =="; \
	    rm -f "$(STAMPS)/qemu-configured"; \
	    $(MAKE) --no-print-directory "$(STAMPS)/qemu-configured"; \
	fi
	@$(ENV); $$NINJA -C "$(QEMU_BUILD)" qemu-system-x86_64 qemu-img
	@echo "== relink libqemu-system-x86_64.so =="
	@$(ENV); EXTRA_LDFLAGS="$(PGO_FLAGS) $${EXTRA_LDFLAGS:-}" \
	    python3 "$(APP_ROOT)/scripts/link-qemu-so.py" \
	    "$(QEMU_BUILD)" qemu-system-x86_64 libqemu-system-x86_64.so
	@echo "== relink libqemu-img.so =="
	@$(ENV); EXTRA_LDFLAGS="$(PGO_FLAGS) $${EXTRA_LDFLAGS:-}" \
	    python3 "$(APP_ROOT)/scripts/link-qemu-so.py" \
	    "$(QEMU_BUILD)" qemu-img libqemu-img.so
	@mkdir -p "$(JLIB)"
	@mv -f "$(QEMU_BUILD)/libqemu-system-x86_64.so" "$(JLIB)/"
	@mv -f "$(QEMU_BUILD)/libqemu-img.so" "$(JLIB)/"
	@$(ENV); "$$STRIP" --strip-unneeded \
	    "$(JLIB)/libqemu-system-x86_64.so" "$(JLIB)/libqemu-img.so"
	@$(ENV); "$(APP_ROOT)/scripts/fix-needed.sh" \
	    "$(JLIB)/libqemu-system-x86_64.so" "$(JLIB)/libqemu-img.so"
	@echo "== jniLibs =="
	@ls -l "$(JLIB)"/libqemu-*.so

liblimbo:
	@$(ENV); "$(APP_ROOT)/scripts/build-limbo.sh"

# Copy renamed dependency libraries into jniLibs (Android needs lib*.so names;
# DT_NEEDED is rewritten by fix-needed.sh).
jnilibs: deps
	@$(ENV); "$(APP_ROOT)/scripts/sync-jnilibs.sh"

native: prepare setjmp deps liblimbo qemu jnilibs
	@echo "native libraries are ready in $(JLIB)"

# ---------------------------------------------------------------------------
# APK
# ---------------------------------------------------------------------------

keystore:
	@$(APP_ROOT)/scripts/make-keystore.sh

apk: apk-release

apk-release: native keystore
	@$(ENV); "$(APP_ROOT)/scripts/package-apk.sh" release

apk-debug: native
	@$(ENV); "$(APP_ROOT)/scripts/package-apk.sh" debug

install: apk-release
	adb install -r "$(BUILD)/limbo-x86-qemu11-arm64-release.apk"

# ---------------------------------------------------------------------------
# Cleaning
# ---------------------------------------------------------------------------

clean:
	@$(GRADLE) -p "$(APP_ROOT)" clean >/dev/null 2>&1 || true
	@rm -rf "$(APP_ROOT)/build" "$(APP_ROOT)/limbo-android-lib/build" \
	    "$(APP_ROOT)/limbo-android-x86/build"

clean-qemu:
	@rm -rf "$(QEMU_BUILD)" "$(BUILD)/native-build"
	@rm -f "$(STAMPS)/qemu-configured"

clean-jnilibs:
	@rm -rf "$(JLIB)"

distclean: clean clean-qemu clean-jnilibs
	@rm -rf "$(BUILD)/.stamps" "$(BUILD)"/*-build "$(BUILD)/config-meson.cross" \
	    "$(BUILD)/setjmp" "$(BUILD)/toolchain-prefix"
	@rm -rf "$(JNI)/qemu" "$(JNI)/glib" "$(JNI)/pixman" "$(JNI)/SDL2" "$(JNI)/libffi"
	@echo "removed native build dirs and extracted sources"
