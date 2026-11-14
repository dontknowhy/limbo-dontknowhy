#!/usr/bin/env python3
"""Drive a QEMU serial console over adb for the dd|md5 benchmark.

    scripts/serial-bench.py <libqemu.so on device> <tag> [iterations] [log]

Waits for the guest login prompt instead of sleeping, so slow boots do not
desynchronise the input.  Requires the usual test setup on the device:

    /data/local/tmp/bt/{vmlinuz-virt,initramfs-virt,alpine.iso}
    /data/local/tmp/bt/libs/*.so           (jniLibs, all DT_NEEDED names)
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

qemu = [
    "-m", "256", "-M", "pc", "-nodefaults", "-L", "/data/local/tmp/bt",
    "-kernel", "vmlinuz-virt", "-initrd", "initramfs-virt",
    "-append", "console=ttyS0 quiet modules=loop,squashfs,sd-mod,usb-storage,ata_piix,sr_mod",
    "-drive", "file=alpine.iso,if=ide,media=cdrom,readonly=on",
    "-display", "none", "-serial", "stdio", "-monitor", "none",
]
remote = ("cd /data/local/tmp/bt && "
          "LD_LIBRARY_PATH=/data/local/tmp/bt/libs "
          "taskset 40 /data/local/tmp/limbo-smoke " + shlex.quote(lib) + " " +
          " ".join(shlex.quote(a) for a in qemu))
cmd = ["adb", "shell", remote]

p = subprocess.Popen(cmd, stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                     stderr=subprocess.STDOUT, bufsize=0)
buf = b""
log = open(logpath, "wb")
sent_login = sent_bench = sent_power = False
deadline = time.time() + 300

nums = " ".join(str(i) for i in range(1, int(iters) + 1))
bench = (
    f"for i in {nums}; do "
    "t=$(cut -d' ' -f1 /proc/uptime); "
    "dd if=/dev/zero bs=1M count=256 2>/dev/null | md5sum; "
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
print("done", logpath)
