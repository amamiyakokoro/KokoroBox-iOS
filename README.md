<div align="center">

<img src="SFI/Assets.xcassets/AppIcon.appiconset/1024.png" width="112" alt="KokoroBox icon">

# KokoroBox

Native sing-box client for Apple platforms with Kokoro integration.

**Client:** 1.14.4 (5) · **Core:** 1.15.0-alpha.1-kokoro

</div>

KokoroBox is based on [sing-box for Apple](https://github.com/SagerNet/sing-box-for-apple). It supports iOS, iPadOS, macOS, and tvOS under the primary bundle identifier `com.amamiyakokoro.box`.

## Features

- Local and remote sing-box profiles with validation before activation
- Server-driven Kokoro subscriptions and Custom Rules
- System-browser osu! OAuth with mandatory PKCE S256 and Keychain token storage
- Network Extension and standalone macOS modes

## Build

Clone with submodules, then open `sing-box.xcodeproj` and select `KokoroBoxI` (iOS/iPadOS), `KokoroBoxM` or `SFM.System` (macOS), or `SFT` (tvOS).

```bash
git clone --recurse-submodules https://github.com/amamiyakokoro/KokoroBox-iOS.git
cd KokoroBox-iOS
make build_ios
make build_macos
swift test
```

Signed builds require a compatible `Libbox.xcframework`, an Apple Developer team, and matching App Group, Network Extension, and provisioning settings. Run Kokoro API and authentication tests with `swift test`.

Implementation details: [OAuth and PKCE](docs/kokoro-oauth.md) · [Custom Rules](docs/kokoro-custom-rules.md)

## License

[GNU General Public License v3 or later](LICENSE). Dependencies retain their respective licenses.
