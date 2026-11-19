# 真机调试与性能对比

QEMU 跑在 App 进程内，没有独立进程可 attach；所有问题先从日志和 `DT_NEEDED`
查起。

## 日志

- QEMU 的 stdout/stderr 被 JNI 重定向到 `base_dir` 下的 `qemu.log`，即
  `cache/limbo/qemu.log`（`limbo-android-lib/src/main/jni/limbo/vm-executor-jni.c`，
  路径由 `VMExecutor.start()` 传入的 `base_dir` 拼出，不写死包名）。每次启动以
  `"w"` 截断。
- 取日志：

  ```bash
  adb shell run-as com.limbo.emu.dontknowhy cat cache/limbo/qemu.log
  # release 包不可 run-as 时：
  adb shell su -c 'cat /data/data/com.limbo.emu.dontknowhy/cache/limbo/qemu.log'
  ```

- Java 侧看 logcat（limbo 的 tag 以 `Limbo`/`VMExecutor` 为主，直接过滤 PID）：

  ```bash
  adb logcat --pid=$(adb shell pidof com.limbo.emu.dontknowhy)
  ```

## 不装 App 跑 QEMU：limbo-smoke

`../build/tools/limbo-smoke` 是工作区里的 arm64 测试壳：`dlopen` 指定 `.so`，把
argv 原样转给 `qemu_init`。用来验证新编译的库，不需要重装 APK。

```bash
adb push ../build/tools/limbo-smoke /data/local/tmp/
adb push limbo-android-x86/src/main/jniLibs/arm64-v8a/*.so /data/local/tmp/bt/libs/
adb push limbo-android-lib/src/main/jniLibs/arm64-v8a/*.so  /data/local/tmp/bt/libs/

adb shell
cd /data/local/tmp/bt
LD_LIBRARY_PATH=/data/local/tmp/bt/libs /data/local/tmp/limbo-smoke \
    ./libqemu-system-x86_64.so -m 256 -M pc -nographic ...
```

- 必须在 `/data/local/tmp` 下执行：SELinux 不允许从 App 私有目录执行二进制。
- 依赖库必须全部用**打包名**放在 `LD_LIBRARY_PATH` 里，否则 dlopen 直接失败。
- 该壳不会转 QEMU 退出码语义，崩溃看 `logcat` / tombstone。

## dlopen 失败 / `cannot find ... from verneed`

bionic 只按被 dlopen 库自己的 `DT_NEEDED` 解析符号，宿主已加载的同名库不算数。

```bash
llvm-readelf -d limbo-android-x86/src/main/jniLibs/arm64-v8a/libqemu-system-x86_64.so \
  | grep NEEDED
```

每个条目都必须与 APK 内 `lib/arm64-v8a/` 的文件名逐字一致（`libglib-2.0.so`，不是
`libglib-2.0.so.0`）。不一致时按顺序检查：

1. `scripts/fix-needed.sh` 是否对 QEMU 和 `libqemu-img.so` 都跑过（改 `DT_NEEDED`）。
2. `scripts/sync-jnilibs.sh` 是否把每个依赖的 `SONAME` 改成了打包名（bionic 用
   被依赖库的 `SONAME` 回填 verneed）。
3. QEMU 是否带了 `--no-as-needed -llimbo`；漏掉时 `liblimbo.so` 不进 `DT_NEEDED`，
   `Android_JNI_SetVMResolution` 静默为 NULL，SDL 分辨率不回传给 UI。
4. 两个 module 的 `jniLibs` 是否都同步了：依赖在 `limbo-android-lib`，QEMU 在
   `limbo-android-x86`，Gradle 合并后才完整。

改完重跑 `make jnilibs`（或 `scripts/sync-jnilibs.sh`）再打包，不要手工 `patchelf`
后就地安装。

## 串口跑分：serial-bench.py

```bash
python3 scripts/serial-bench.py <设备上的 libqemu.so> <tag> [iters] [log] [额外 QEMU 参数]
```

- 默认 4 轮，guest 内执行 `dd if=/dev/zero bs=1M count=256 | md5sum`，stdout 输出
  `BENCH <tag> <i> <uptime_before> <uptime_after>`，差值即墙钟秒数；日志文件里另有
  `BOOT <tag> <s>`（等到 login 提示的耗时）。用 `BENCH_CMD` 换负载。
- 设备侧固定布局：
  `/data/local/tmp/bt/{vmlinuz-virt,initramfs-virt,alpine.iso}`、
  `/data/local/tmp/bt/libs/*.so`（`BENCH_LIBDIR` 可改）、`/data/local/tmp/limbo-smoke`、
  `/data/local/tmp/bt/<libqemu.so>`。
- 固定 `taskset 40`、256 MB guest；比较时一次只改一个变量（LTO、PGO、TCG 线程数），
  额外参数通过第 5 个参数透传（如 `"-accel tcg,thread=single"`）。
- 日志默认写 `/tmp/opencode/bench-<tag>.log`；构建日志放工作区 `build/logs/`。

## 常见失败对照

| 现象 | 原因 / 处理 |
|---|---|
| 启动即闪退，`qemu.log` 为空 | `dlopen` 失败。按上一节查 `DT_NEEDED` 与文件是否在 APK 内。 |
| 第二次启动弹“需重开 App” | `VMExecutor.qemuInitializedOnce` 拦截。QEMU 不支持同进程二次 `qemu_init`，这是预期行为。 |
| SDL 下启动后 Scudo OOM / 映射数暴涨 | 同时挂了两个 `-pflash`。只保留一个 UEFI code fd；两个 UEFI 都关时才用 `-bios bios-xbzj.bin`。 |
| `SIGILL`，`esr 0x72000000`（PAC） | 协程用了 bionic 的 `sigsetjmp`。确认链接了 `libandroid-setjmp.a`（`--whole-archive` + `-Bsymbolic-functions`），且 configure 为 `--with-coroutine=sigaltstack`。 |
| 安装时报 16 KB 对齐 | 链接缺 `-Wl,-z,max-page-size=16384`，或 `zipalign` 不支持 `-P`（需 build-tools 35+）。用 `zipalign -c -P 16 4 app.apk` 复核。 |
| 音频无声 / `abort()` | 新 audio driver 没接进三处分派（`audio_create_pdos`、`audio_get_pdo_out/in`、`audio_template.h`），或设备不支持请求的采样率（OpenSL ES/AAudio 只有 S16）。 |
| SAF 磁盘打不开 | 只接受 `/dev/fdset/<n>` + `-add-fd`；`-kernel`/`-initrd` 不能走 fdset，必须先拷到 `cache/limbo/saf-*.bin`。 |
| UI 输入法遮挡 / insets 为 0 | 窗口未设 `SOFT_INPUT_ADJUST_RESIZE`（targetSdk 29 + Android 11+）。 |
| 改了 QEMU 后跑分反而变慢 | PGO profile 过期。改源码后必须重训，见 [build.md](build.md)。 |

## 相关文档

- 构建/重链接/PGO 重训：[build.md](build.md)
- QEMU 补丁与 setjmp 来源：[qemu-patches.md](qemu-patches.md)
- App 启动链与参数拼装：[app.md](app.md)
