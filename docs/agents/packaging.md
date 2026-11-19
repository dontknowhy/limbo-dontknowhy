# APK packaging and signing

`make apk` = `make native` + `make keystore` + `scripts/package-apk.sh release`.
`make apk-debug` skips signing/alignment (Gradle debug key).

## Release pipeline

```
gradle :limbo-android-x86:assembleRelease     # unsigned APK
zipalign -P 16 -f 4 unsigned.apk aligned.apk  # 16 KB ZIP alignment
apksigner sign --ks $KEYSTORE ...             # v1+v2+v3
zipalign -c -P 16 4 final.apk                 # verify
apksigner verify --print-certs final.apk      # verify
```

- AGP 8.1 only aligns to 4 KB, so the alignment step is explicit and runs **before**
  signing. `zipalign` must support `-P <pagesize>` (build-tools 35.0.0+); the script
  refuses to run otherwise.
- Native libraries are stored **uncompressed** (`useLegacyPackaging = false`).
- ELF side: NDK r30 plus `-Wl,-z,max-page-size=16384` in `CROSS_LD_16K`
  (`scripts/env.sh`) gives every LOAD segment `p_align >= 0x4000`.
- `package-apk.sh` picks build-tools by scanning `36.0.0/35.0.0/34.0.0` for a `zipalign`
  that understands `-P`; set `BUILD_TOOLS=` to force a directory.

Outputs (workspace `build/`, not the Gradle `build/`):

- `../build/limbo-x86-qemu11-arm64-release.apk`
- `../build/limbo-x86-qemu11-arm64-debug.apk`

`package-apk.sh` prints the size and sha256 of the result.

## Signing key

- Default: `$LIMBO_ROOT/keystore/limbo-release.jks` and
  `$LIMBO_ROOT/keystore/keystore.properties` (keys `keyAlias`, `storePassword`,
  `keyPassword`). This is the fork's published demo key.
- The keystore is deliberately **outside the git checkout** and directories are
  gitignored. Override `KEYSTORE`/`KEYSTORE_PROPERTIES`/`KEYSTORE_DIR` for CI or a private
  key.
- `make keystore` generates a demo key only if neither file exists. Switching keys makes
  existing installs fail to upgrade (`INSTALL_FAILED_UPDATE_INCOMPATIBLE`); uninstall
  first.
- `apksigner` is invoked with `--min-sdk-version 24`; keep that in mind if you compare
  signatures with a differently configured tool.

## Installing

```bash
adb install -r ../build/limbo-x86-qemu11-arm64-release.apk
```

MIUI often rejects `adb install`; use:

```bash
adb push ../build/limbo-x86-qemu11-arm64-release.apk /data/local/tmp/limbo.apk
adb shell pm install -r /data/local/tmp/limbo.apk
```

## Verification checklist

```bash
$BUILD_TOOLS/zipalign -c -P 16 4 ../build/limbo-x86-qemu11-arm64-release.apk
$BUILD_TOOLS/apksigner verify --print-certs ../build/limbo-x86-qemu11-arm64-release.apk
$READELF -lW limbo-android-x86/src/main/jniLibs/arm64-v8a/libqemu-system-x86_64.so | grep LOAD
```

`zipalign -c` must print `Verification successful`; `apksigner verify` must not report
errors; every LOAD `Align` must be `0x4000` (16 KB). A release binary that was linked
without `-z max-page-size=16384` passes the ZIP check but fails on 16 KB-page devices.

## APK size

The QEMU `.so` dominates (~31 MB stripped, full LTO + PGO). Do not add `android:extractNativeLibs`
or re-enable legacy packaging to “fix” size; it breaks the 16 KB requirement. Do not
commit the APK or `jniLibs` binaries.
