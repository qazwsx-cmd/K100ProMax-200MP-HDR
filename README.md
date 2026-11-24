# Redmi K100 Pro Max · 200MP HDR

A device-specific LSPosed/libxposed research project for the stock Xiaomi Camera app on Redmi K100 Pro Max (`songyuan`). The goal is to understand why 200MP capture does not enter the stock HDR path and to investigate a safe route through Xiaomi's original HDR state machine.

> **Current status: experimental; HDR is not triggering on the target device.** The user has explicitly confirmed this. The v0.1.6 change is a source-level experiment, not a verified HDR fix. A visible Auto HDR option, a Java hook callback, or a request metadata value is not proof of multi-frame HDR fusion.

## Target environment

| Item | Target |
|---|---|
| Device codename | `songyuan` |
| Device | Redmi K100 Pro Max |
| OS | Android 17 / HyperOS 4 |
| Camera package | `com.android.camera` |
| Camera version | `6.7.000280.0` (`670002800`) |
| Framework | LSPosed 2.2.1, libxposed API 102 |
| Module package | `dev.songyuan.hdr` |

## Repository layout

- `versions/v0.1.4/source.zip` — v0.1.4 source snapshot.
- `versions/v0.1.5/source.zip` — v0.1.5 source snapshot.
- `versions/v0.1.6/source.zip` — v0.1.6 source snapshot, including the experimental 200MP scene-trigger change.
- `artifacts/` — v0.1.4 and v0.1.5 module APKs supplied with the project materials.
- `patches/v0.1.6.patch` — source diff from v0.1.5 to v0.1.6.
- `scripts/` — read-only device diagnostic script for v0.1.5.
- `reports/Camera_6.7_Algorithm_Audit_zh.md` — full camera algorithm audit, including HDR/MIA2 findings and broader camera image-quality research.
- `docs/HDR_RESEARCH_SUMMARY.md` — focused summary of the HDR path and evidence boundaries.
- `docs/PROJECT_STATUS.md` — latest confirmed project status and outstanding work.
- `docs/BUILD_AND_INSTALL.md` — build requirements and safe installation notes.

The source ZIPs can be extracted locally to browse or build the corresponding version. Signing keys and passwords are not included.

## v0.1.6 experiment

v0.1.5 observed the stock high-resolution HDR component and scene state. Its diagnostics showed that the component could be ready while the scene state remained false and the request field remained disabled.

v0.1.6 adds a guarded rear-200MP Auto/On/Normal path. When the stock component is neither muted nor empty, it supplies a positive scene result to the original scene callback and preserves the scene state before stock preference application. It does **not** directly forge vendor HDR tags, exposure values, or frame counts.

This experiment has **not** been built with the complete target toolchain, installed, or validated on-device. It must not be described as a working HDR implementation. See `docs/PROJECT_STATUS.md` and `docs/HDR_RESEARCH_SUMMARY.md`.

## Build

See `docs/BUILD_AND_INSTALL.md`. Each source archive includes its own README and build script. The required Android SDK, libxposed dependencies, and a user-provided signing keystore are not bundled.

## Safety and scope

- This is a device- and camera-version-specific experiment, not a general Xiaomi camera module.
- Keep the module scoped only to the stock camera process.
- The stock camera APK and vendor libraries are not redistributed.
- Do not change MIA2 configuration, camera provider libraries, SELinux policy, or vendor properties without a separate backup and rollback plan.

## License

No project-wide license has been declared. The libxposed interface license text is retained in the source snapshots. Do not assume the project source is licensed for redistribution or reuse until a project license is selected.
