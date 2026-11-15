#!/usr/bin/env python3
"""Re-link a QEMU meson executable edge as a shared library.

QEMU 11 no longer has the old Makefile.target link hook, so we take the exact
object list and link arguments from build.ninja and re-link them with -shared.
The object list MUST come before the libraries (archive scan order), otherwise
libqemuutil.a stub members win over the real objects and we get duplicate
symbols.

Usage: scripts/link-qemu-so.py <build-dir> <target> <output>
"""
import os
import shlex
import subprocess
import sys

build_dir = sys.argv[1] if len(sys.argv) > 1 else os.environ.get(
    "QEMU_BUILD", "build/qemu-build")
target = sys.argv[2] if len(sys.argv) > 2 else "qemu-system-x86_64"
output = sys.argv[3] if len(sys.argv) > 3 else "libqemu-system-x86_64.so"
build_dir = os.path.abspath(build_dir)

ninja = os.path.join(build_dir, "build.ninja")
with open(ninja, encoding="utf-8") as f:
    lines = f.read().splitlines()

marker = None
start = None
for rule in ("c_LINKER_RSP", "c_LINKER"):
    candidate = f"build {target}: {rule} "
    for i, line in enumerate(lines):
        if line.startswith(candidate):
            marker, start = candidate, i
            break
    if start is not None:
        break
if start is None:
    sys.exit(f"error: link edge for {target} not found in {ninja}")

# Objects are everything between the rule name and the order-only separator.
objs = lines[start][len(marker):].split("|", 1)[0].split()

link_args = None
for line in lines[start + 1:]:
    stripped = line.strip()
    if not stripped:
        continue
    if stripped.startswith("LINK_ARGS = "):
        link_args = stripped[len("LINK_ARGS = "):]
        break
    if stripped.startswith("build "):
        break
if link_args is None:
    sys.exit("error: LINK_ARGS not found after link edge")

args = shlex.split(link_args)
# The meson edge is a PIE link; we want a normal shared object instead.
args = [a for a in args if a != "-pie"]
if "-shared" not in args:
    args.insert(0, "-shared")
soname = f"-Wl,-soname,{output}"
if not any(a.startswith("-Wl,-soname,") for a in args):
    args.append(soname)

# Android 15+ ships 16 KB page kernels; the ELF LOAD segments must be aligned
# accordingly (NDK r28+ already defaults to this, be explicit).
args.append("-Wl,-z,max-page-size=16384")

if target.startswith("qemu-system"):
    # aarch64 Android: bionic's sigsetjmp/siglongjmp are PAC-signed and cannot
    # be used across coroutine stacks / threads (SIGILL, ESR 0x72000000).
    # Link the AOSP replacement (patches/setjmp-aarch64) and bind internal
    # function references to it with -Bsymbolic-functions.
    sj = os.environ.get("SETJMP_LIB")
    if not sj:
        root = os.environ.get("LIMBO_ROOT", os.path.dirname(
            os.path.dirname(os.path.abspath(__file__))))
        sj = os.path.join(root, "build", "setjmp", "libandroid-setjmp.a")
    if os.path.exists(sj):
        args += ["-Wl,--whole-archive", sj, "-Wl,--no-whole-archive",
                 "-Wl,-Bsymbolic-functions"]
    else:
        sys.exit(f"error: {sj} not found (run 'make setjmp' first)")

    # liblimbo provides the Java/SAF callbacks used by QEMU (e.g.
    # Android_JNI_SetVMResolution). The only references are weak, so the
    # default --as-needed would drop the dependency and the weak call would
    # stay NULL at runtime: bionic only searches a dlopen'ed library's own
    # DT_NEEDED set, not the caller's. Force the DT_NEEDED entry.
    args += ["-Wl,--no-as-needed", "-llimbo", "-Wl,--as-needed"]

# Optional extra link flags (experiments, e.g. "-Wl,--lto-O3 -Wl,--icf=all").
extra_ldflags = shlex.split(os.environ.get("EXTRA_LDFLAGS", ""))
args += extra_ldflags

cc = os.environ.get("CC")
if not cc:
    sys.exit("error: CC is not set; source scripts/env.sh first")

rsp_path = os.path.join(build_dir, "link-libqemu.rsp")
cmd = [cc, "@" + rsp_path]
rsp = " ".join(["-o", output] + objs + args)
with open(rsp_path, "w", encoding="utf-8") as f:
    f.write(rsp + "\n")

os.chdir(build_dir)
print(f"linking {output}: {len(objs)} objects")
sys.exit(subprocess.call(cmd))
