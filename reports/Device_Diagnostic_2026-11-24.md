# Device diagnostic — 2026-11-24

This note records the read-only output supplied by the device owner for the K100 Pro Max HDR module v0.1.5.

## Environment

- Device: `songyuan`
- SDK: 37
- Android user: 0
- `logd`: running
- Camera package: `com.android.camera`
- Camera version: 6.7.000280.0
- Module APK SHA-256: `0084fc90461eb6c8473d768532ed40e06febe8160f5974dd2998b79654856d87` (matched the v0.1.5 expected hash)
- Camera process: PID 10669, UID 10149, user 0

## Status journal

The file `/data/user/0/com.android.camera/cache/songyuan200hdr-status.properties` existed. The device-encrypted cache did not contain a corresponding status file.

Key recorded values:

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

## Interpretation

- The journal is evidence that the module entry and several camera startup lifecycle hooks executed.
- The 200MP component reported ready for cameraId 2.
- The observed stock HDR capability value was `0x0`; the scene state was false and the recorded HDR-enabled value was false.
- The internal `requestRoute=true` journal field does not prove that a CaptureRequest with HDR metadata was submitted or accepted.
- The owner confirmed that HDR still cannot be triggered. No multi-exposure capture or MIA2 fusion was demonstrated.

This diagnostic supersedes the earlier UI-only false-negative interpretation for module entry. It does not establish working HDR.
