# KokoroBox

KokoroBox is an experimental Apple-platform client for [sing-box](https://sing-box.sagernet.org/), maintained for the Kokoro service. It is based on the upstream sing-box for Apple applications and adds first-party Kokoro account and subscription integration.

## Applications

| Platform | Xcode scheme | Product |
| --- | --- | --- |
| iOS and iPadOS | `KokoroBoxI` | `KokoroBoxI.app` |
| macOS | `KokoroBoxM` | `KokoroBoxM.app` |
| macOS standalone | `SFM.System` | `KokoroBoxM.app` |
| tvOS | `SFT` | `KokoroBox.app` |

The installed display name is **KokoroBox**. The primary application bundle identifier is `com.amamiyakokoro.box`.

## Kokoro subscriptions

KokoroBox can create and maintain sing-box profiles directly from a Kokoro account:

- Secure osu! sign-in through the system browser
- Credentials stored in the Apple Keychain with automatic token refresh
- Server-driven plan, ISP, protocol, routing, and update options
- VMess, AnyTLS, and Hysteria 2 subscription profiles when enabled by the server
- Configuration validation before replacing the active local profile

Access tokens, refresh tokens, subscription credentials, and complete subscription URLs must never be included in logs, analytics, screenshots, or issue reports.

## Building

Clone the repository with its submodules, open `sing-box.xcodeproj` in Xcode, and select the scheme for the platform you want to build.

```sh
git clone --recurse-submodules https://github.com/amamiyakokoro/KokoroBox-iOS.git
cd KokoroBox-iOS
```

The project expects a compatible `Libbox.xcframework` at the repository root. Code signing, application groups, Network Extension capabilities, and provisioning profiles must belong to your own Apple Developer team.

Common local build commands:

```sh
make build_ios
make build_macos
make build_macos_standalone
make build_tvos
```

Release and notarization targets in the `Makefile` require the corresponding Apple distribution certificates and signing identities.

## Upstream

KokoroBox is derived from [SagerNet/sing-box-for-apple](https://github.com/SagerNet/sing-box-for-apple). The original client documentation remains useful for platform-specific sing-box behavior:

- [SFI documentation](https://sing-box.sagernet.org/installation/clients/sfi/)
- [SFM documentation](https://sing-box.sagernet.org/installation/clients/sfm/)

## License

```
Copyright (C) 2022 by nekohasekai <contact-sagernet@sekai.icu>

This program is free software: you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation, either version 3 of the License, or
(at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with this program. If not, see <http://www.gnu.org/licenses/>.
```
