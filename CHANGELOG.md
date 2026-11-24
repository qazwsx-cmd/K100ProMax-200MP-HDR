# Changelog

## v0.1.6 — 200MP Auto HDR scene-trigger experiment

- Added a guarded `shouldForceHighResScene` policy for rear 200MP Auto/On/Normal HDR.
- Before stock HDR preference application, set the stock scene state true under the same guard.
- If the original `onHdrSceneChanged(false)` callback would run under the guard, pass `true` to the original callback using libxposed API 102 `Chain.proceedWith`.
- Preserve stock behavior for explicit Off, muted/empty components, and unsupported/non-200MP paths.
- Add a status label distinguishing module-forced scene state from stock scene detection.
- Validation completed only at source/unit-test/stub-compile level; no full Android build or device validation.

## v0.1.5 — initial module snapshot

- Included LSPosed/libxposed module, status UI, framework/scope inspection and read-only status journal.
- Observed the high-resolution HDR component and stock scene/request state.
- Did not force a positive scene result; HDR remained untriggered when the stock detector returned false.