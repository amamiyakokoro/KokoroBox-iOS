# KokoroBox Privacy Policy

**Last updated: September 8, 2026**

KokoroBox is an open-source sing-box client for iOS, iPadOS, and macOS. This policy describes how the KokoroBox client handles data. It applies to the client published from this repository, not to independent proxy, subscription, identity, or rule-provider services that you choose to use.

## Summary

KokoroBox does not include advertising, behavioural analytics, or third-party tracking SDKs. It does not sell personal data. Most app data stays on your device. Some features necessarily send data to the servers or services involved in the action you choose, such as a subscription provider, a proxy server, Kokoro, or a public-IP lookup service.

## Data stored on your device

KokoroBox stores the following data locally to provide its features:

- Profiles and their configuration, including remote subscription URLs, proxy server addresses, and any credentials contained in a configuration.
- App settings, profile update preferences, routing overrides, and optional custom User-Agent values.
- Connection and service logs, which can contain network metadata such as domains, IP addresses, ports, and error messages.
- Locally generated crash, out-of-memory, power, and hang reports. These may include diagnostic details and, when the relevant export option is selected, a configuration or log snapshot.
- Kokoro access and refresh tokens in the platform Keychain. The app keeps pending OAuth state and PKCE verifier data only in memory during sign-in.

You can remove local profiles, sign out of Kokoro, clear reports and logs, or uninstall the app to remove applicable local data. Operating-system backups, iCloud, or files you have exported are controlled separately by you and Apple.

## Data sent for app functionality

The app sends data only when needed for a feature you enable or request.

| Feature | Recipient | Data involved |
| --- | --- | --- |
| Remote profile download and update | The URL configured in the profile | The request, its network metadata, and the profile's configured User-Agent. A subscription URL may itself contain a credential. |
| VPN/proxy service | The proxy servers, DNS resolvers, rule-set providers, and destinations selected by your active configuration | Network traffic and metadata required by that configuration. These parties operate under their own privacy practices. |
| Kokoro sign-in, subscription, and Custom Rules | `https://amamiyakoko.ro/api` and the system-browser identity flow | OAuth authorisation data, Kokoro session tokens, account/subscription data, configuration choices, and Custom Rules you submit. The client does not send an osu! user ID or `proxy_uuid` as a client-selected identity field. |
| Public IP tool | `https://api.ip.sb/ip` | Your network IP address and ordinary request metadata necessary to answer the request. This occurs only when you open or refresh the Public IP tool. |
| Optional update checks and downloads | GitHub and the configured release/download source | Version information, ordinary request metadata, and any GitHub token you explicitly configure for update checks. |

KokoroBox does not log Kokoro access tokens, refresh tokens, OAuth codes, PKCE verifiers, complete Authorization headers, `proxy_uuid` values, or complete external subscription URLs in its app logs, analytics, or generated crash reports.

## Permissions

- **VPN / Network Extension:** Required to create and operate a device VPN tunnel. Traffic handling follows the profile you activate.
- **Location and Wi-Fi information (iOS/iPadOS):** If you grant location access, KokoroBox reads the current Wi-Fi SSID and BSSID to support Wi-Fi routing rules and the Network Interfaces diagnostic screen. It does not request location coordinates or use this permission for advertising or tracking. Wi-Fi details may be unavailable when permission is denied, the device is not connected to Wi-Fi, or iOS does not provide them.
- **Camera:** Used only when you choose to scan a QR code to import a profile. Camera images are processed for the scan and are not uploaded or retained by KokoroBox.
- **Local network:** Used for features that communicate with services on your local network, when you use them.

You can change permissions in system Settings at any time. Denying a permission may make its related feature unavailable.

## iCloud and sharing

If you choose an iCloud-backed profile or enable iCloud document storage, Apple may sync the related profile files through your iCloud account. KokoroBox does not control Apple's handling of iCloud data.

Crash reports, logs, and profiles are not automatically sent to the developer. When you explicitly export, share, or upload a report or profile, you choose the destination and are responsible for reviewing it first. Such files can contain sensitive configuration and network information.

## Data retention and security

Kokoro tokens are stored in the platform Keychain using device-only accessibility. Profile files, preferences, logs, and diagnostic reports remain on device storage until they are replaced, cleared, deleted, or removed with the app. Remote services retain data under their own policies.

No method of transmission or storage is completely secure. Avoid sharing subscription URLs, credentials, tokens, logs, or diagnostic reports unless you understand their contents and trust the recipient.

## Children

KokoroBox is not directed to children. Do not use it where doing so would violate a law, service rule, or age requirement that applies to you.

## Changes and contact

This policy may change when KokoroBox's data practices change. The current version is maintained in this repository. For questions or reports about the client, open an issue at [amamiyakokoro/KokoroBox-iOS](https://github.com/amamiyakokoro/KokoroBox-iOS/issues).

This policy is an informational description of the client and is not legal advice.
