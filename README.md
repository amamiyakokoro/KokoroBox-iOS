<div align="center">

<img src="docs/assets/kokorobox-icon.png" width="112" alt="KokoroBox icon">

# KokoroBox

Native sing-box client for Apple platforms with Kokoro integration.

[Privacy](PRIVACY_POLICY.md) · [License](LICENSE)

</div>

## Features

- Local and remote profiles with validation, automatic updates, custom User-Agent, and safe reloads
- Server-driven Kokoro subscriptions and default Custom Rules editing
- System-browser osu! OAuth with mandatory PKCE S256 and Keychain token storage
- Exit IP with country flags, network quality, STUN, interface, route-table, and runtime diagnostics
- Network Extension and standalone macOS modes

## Supported platforms

KokoroBox supports iOS, iPadOS, and macOS. Its primary bundle identifier is `com.amamiyakokoro.box`.

## Get started

To build the app from source, clone the repository with submodules and open `sing-box.xcodeproj` in Xcode. Select `KokoroBoxI` for iOS/iPadOS or `KokoroBoxM`/`SFM.System` for macOS.

## Development

Requires Xcode and `xcbeautify`. Signed builds also need a compatible `Libbox.xcframework`, an Apple Developer team, and matching App Group, Network Extension, and provisioning settings.

```bash
git clone --recurse-submodules https://github.com/amamiyakokoro/KokoroBox-iOS.git
cd KokoroBox-iOS
make build_ios
make build_macos
swift test
```

## Documentation

- [OAuth and PKCE](docs/kokoro-oauth.md)
- [Custom Rules](docs/kokoro-custom-rules.md)
- [App Store Connect CI](docs/app-store-connect-ci.md)
- [Privacy policy](PRIVACY_POLICY.md)

## License

KokoroBox-iOS is based on [sing-box for Apple](https://github.com/SagerNet/sing-box-for-apple) and licensed under [GNU General Public License v3 or later](LICENSE). Dependencies retain their respective licenses.
