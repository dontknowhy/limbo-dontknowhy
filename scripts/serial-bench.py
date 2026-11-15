#!/usr/bin/env python3
"""Drive a QEMU serial console over adb for the dd|md5 benchmark.

    scripts/serial-bench.py <libqemu.so on device> <tag> [iterations] [log] [extra qemu args]

`extra qemu args` are appended to the QEMU command line (e.g.
``"-accel tcg,thread=single"``) so build/runtime knobs can be compared without
touching the library.  `BENCH_CMD="..."` overrides the guest workload
(default: `dd if=/dev/zero bs=1M count=256 | md5sum`).

Waits for the guest login prompt instead of sleeping, so slow boots do not
desynchronise the input.  Requires the usual test setup on the device:

    /data/local/tmp/bt/{vmlinuz-virt,initramfs-virt,alpine.iso}
    /data/local/tmp/bt/libs/*.so           (jniLibs, all DT_NEEDED names)
                                           override with $BENCH_LIBDIR
    /data/local/tmp/limbo-smoke            (build/tools/limbo-smoke)
    /data/local/tmp/bt/<libqemu.so>        the library under test

Prints `BENCH <tag> <i> <uptime_before> <uptime_after>` from the guest; the
difference is the wall time in seconds (`taskset 40`, 256 MB guest).
"""
import os
import select
import shlex
import subprocess
import sys
import time

lib = sys.argv[1]
tag = sys.argv[2]
iters = sys.argv[3] if len(sys.argv) > 3 else "4"
logpath = sys.argv[4] if len(sys.argv) > 4 else f"/tmp/opencode/bench-{tag}.log"
extra = shlex.split(sys.argv[5]) if len(sys.argv) > 5 else []
libdir = os.environ.get("BENCH_LIBDIR", "/data/local/tmp/bt/libs")
smoke = os.environ.get("BENCH_SMOKE", "/data/local/tmp/limbo-smoke")

qemu = [
    "-m", "256", "-M", "pc", "-nodefaults", "-L", "/data/local/tmp/bt",
    "-kernel", "vmlinuz-virt", "-initrd", "initramfs-virt",
    "-append", "console=ttyS0 quiet modules=loop,squashfs,sd-mod,usb-storage,ata_piix,sr_mod",
    "-drive", "file=alpine.iso,if=ide,media=cdrom,readonly=on",
    "-display", "none", "-serial", "stdio", "-monitor", "none",
]
qemu = qemu + extra
remote = ("cd /data/local/tmp/bt && "
          f"LD_LIBRARY_PATH={shlex.quote(libdir)} "
          f"taskset 40 {shlex.quote(smoke)} " + shlex.quote(lib) + " " +
          " ".join(shlex.quote(a) for a in qemu))
cmd = ["adb", "shell", remote]

p = subprocess.Popen(cmd, stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                     stderr=subprocess.STDOUT, bufsize=0)
buf = b""
log = open(logpath, "wb")
sent_login = sent_bench = sent_power = False
start = time.time()
boot_time = None
deadline = start + 300

nums = " ".join(str(i) for i in range(1, int(iters) + 1))
workload = os.environ.get(
    "BENCH_CMD", "dd if=/dev/zero bs=1M count=256 2>/dev/null | md5sum")
bench = (
    f"for i in {nums}; do "
    "t=$(cut -d' ' -f1 /proc/uptime); "
    f"{workload}; "
    "t2=$(cut -d' ' -f1 /proc/uptime); "
    f"echo BENCH {tag} $i $t $t2; "
    "done; echo BENCH_DONE"
)

while time.time() < deadline:
    r, _, _ = select.select([p.stdout], [], [], 1)
    if r:
        chunk = os.read(p.stdout.fileno(), 4096)
        if not chunk:
            break
        log.write(chunk)
        log.flush()
        buf += chunk
    if not sent_login and b"login:" in buf:
        boot_time = time.time() - start
        log.write(f"BOOT {tag} {boot_time:.2f}\n".encode())
        log.flush()
        p.stdin.write(b"root\n")
        p.stdin.flush()
        sent_login = True
        buf = b""
    elif sent_login and not sent_bench and b"localhost:~#" in buf:
        p.stdin.write(bench.encode() + b"\n")
        p.stdin.flush()
        sent_bench = True
        buf = b""
    elif (sent_bench and not sent_power and
          buf.count(f"BENCH {tag} ".encode()) >= int(iters) + 1):
        p.stdin.write(b"poweroff -f\n")
        p.stdin.flush()
        sent_power = True
        deadline = time.time() + 20
    if p.poll() is not None:
        break

try:
    p.terminate()
except Exception:
    pass
log.close()
if boot_time is not None:
    print(f"done {logpath} boot={boot_time:.2f}s")
else:
    print("done", logpath, "(no login prompt seen)")
