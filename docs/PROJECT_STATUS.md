# Project status

**Last updated:** 2026-11-24

## Current outcome

The user has explicitly confirmed that 200MP HDR still cannot currently be triggered on the target phone. The project is **not complete** and must not be described as a working 200MP HDR implementation.

## Confirmed target

- Device: Redmi K100 Pro Max (`songyuan`).
- OS: Android 17 / HyperOS 4; SDK 37.
- Stock camera: `com.android.camera` 6.7.000280.0 (`670002800`).
- LSPosed: 2.2.1 (7912); libxposed API 102.
- Module package: `dev.songyuan.hdr`.
- Source archives preserved: v0.1.4, v0.1.5, and v0.1.6.
- APK artifacts preserved: v0.1.4 and v0.1.5.

## Latest read-only diagnostic supplied by the user

The diagnostic ran with `logd=running` and found the installed v0.1.5 APK hash matching the expected build.

The camera process was PID 10669 (UID 10149, user 0). The credential-protected camera cache contained `songyuan200hdr-status.properties`; the device-encrypted cache did not contain a status file.

The status journal recorded:

```properties
phase=READY
module_entry=MODULE_LOADED module=0.1.5 process=com.android.camera
package_loaded=PACKAGE_LOADED module=0.1.5
package_ready=ENTRY module=0.1.5 API=102 process=com.android.camera
startup_hooks=[CONTEXT_ATTACH, INSTRUMENTATION_CREATE, CAMERA_APPLICATION_CREATE, CAMERA_ACTIVITY_CREATE, CAMERA_ACTIVITY_RESUME]
mode=200MP component ready, cameraId=2 stockHdhdr=0x0 requestRoute=true
scene=false
request stage=1 hdrMode=2 hdrEnabled=false checker=null checkerStatus=null
```

Interpretation:

- The journal is positive evidence that the v0.1.5 module entry and several startup lifecycle hooks executed in the camera process.
- The earlier status UI fields `camera_entry=false` and `camera_module_loaded=false` were inconsistent with the journal and should not be treated as definitive entry-failure evidence.
- The 200MP component was reported ready for cameraId 2.
- `stockHdhdr=0x0`, `scene=false`, and `hdrEnabled=false` show that the observed state did not reach an enabled HDR state.
- The journal's `requestRoute=true` field is an internal module diagnostic; it does not prove that a CaptureRequest with HDR metadata was submitted or accepted.
- The user confirms that HDR cannot be triggered. No real multi-exposure capture or MIA2 fusion has been demonstrated.

## v0.1.6 validation boundary

The v0.1.6 source archive and patch are preserved for review. The source-level experiment attempts to force the guarded 200MP Auto HDR scene callback into the original stock state machine.

Not completed:

- Full build with Android SDK Platform 37, Build Tools 36.0.0, and the exact libxposed API/interface JARs.
- Installation and LSPosed loading of v0.1.6 on the target phone.
- Confirmation that the exact original callback is hooked on this camera build.
- Confirmation that a submitted CaptureRequest contains `xiaomi.hdr.enabled=true`.
- Confirmation that the provider receives and accepts the request.
- Confirmation that MIA2 selects and executes an HDR multi-frame pipeline.
- Confirmation of distinct exposure frames, merge output, HDR metadata, or measured dynamic-range improvement.

## Known risks

- Forcing Auto HDR scene state for every eligible 200MP shot may increase capture latency and create motion ghosting.
- A Java-side scene state does not guarantee that the HAL/provider accepts the request or executes multi-frame HDR.
- Do not increase `xiaomi.multiframe.inputNum` without matching real frame buffers and a validated capture strategy.
- Do not mark HDR as working based only on UI state, a hook log, or a single request tag.

## Next engineering gates

1. Verify the exact target method/signature in the installed camera build.
2. Complete a reproducible v0.1.6 Android build with known signing credentials.
3. Install and verify the guarded callback path on-device.
4. Inspect actual submitted capture metadata and frame sequence.
5. Confirm provider/MIA2 pipeline selection and HDR plugin execution.
6. Compare original JPEG/DNG metadata and controlled static/moving-scene samples.
7. Keep an explicit opt-out and rollback path if latency, ghosting, or instability appears.
