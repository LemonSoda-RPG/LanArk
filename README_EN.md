# LanArk

LanArk is a native HarmonyOS NEXT LANraragi reader written in ArkTS and ArkUI. It connects to a LANraragi server on the local network and provides a cached archive library, cover browsing, tags, reading progress synchronization, and a responsive reader for phones and tablets.

## Features

- Multiple LANraragi server profiles with per-server API key configuration
- API key storage through HarmonyOS Asset Store Kit
- Local library-index and cover caching
- List and cover-grid layouts with automatic or fixed grid columns
- Search, category filtering, and multiple sort modes
- Reading progress synchronization with immediate local updates
- Single-page, two-page, and continuous reading modes
- Left-to-right and right-to-left reading directions
- Tap-to-turn pages, page slider, pinch zoom, and panning
- Configurable page preloading
- In-app offline archive downloads, with per-page progress and resumable partial downloads
- Downloaded archive library and download manager pages
- Fixed high-resolution decode policy for large source images
- Selectable image interpolation: nearest neighbor, bilinear, MipMap, or cubic
- Dark mode, portrait/landscape rotation that respects the system rotation lock, and phone/tablet layout adaptation
- English resources and automatic English UI labels when the system language is English

## Requirements

| Component | Recommended version |
| --- | --- |
| DevEco Studio | 6.1.1 Release |
| HarmonyOS SDK | 6.1.1 Release (API 24) |
| Build system | Hvigor supplied by DevEco Studio or Command Line Tools |
| Package manager | OHPM supplied by DevEco Studio or Command Line Tools |
| Runtime device | HarmonyOS NEXT phone or tablet |

The project uses the Stage model, ArkTS, ArkUI, and the following system kits:

- Ability Kit
- ArkUI
- ArkData (Preferences)
- Asset Store Kit
- Basic Services Kit
- Core File Kit
- Image Kit
- Localization Kit
- Network Kit
- Performance Analysis Kit

No third-party runtime UI framework is required. The test targets use `@ohos/hypium` and `@ohos/hamock`; these are development-only dependencies.

## Project layout

```text
AppScope/                         Application metadata, icon, and app resources
entry/src/main/ets/               ArkTS application code
entry/src/main/resources/base/   Default resources
entry/src/main/resources/en_US/  English resource overrides
entry/src/main/resources/dark/   Dark-mode media and colors
build-profile.json5              Product and SDK build configuration
oh-package.json5                 OHPM dependencies
oh-package-lock.json5            Locked dependency versions
hvigorfile.ts                    Root build entry
```

## Localization

HarmonyOS selects resource qualifiers from the device configuration. The default strings are in `resources/base/element/string.json`, and the English overrides are in `resources/en_US/element/string.json`. UI text referenced through `$r('app.string...')` follows the selected resource automatically. Dynamic labels and validation messages use `@kit.LocalizationKit` and switch to English when `i18n.System.getSystemLanguage()` starts with `en`.

To test English UI, change the device system language to English and relaunch LanArk. The app does not store a separate language preference; it follows the system language.

## Open the project

Open the repository root in DevEco Studio, not only the `entry` directory:

```text
AppScope/
entry/
hvigor/
build-profile.json5
oh-package.json5
oh-package-lock.json5
hvigorfile.ts
```

Allow DevEco Studio to synchronize the project and install dependencies. Install the API 24 SDK from **Tools → SDK Manager** if it is not already available.

## Build a debug HAP

### DevEco Studio

1. Open the project root.
2. Select the `default` product and the `entry` module.
3. Choose **Build → Build Hap(s)/APP(s) → Build Hap(s)**.
4. Find the generated package under `entry/build/`.

### Command line

Run the command from the project root with the Hvigor wrapper supplied by your DevEco installation:

```powershell
.\hvigorw.bat --mode module -p product=default assembleHap --no-daemon
```

On Linux or macOS:

```bash
./hvigorw --mode module -p product=default assembleHap --no-daemon
```

Typical outputs are:

```text
entry/build/default/outputs/default/entry-default-unsigned.hap
entry/build/default/outputs/default/entry-default-signed.hap
```

`entry/build` is generated output and should not be committed.

## Signing

The public repository intentionally contains no personal signing certificates or profiles. Configure signing in **File → Project Structure → Signing** with your own `.p12`, `.cer`, `.p7b`, profile, and passwords before building a release HAP. Do not commit signing files, `local.properties`, generated HAP files, or private paths.

## Install on a device

Enable Developer mode and USB debugging on the phone or tablet, connect it to the computer, and accept the authorization prompt.

```powershell
hdc list targets
hdc install -r .\entry\build\default\outputs\default\entry-default-signed.hap
```

If no target is listed, check the USB cable, authorization prompt, HDC installation, and device developer settings.

## Connect to LANraragi

1. Open LanArk and enter the server URL in Settings, for example `http://192.168.1.10:3000`.
2. Enter the LANraragi API key if the server requires one.
3. Tap **Verify and save**.
4. Tap **Refresh** in the library to fetch the current index.

After saving, the endpoint appears under **Saved servers**. To switch servers, select another
profile and tap **Verify and save**. Use **Add server** to store another endpoint. Each profile's
API key is kept separately in HarmonyOS secure storage.

The URL must be reachable from the phone or tablet. `localhost` refers to the device itself, not the computer hosting LANraragi. The API key is never written to source code or README files; it is stored in the device secure storage.

## Image memory policy

Original encoded page bytes are cached locally for the current reading session. Large pages are decoded to a bounded target size (maximum long edge 4096 px and an estimated 64 MiB RGBA budget) before rendering. This keeps high-resolution pages readable without allocating an unbounded PixelMap. The interpolation option changes display resampling only; it does not disable the fixed decode limits.

## Data and privacy

- The app only reads the configured LANraragi server.
- It synchronizes reading progress and does not delete server documents during normal reading.
- Covers and temporary reading pages are stored in the app sandbox.
- Explicitly downloaded pages are kept in a separate persistent offline directory and are not removed by **Clear image cache**.
- Only complete downloads appear in the Downloaded page; interrupted downloads keep their partial pages and can be retried from Download manager.
- The Settings page can clear local image caches.
- Server URL, API key, signing files, generated HAPs, and personal paths are excluded from the public source package.

## Official references

- [HarmonyOS documentation center](https://developer.huawei.com/consumer/cn/doc/)
- [HarmonyOS multilingual resources](https://developer.huawei.com/consumer/cn/doc/HarmonyOS-Guides/l10n-multilingual-resources)
- [HarmonyOS application configuration files](https://developer.huawei.com/consumer/cn/doc/doccenter-getting-started/application-configuration-file-overview-stage)
- [LANreader reference project](https://github.com/Doraemoe/LANreader)

## License and notices

Review [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md) for icon and third-party resource notices. Add a project license before publishing a release if your distribution policy requires one.
