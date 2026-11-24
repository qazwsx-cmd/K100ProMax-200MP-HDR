# Build and install

## Build prerequisites

The source README specifies:

- JDK 17 or newer.
- Android SDK Platform 37.
- Android Build Tools 36.0.0.
- libxposed API 102.0.0 JAR.
- libxposed interface 102.0.0 `classes.jar`.
- A user-provided signing keystore and password file.

Environment variables used by `build.sh`:

- `JAVA_HOME`
- `ANDROID_SDK_ROOT`
- `LIBXPOSED_API_JAR`
- `LIBXPOSED_INTERFACE_JAR`
- `SONGYUAN_KEYSTORE`
- `SONGYUAN_KEY_PASSWORD_FILE`

The build expects a signing alias named `songyuan-hdr`. Signing keys and passwords are intentionally not included in this repository.

## Build command

From the selected version directory:

```sh
bash build.sh
```

The build script writes the signed APK under that version's `build/` directory.

## Install / scope

1. Install the APK.
2. Enable the module in LSPosed.
3. Select only the current user's stock camera package `com.android.camera` as the module scope.
4. Force-stop the camera and relaunch it after installing or changing the module.
5. Open the module status UI and inspect the hook-entry and camera-process state.

## Rollback

Disable the module in LSPosed, then force-stop and reopen the stock camera. Do not remove or replace stock camera/vendor components as a rollback method.

## Important

The v0.1.6 source snapshot has not been built with the full toolchain or installed on the target device. A successful APK build or hook log does not prove that the ISP/provider performs multi-frame HDR fusion.