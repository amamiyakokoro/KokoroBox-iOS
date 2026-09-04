<div align="center">

<img src="SFI/Assets.xcassets/AppIcon.appiconset/1024.png" width="112" alt="KokoroBox icon">

# KokoroBox

An Apple-platform sing-box client with native Kokoro subscription support.

</div>

## About

KokoroBox is an experimental Apple-platform client for [sing-box](https://sing-box.sagernet.org/), maintained for the Kokoro service. It is based on the upstream sing-box for Apple applications and adds first-party Kokoro account and subscription integration.

The installed display name is **KokoroBox**. The primary application bundle identifier is `com.amamiyakokoro.box`.

## Highlights

- **Native Apple experience** — platform-specific apps for iOS, iPadOS, macOS, and tvOS
- **sing-box profiles** — local and remote profile management with validation before activation
- **Kokoro integration** — secure account sign-in and server-driven subscription options
- **Secure credentials** — Apple Keychain storage with automatic access-token refresh
- **Network integration** — Apple Network Extension and standalone macOS system modes

## Kokoro subscriptions

KokoroBox can create and maintain sing-box profiles directly from a Kokoro account:

- Secure osu! sign-in through the system browser
- Server-driven plan, ISP, protocol, routing, and update options
- VMess, AnyTLS, and Hysteria 2 subscription profiles when enabled by the server
- Configuration validation before replacing the active local profile

Access tokens, refresh tokens, subscription credentials, and complete subscription URLs must never be included in logs, screenshots, analytics, or issue reports.

## Applications

| Platform         | Xcode scheme | Product          |
| ---------------- | ------------ | ---------------- |
| iOS and iPadOS   | `KokoroBoxI` | `KokoroBoxI.app` |
| macOS            | `KokoroBoxM` | `KokoroBoxM.app` |
| macOS standalone | `SFM.System` | `KokoroBoxM.app` |
| tvOS             | `SFT`        | `KokoroBox.app`  |

## Build from source

### Requirements

- A recent Xcode release with the required platform SDKs
- A compatible `Libbox.xcframework` at the repository root
- An Apple Developer team and matching provisioning profiles for signed, on-device builds
- `make` and `xcbeautify` when using the provided command-line targets

Clone the repository with its submodules:

```bash
git clone --recurse-submodules https://github.com/amamiyakokoro/KokoroBox-iOS.git
cd KokoroBox-iOS
```

Open `sing-box.xcodeproj` in Xcode and select the scheme for the platform you want to build, or use one of the common local build commands:

```bash
make build_ios
make build_macos
make build_macos_standalone
make build_tvos
```

Code signing, application groups, Network Extension capabilities, and provisioning profiles must belong to your own Apple Developer team. Release and notarization targets in the `Makefile` additionally require the corresponding Apple distribution certificates and signing identities.

## Project structure

| Path                              | Purpose                                              |
| --------------------------------- | ---------------------------------------------------- |
| `ApplicationLibrary`              | Shared application services and views                |
| `Library`                         | Shared database, network, update, and utility code   |
| `SFI`                             | iOS and iPadOS application                           |
| `SFM`                             | macOS application                                    |
| `SFM.System`                      | Standalone macOS application and packaging resources |
| `SFT`                             | tvOS application                                     |
| `Extension` and `SystemExtension` | Network extension implementations                    |
| `Frameworks`                      | Embedded editor and parsing frameworks               |

## Contributing

Bug reports and focused pull requests are welcome. Please use [GitHub Issues](https://github.com/amamiyakokoro/KokoroBox-iOS/issues) for reproducible bugs and feature proposals, and update the documentation when behavior changes.

Never commit access tokens, subscription URLs, signing certificates, provisioning profiles, OAuth secrets, or generated private configuration files.

## Upstream and license

KokoroBox is derived from [SagerNet/sing-box-for-apple](https://github.com/SagerNet/sing-box-for-apple). The original [SFI](https://sing-box.sagernet.org/installation/clients/sfi/) and [SFM](https://sing-box.sagernet.org/installation/clients/sfm/) documentation remains useful for platform-specific sing-box behavior.

The project is distributed under the [GNU General Public License version 3 or later](LICENSE). Individual dependencies remain subject to their respective licenses.
