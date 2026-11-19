# Coding principles

How every change in this repo is written: the diff should look as if the project's
original author wrote it. When unsure, choose “less, dumber, closer to the status quo”.
`AGENTS.md` carries the one-paragraph summary; this file is the long form.

## 1. Read before writing

- Before touching anything, read: the target file, 1–2 files of the same kind, and the
  code that calls or is called by it. Stop once that is enough; do not scan the whole repo.
- Java control-plane changes usually cross three layers — `VMExecutor` / `Config`
  (QEMU command line), `MachineController` / `MachineService` (lifecycle), and the
  Activity (UI). Read all three before changing a VM parameter.
- Native changes usually cross `jni/limbo` (JNI entry points), `jni/compat` (bionic
  shims) and the QEMU patch series. Read the matching patch before adding a new hook.
- Reuse existing helpers/constants. Do not invent a second path for something the app
  already does (e.g. do not add a new QMP client or a new fdset encoder).

## 2. Minimal change

- Change only what the task needs. Do not reformat, re-sort imports, rename unrelated
  symbols, or “modernize” old upstream code.
- One task, one thing. A nearby bug gets reported, not fixed in passing, unless the
  human asked for it.
- Readability beats line count: if three edited lines do, do not rewrite the function;
  but never twist the code to keep the diff small — rewrite when rewriting is right and
  explain why.
- Large change or cross-cutting behaviour: state the approach and impact surface in the
  reply first, then start.

## 3. Follow existing conventions

- Naming, package layout, error handling, logging (`Log.d/e`, `ToastUtils`) and resource
  naming follow the surrounding code.
- Keep the two Java package roots as they are: `com.max2idea.android.limbo.*` for the
  upstream-derived code and `com.limbo.emu.dontknowhy.*` for the fork's entry point.
- Do not introduce a new abstraction layer, dependency or design pattern unless the task
  explicitly requires it. A new dependency needs a stated reason and consent first.
- UI copy is deliberately CN/EN mixed. Keep the style of the file you edit; never bulk
  translate, delete or “normalize” existing Chinese text.

## 4. Against over-engineering

- No interfaces, parameters or config options reserved for “possible future needs”.
- No helper with a single call site; no factory/strategy/DI for simple logic.
- No defensive branches for inputs the caller cannot produce. QEMU itself validates most
  machine options; do not duplicate that validation in Java.
- Comments explain *why*, never restate *what*. Do not leave “temporary” debug logging.

## 5. Honesty and boundaries

- For an API, NDK behaviour or QEMU option you are unsure about, verify it (source,
  `--help`, a build) or say explicitly “I'm not sure”. Fabricating is forbidden.
- Do not edit code you have not understood. Do not delete code that “looks unused” — it may
  be reached through JNI/`dlsym` or reflection.
- State implicit assumptions (API level, ABI, QEMU option validity) in the reply.
- Do not weaken a check just to make a build pass (e.g. removing
  `--no-as-needed -llimbo`, `qemuInitializedOnce`, or a `DT_NEEDED` rewrite).
- Destructive commands (`rm -rf`, `make distclean` on a tree with uncommitted work,
  force-push) need explicit approval.

## 6. Verification

This repository has **no unit-test suite**. Do not invent one, and do not claim a test
run that did not happen. Verify proportionally:

- Java/UI-only change: `make apk-debug`, install, exercise the screen. At minimum the
  Gradle build must succeed.
- JNI / `liblimbo` change: `make liblimbo` or `make native`, then the device smoke path
  in `docs/agents/debugging.md` if behaviour depends on QEMU being loaded.
- QEMU source/patch change: rebuild, re-link, `fix-needed.sh`, apply the patch series to a
  pristine tarball and confirm it reproduces `jni/qemu` byte-for-byte
  (`docs/agents/qemu-patches.md`).
- Benchmark/performance claim: use `scripts/serial-bench.py`, give min/median and run
  count, and never compare across machines.
- A native-library change is not “verified” until it has been dlopen'ed on a device or in
  the smoke harness; a successful link alone proves very little on bionic.

## 7. Delivery

- Self-check the diff: no unrelated edits, no generated files, no `.so`, no `jni/qemu`
  changes left outside the patch series.
- Report what changed, why, the exact verification commands and their results, and what is
  still unverified.
- If the task is ambiguous, ask before guessing your way through a big change.

## 8. Documentation duty

- A new build command, a new mandatory check, a new patch topic or a pitfall that will
  recur earns 1–2 sentences in the matching `AGENTS.md` section or `docs/agents/*.md`.
- A statement that no longer matches the code is corrected immediately. Example already
  fixed here: `minSdk` is 29, not the “API 21” the old README repeats.
- Documentation records current behaviour, never the history of a change: “the build does
  X”, not “I fixed X”. The same rule governs commit messages and code comments.
- Commit messages in this repo are short, Chinese, statement-style. Do not copy the
  IOPaint `[<model>老师]` subject convention.
