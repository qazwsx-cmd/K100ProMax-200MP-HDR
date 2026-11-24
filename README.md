# Redmi K100 Pro Max · 200MP HDR

A device-specific LSPosed/libxposed module research project for the stock Xiaomi Camera app on Redmi K100 Pro Max (`songyuan`). The project investigates why 200MP capture does not enter the stock HDR path and attempts to route the 200MP Auto HDR scene state through Xiaomi's original HDR state machine.

> **Status: experimental / not yet verified on-device.** The user has confirmed that HDR still cannot currently be triggered. The v0.1.6 change is a source-level hypothesis and has not been built against the complete Android 37 + libxposed toolchain, installed, or validated with a real 200MP capture. Do not treat an enabled UI option, a Java hook callback, or a request metadata value as proof of multi-frame HDR fusion.

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

- `versions/v0.1.5/` — complete v0.1.5 source snapshot.
- `versions/v0.1.6/` — complete v0.1.6 source snapshot, including the experimental 200MP scene-trigger change.
- `patches/v0.1.6.patch` — source diff from v0.1.5 to v0.1.6.
- `scripts/` — read-only device diagnostic script for v0.1.5.
- `reports/Camera_6.7_Algorithm_Audit_zh.md` — full camera algorithm audit; it covers broader camera-quality topics as well as the HDR/MIA2 findings.
- `docs/HDR_RESEARCH_SUMMARY.md` — focused summary of the HDR path and evidence boundaries.
- `docs/PROJECT_STATUS.md` — latest confirmed project status and outstanding work.
- `docs/BUILD_AND_INSTALL.md` — build requirements and safe installation notes.

## What v0.1.6 changes

v0.1.5 exposed/observed the stock high-resolution HDR component but only observed the scene callback after the stock method ran. If the stock scene detector always returned `false`, the stock state machine could keep `xiaomi.hdr.enabled=false`, so the camera never produced an HDR request.

v0.1.6 adds a guarded path for the rear 200MP mode: when the stock preference is Auto/On/Normal and the stock component is not muted or empty, it supplies a positive scene result to the original `r6.b.onHdrSceneChanged(boolean)` callback and preserves the scene state before the stock preference-application method. It does **not** directly forge vendor HDR tags, exposure values, or frame counts.

This is not yet proven to trigger a valid request or a multi-frame fusion pipeline. See `docs/PROJECT_STATUS.md` and `docs/HDR_RESEARCH_SUMMARY.md`.

## Build

See `docs/BUILD_AND_INSTALL.md` and `versions/v0.1.6/README.md`. Signing credentials and proprietary Xiaomi camera binaries are intentionally not included.

## Safety / scope

- This is a device- and camera-version-specific experiment, not a general Xiaomi camera module.
- The module should remain scoped only to the stock camera process.
- The stock camera and vendor libraries are not redistributed here.
- Do not change MIA2 configuration, camera provider libraries, SELinux policy, or vendor properties as part of this Java-hook experiment without a separate backup and rollback plan.

## License

No project-wide license has been declared. The included libxposed interface license text is retained in each source snapshot. Do not assume the project source is licensed for redistribution or reuse until a project license is selected.