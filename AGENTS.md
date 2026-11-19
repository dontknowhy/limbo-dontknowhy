# AGENTS.md

Limbo 的 Android 前端 + QEMU 11.1.3 原生构建系统。QEMU 源码不在本仓库：所有改动是
`limbo-android-lib/src/main/jni/patches/qemu-11.1.3/*.patch`。原生构建由根 `Makefile`
驱动（不是 ndk-build）；`deps/`、`build/`、`prebuilt/` 位于仓库上一级工作区
（`LIMBO_ROOT`，默认 `..`）。

## TOC

- [快速事实](#快速事实)
- [命令](#命令)
- [架构](#架构)
- [硬约束与易踩坑](#硬约束与易踩坑)
- [验证](#验证)
- [编码约定](#编码约定)
- [文档索引](#文档索引)

## 快速事实

- 仅支持 `arm64-v8a`；`minSdk`/`targetSdk` 29，`compileSdk` 31，applicationId
  `com.limbo.emu.dontknowhy`。`README.developers` 里“API 21”是旧描述，`scripts/env.sh`
  的 `API=29` 才是实际值（ELF TLS 需要）。
- 不入库：`jniLibs/**/*.so`、`jni/{qemu,glib,pixman,SDL2,libffi}`、`build/`、
  `deps/` 与 keystore。不要提交二进制或解压后的源码。
- 工作区级规则在 `../AGENTS.md`，进度/决策记录在 `../memo.md`；两者不在本 git 仓库内。
  `README.developers` 是构建/打包/调试的权威长文，本文只保留 agent 最容易踩错的部分。
- QEMU 改动的唯一权威记录是 patch 系列。不要改完 `jni/qemu` 就留在那里，见
  [docs/agents/qemu-patches.md](docs/agents/qemu-patches.md)。

## 命令

所有命令在仓库根执行。`make` 的每条 recipe 都会自己 `source scripts/env.sh`；只有交互式
shell 需要 `source ../envsetup.sh`。

```bash
make deps-fetch      # 下载 tarball 到 ../deps 并校验 sha256（GitHub 可设 GH_PROXY）
make native          # prepare + setjmp + deps + liblimbo + qemu + jnilibs
make apk             # release APK（缺 keystore 时先 make keystore）
make apk-debug       # debug-signed，迭代 UI 用这个
make prepare deps liblimbo qemu jnilibs   # 单步
make clean           # 只删 Gradle/app 产物
make clean-qemu      # 删 QEMU build，同时清 qemu-configured stamp
make distclean       # 连 native build 与 jniLibs 一起删
```

- 产物：`../build/limbo-x86-qemu11-arm64-release.apk`、`...-debug.apk`（注意是工作区
  `build/`，不是 Gradle 的仓库内 `build/`）。
- `limbo-android-x86/src/main/jniLibs/arm64-v8a/`：`libqemu-system-x86_64.so`、
  `libqemu-img.so`；`limbo-android-lib/src/main/jniLibs/arm64-v8a/`：依赖 `.so` +
  `liblimbo.so`。Gradle 合并两个目录。
- 步骤 stamp 在 `../build/.stamps/`；删对应 stamp 即可只重跑一步。`make qemu` 发现
  `build.ninja` 不存在会自动重新 configure。
- 常改的覆盖变量：`LIMBO_ROOT=`、`DEPS=`、`PREFIX=`、`BUILD=`、`QEMU_SRC=`、
  `QEMU_BUILD=`、`JOBS=`、`NDK_ROOT=`、`ANDROID_HOME=`。
- PGO 默认开启。`make PGO_PROFILE=` 关闭；profile 在
  `profiles/qemu-11.1.3.profdata`，改 QEMU 源码后必须重训（见
  [docs/agents/build.md](docs/agents/build.md)）。
- 要从 git 版 QEMU 树构建：`make QEMU_SRC=../qemu QEMU_BUILD=$PWD/../build/qemu-build-git ...`。
  切换源码树时记得删 `qemu-configured` stamp。
- 手工重链接 QEMU：`python3 scripts/link-qemu-so.py <build-dir> <target> <out.so>`；
  依赖改名用 `scripts/fix-needed.sh`。完整步骤见 `README.developers` §7–8。

## 架构

- 两个 Gradle module：`limbo-android-lib`（Java UI/控制面 + `jni/` 的 JNI/compat 源码，
  出 `liblimbo.so`）和 `limbo-android-x86`（application module，打包 QEMU 库）。
  Java 包同时存在 `com.max2idea.android.limbo.*`（上游代码）和
  `com.limbo.emu.dontknowhy.*`（启动入口），保持现状。
- 启动链：`LimboEmuActivity` → `MachineController`（单例状态）→ `MachineService`
  （前台 Service，`Thread.MAX_PRIORITY` 跑 QEMU）→ `VMExecutor.start()` →
  `jni/limbo/vm-executor-jni.c` 的 `dlopen()` + `dlsym(qemu_init / qemu_main_loop /
  qemu_cleanup)`。QEMU 在主进程内运行，不是独立进程。
- QEMU 命令行由 `VMExecutor.prepareParams()` 拼装，机器/磁盘/显示配置来自
  `Config`、`Machine`、`LimboSettingsManager`。新增 QEMU 参数先看这里，不要在别处另起一套。
- 两种显示模式：SDL 走 `LimboSDLActivity` + `org.libsdl.app`；VNC 走
  `LimboActivity`，用 `QmpClient`（QMP over local socket 或 `tcp:127.0.0.1:4444`）
  发 `sendkey`、改密码、查状态。
- SAF 磁盘：`FileUtils.encodeDocumentFilePath()` 把 `content://` 变成
  `/dev/fdset/<set>` 并加 `-add-fd`；运行中换盘走 `nativeAddFd()` →
  `limbo_fdset_add()`。`-kernel`/`-initrd` 不能走 fdset，会先拷到 app cache。
- `qemu-img` 以库形态提供：`libqemu-img.so` 导出 `limbo_img_create()`（直接调
  `bdrv_create`，绕开 `main()/exit()`），JNI 是 `VMExecutor.nativeCreateImage`。
- 音频固定用原生后端：`-audiodev aaudio|opensles,id=sdl,...`，不用 SDL 的 Android
  音频驱动（VNC 下没有 SDL 视频上下文）。AAudio 用 `dlopen("libaaudio.so")` 以兼容
  低 API。新增 audio driver 必须同步改三处分派，见 patch 0004。
- UI 附加功能：`ScreenSaver`（默认 30 s，0 关闭；SDL 隐藏系统栏，VNC 播 DVD logo）、
  `SpecialKeysBar`（修饰键按住 + 一次性语义）、`KeyboardUtils`。窗口必须设
  `SOFT_INPUT_ADJUST_RESIZE`，否则 targetSdk 29 下 IME insets 恒为 0。

## 硬约束与易踩坑

- **一个进程只能 `qemu_init` 一次**。`VMExecutor.qemuInitializedOnce` 会拦截第二次启动并
  提示用户重开 App；不要移除这个检查，也不要尝试同进程 stop→start。
- **`sigsetjmp` 替换**：bionic 的带 PAC 签名，协程跨栈使用会 SIGILL。`link-qemu-so.py`
  用 `--whole-archive libandroid-setjmp.a` + `-Bsymbolic-functions` 绑进 QEMU .so。
  协程后端必须是 `--with-coroutine=sigaltstack`。
- **UEFI 只能挂一个 `-pflash`**。32/64 位同时挂会把映射数推到 `vm.max_map_count`
  之上，SDL 下 Scudo OOM。`ENABLE_32_UEFI`/`ENABLE_64_UEFI` 都勾选时按架构取一个。
- **`DT_NEEDED` 必须用打包名**（`libglib-2.0.so` 等）。`fix-needed.sh` 改 QEMU 的依赖名，
  `sync-jnilibs.sh` 同时把每个库的 SONAME 改成文件名；少一步会在 bionic 上报
  `cannot find ... from verneed`。QEMU 还要 `--no-as-needed -llimbo`，否则 weak 的
  `Android_JNI_SetVMResolution` 不会进 `DT_NEEDED`。
- **16 KB 页**：链接加 `-Wl,-z,max-page-size=16384`；打包必须用支持 `-P` 的
  `zipalign`（build-tools 35+），`.so` 保持未压缩。细节见
  [docs/agents/packaging.md](docs/agents/packaging.md)。
- **pkg-config 只能看到 `$PREFIX`**。`scripts/env.sh` 已设 `PKG_CONFIG_LIBDIR`；
  不要把宿主路径加回来。
- **PGO profile 的键带相对源码路径**。`prepare-pgo-profile.sh` 会按当前
  `QEMU_BUILD→QEMU_SRC` 重写；移动工作区后删 `../build/qemu-pgo.profdata` 让它重生成。
- QEMU 日志固定写到 `/data/data/com.limbo.emu.dontknowhy/cache/qemu.log`
  （`vm-executor-jni.c` 里硬编码）。
- `libcompat-limbo.so` 已不存在；`set_jni`、`Android_JNI_SetVMResolution`、
  `FileUtils.nativeAddFd` 都在 `liblimbo.so`。不要再拆出第二个 compat 库。
- 不要引入需要运行时依赖的库（libunwind/libomp/mimalloc 等），也不要用
  `-march=native`；目标 flags 是 `-march=armv8-a+simd+crc+crypto`。

## 验证

仓库没有单元测试套件，验证靠“编译 + 真机 smoke”：

- 原生改动：`make native`（exit 0），再用 `../build/tools/limbo-smoke` 在设备上
  dlopen 新 `.so` 并启动一个 guest；或 `scripts/serial-bench.py` 跑 Alpine
  登录 + `dd|md5`。步骤见 [docs/agents/debugging.md](docs/agents/debugging.md)。
- App 改动：`make apk-debug` 后安装；release 打包额外检查
  `zipalign -c -P 16 4` 与 `apksigner verify`。
- 声称“已验证”时给出命令、退出码和关键日志；没跑过就写“未验证”。

## 编码约定

改动应像原项目作者写的：先读目标文件和 1–2 个同类文件，最小 diff，复用现有 helper，
不引入新抽象/依赖/配置项，不顺手重构或重排 import。UI 中文串与英文串并存是现状，
不要批量翻译或“规范化”。提交信息沿用仓库风格：中文、简短、陈述改动，不要加
IOPaint 那类 `[<model>老师]` 前缀。完整版（含“何时该重写而不是硬缩 diff”）见
[docs/agents/coding-principles.md](docs/agents/coding-principles.md)。

## 文档索引

- [docs/agents/coding-principles.md](docs/agents/coding-principles.md) — 编码原则全文，
  以及本仓库的验证替代方案（无测试套件）。（触发：写/审任何代码改动）
- [docs/agents/build.md](docs/agents/build.md) — 工具链、依赖构建顺序、QEMU configure
  选项、LTO/PGO、重链接、stamp 与常见构建失败。（触发：改构建脚本、依赖或 QEMU 配置）
- [docs/agents/qemu-patches.md](docs/agents/qemu-patches.md) — 6 个 patch 的主题、
  新增文件、setjmp 替换、改完 `jni/qemu` 后如何重生成并逐字节验证。（触发：碰 QEMU 源码/补丁）
- [docs/agents/app.md](docs/agents/app.md) — Java 控制面：启动/停止、参数拼装、SAF、
  VNC/QMP、qemu-img、屏保/按键条与生命周期细节。（触发：改 app/JNI 行为）
- [docs/agents/packaging.md](docs/agents/packaging.md) — 签名、16 KB 对齐、APK 产物与
  MIUI 安装。（触发：打包或安装 release APK）
- [docs/agents/debugging.md](docs/agents/debugging.md) — qemu.log、limbo-smoke、
  DT_NEEDED 排查、串口跑分与 PGO 重训。（触发：真机启动失败或做性能对比）
