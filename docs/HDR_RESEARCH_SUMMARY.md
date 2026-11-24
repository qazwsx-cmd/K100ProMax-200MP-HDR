# HDR research summary — K100 Pro Max / Camera 6.7.000280.0

## 1. Application-side control path

The camera APK contains separate application policy, request-building and rendering layers. The audit identified the HDR application entry around `n9.d0.M(p9.a)` and the old request path `n9.k0.j0()` writing the vendor key `xiaomi.hdr.enabled`. The APK also contains newer request construction wrappers (`Mp.*`, `Wp.*`, `pa.b0`). These are application-side request paths; a successful Java write is not proof of provider execution.

## 2. Relevant vendor metadata

The analyzed post-processing client merges app request settings into later metadata. Relevant keys include:

| Metadata key | Meaning / limit |
|---|---|
| `xiaomi.hdr.enabled` | HDR enable flag; Boolean normalization was identified. |
| `xiaomi.hdr.raw.enabled` | RAW HDR-related switch. |
| `xiaomi.hdr.sr.enabled` | HDR + super-resolution-related switch. |
| `xiaomi.mfnr.enabled` | Multi-frame noise-reduction switch. |
| `xiaomi.capturefusion.isFusionOn` | Fusion-related switch. |
| `xiaomi.multiframe.inputNum` | Multi-frame input count metadata; must match actual buffers and capture strategy. |

A tag value alone cannot create missing exposure frames or prove a merge occurred.

## 3. Native processing architecture

The target ROM investigation identified:

- `/odm/lib64/libmialgoengine.so` — MIA2 pipeline/plugin engine.
- `/system_ext/lib64/libmicampostproc_client.so` — client that connects to the Xiaomi post-processing service through HIDL and transfers frame/metadata information.
- MIA2 pipeline JSON root: `/odm/etc/camera/xiaomi/`.
- Plugin directories: `/odm/lib64/camera/plugins/`, `/odm/lib64/camera/preloadplugins/`, `/odm/lib64/camera/dynamicplugins/`.
- A high-resolution snapshot description named `superhdsnapshot.json` was found in the engine's pipeline-selection logic. Its name alone does not prove that a particular 200MP capture uses HDR.

The audit's device capture identified the Qualcomm camera provider process as the process loading MIA2 and associated plugins. That suggests the app-side hook and provider-side algorithm execution are separate stages.

## 4. Important evidence boundaries

The following statements are distinct and must not be conflated:

1. The module APK is installed.
2. LSPosed has the module enabled and the camera selected as scope.
3. The module's Java entry actually executes in the camera process.
4. The HDR component is initialized in the 200MP mode.
5. The app submits a request with `xiaomi.hdr.enabled=true`.
6. The provider receives and accepts the request.
7. MIA2 selects the relevant HDR-capable pipeline/plugin.
8. Multiple exposures are captured and merged into the final image.

Only the last stages establish actual HDR capture/fusion. Earlier stages are necessary but insufficient.

## 5. v0.1.5 failure hypothesis

The v0.1.5 hook observed the stock scene callback after the stock callback had already run. If the stock scene detector returned false, the stock state machine could retain `xiaomi.hdr.enabled=false`. The module could therefore report that its component was ready without causing an HDR request.

## 6. v0.1.6 source-level change

v0.1.6 introduces a guarded rear-200MP Auto/On/Normal path. When the component is neither muted nor empty, it:

- sets the stock scene field true before stock HDR preference application; and
- when the original scene callback would receive false, passes true into the original callback via libxposed API 102 `Chain.proceedWith`.

It deliberately does not forge `xiaomi.hdr.enabled`, exposure values, HDR mode, or multi-frame counts directly. The goal is to let Xiaomi's original state machine construct its own request and exposure plan.

This is an unverified source-level intervention. It may still fail if the hook target/signature is wrong, if the component is not active in 200MP mode, if the camera does not submit the request, or if the provider rejects/ignores the metadata.

## 7. Source report

See [`../reports/Camera_6.7_Algorithm_Audit_zh.md`](../reports/Camera_6.7_Algorithm_Audit_zh.md), especially sections 12–20 for MIA2, plugin, provider and HDR algorithm findings. The report also contains broader camera image-quality research outside this HDR-specific project.