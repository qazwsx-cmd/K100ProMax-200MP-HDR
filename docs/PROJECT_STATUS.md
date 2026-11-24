# Project status

**Last updated:** 2026-11-24

## Current outcome

The user has explicitly confirmed that HDR cannot currently be triggered on the target phone. The project is therefore **not complete** and must not be described as a working 200MP HDR implementation.

## Confirmed project inputs

- Target device: Redmi K100 Pro Max (`songyuan`).
- OS: Android 17 / HyperOS 4.
- Stock camera: `com.android.camera` 6.7.000280.0 (`670002800`).
- LSPosed: 2.2.1 (7912); libxposed API 102.
- Source snapshots available: v0.1.5 and v0.1.6.
- The v0.1.6 source diff and v0.1.5 read-only diagnostic script are preserved in this repository.

## Latest v0.1.5 status payload supplied in the conversation

The supplied status payload reported:

- LSPosed framework service connected; API 102.
- Camera scope selected/enabled.
- Framework target for camera process was `up_to_date` with module version code 6.
- `camera_entry=false` and `camera_module_loaded=false`.
- `camera_hook_error=false`; framework and module log fields were empty.

This confirms framework service/scope visibility, but **does not prove that the Java hook entry executed**. An empty error field is not proof of success.

## v0.1.6 validation boundary

Completed locally:

- `HdrPolicyTest` compiled and passed.
- `HdrModule` / `HdrPolicy` passed a Java compile check against minimal API stubs, including the API 102 `Chain.proceedWith(thisObject, args)` shape.
- Source diff and README were reviewed.

Not completed:

- Full build against Android SDK platform 37, Build Tools 36.0.0 and the actual libxposed API/interface JARs.
- Installation and LSPosed loading on the target phone.
- Confirmation that the original `r6.b` callback is hooked and receives the forced scene state.
- Confirmation that a 200MP CaptureRequest contains `xiaomi.hdr.enabled=true`.
- Confirmation that the camera provider/MIA2 selects and executes the HDR multi-frame pipeline.
- Confirmation of multiple exposure frames, final merge, HDR metadata, or visual dynamic-range improvement.

## Known risks

- Forcing Auto HDR scene state for every eligible 200MP shot may increase capture latency and can create motion ghosting.
- A Java-side scene state does not guarantee that the HAL/provider accepts the request or executes multi-frame HDR.
- Do not increase `xiaomi.multiframe.inputNum` without matching real frame buffers and a validated capture strategy.
- Do not mark HDR as working based only on UI state, a hook log, or a single request tag.

## Next engineering gates

1. Confirm hook entry and method signature on the exact camera APK.
2. Build and install v0.1.6 with a known signing key.
3. Confirm the original callback receives the intended boolean only in the guarded 200MP path.
4. Inspect submitted capture metadata and frame sequence.
5. Confirm the provider's MIA2 pipeline and HDR plugin actually execute.
6. Compare original JPEG/DNG metadata and controlled static/moving-scene samples.
7. Add an explicit opt-out and rollback path if ghosting or instability occurs.