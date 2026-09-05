<div align="center">

<img src="SFI/Assets.xcassets/AppIcon.appiconset/1024.png" width="112" alt="KokoroBox icon">

# KokoroBox

An Apple-platform sing-box client with native Kokoro subscription support.

**Client:** 1.14.4 (build 4) · **Core:** 1.15.0-alpha.1-kokoro

</div>

KokoroBox is an experimental Apple-platform client based on [sing-box for Apple](https://github.com/SagerNet/sing-box-for-apple), with first-party Kokoro account and subscription support. Its primary bundle identifier is `com.amamiyakokoro.box`.

## Features

- Native clients for iOS, iPadOS, macOS, and tvOS
- Local and remote sing-box profiles with validation before activation
- Kokoro subscriptions with server-driven plan, ISP, protocol, routing, and update options
- Kokoro Custom Rules shared with the website and generated configurations
- System-browser osu! OAuth with mandatory PKCE S256 and Keychain token storage
- Apple Network Extension and standalone macOS modes

Kokoro sign-in is available on iOS, iPadOS, and macOS. See the [OAuth integration guide](docs/kokoro-oauth.md) and [Custom Rules client guide](docs/kokoro-custom-rules.md) for implementation and verification details.

## Applications

| Platform         | Xcode scheme | Product          |
| ---------------- | ------------ | ---------------- |
| iOS and iPadOS   | `KokoroBoxI` | `KokoroBoxI.app` |
| macOS            | `KokoroBoxM` | `KokoroBoxM.app` |
| macOS standalone | `SFM.System` | `KokoroBoxM.app` |
| tvOS             | `SFT`        | `KokoroBox.app`  |

## Build

Requires a recent Xcode, a compatible `Libbox.xcframework`, and an Apple Developer team for signed builds.

```bash
git clone --recurse-submodules https://github.com/amamiyakokoro/KokoroBox-iOS.git
cd KokoroBox-iOS
```

Open `sing-box.xcodeproj` and select a scheme, or use:

```bash
make build_ios
make build_macos
make build_macos_standalone
make build_tvos
```

Run the Kokoro API, OAuth, and session tests with:

```bash
swift test
```

Signing identities, App Groups, Network Extension capabilities, and provisioning profiles must belong to your Apple Developer team.

## License

[GNU General Public License v3 or later](LICENSE). Dependencies retain their respective licenses.
