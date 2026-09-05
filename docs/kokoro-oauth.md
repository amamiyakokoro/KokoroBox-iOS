# Kokoro OAuth integration (Apple client)

This client uses the public API base `https://amamiyakoko.ro/api` and the exact callback URI `kokoro://oauth/callback`. All code grants require PKCE **S256**. There is no plain, missing-verifier, platform-specific URI, Universal Link, App Link, or loopback fallback. Client code must not contain `API_SECRET`, `APP_AUTH_SECRET`, or `OSU_CLIENT_SECRET`.

## Login transaction

`KokoroWebAuthenticator.shared` owns one pending login per running application, shared across windows. It retains the lock through the token exchange. `KokoroLoginTransaction` owns `{state, code_verifier, redirect_uri, expiry}` privately in memory; nothing is written to preferences, files, logs, or Keychain for pending login.

Each login makes two separate `SecRandomCopyBytes` calls, each for 32 bytes, then Base64URL encodes each result without padding. The verifier is 43 ASCII characters. Its challenge is:

```text
BASE64URL_NO_PADDING(SHA256(ASCII(code_verifier)))
```

The hash input is the verifier string, not its decoded random bytes or a hexadecimal digest. A URL builder constructs `/app/auth/login` with exactly these parameters:

| Parameter | Value |
| --- | --- |
| `redirect_uri` | `kokoro://oauth/callback` |
| `state` | This login's independent random state |
| `code_challenge` | This login's S256 challenge |
| `code_challenge_method` | `S256` |

The URL is opened by `ASWebAuthenticationSession`. Pending logins expire after five minutes; a timer cancels the browser session and clears the transaction. Dismissing the subscription screen cancels its login task. Browser cancellation, startup failure, callback failure, and success also clear pending state. Each browser completion is tied to an internal attempt ID so a delayed completion cannot finish a newer login.

## Callback delivery and validation

iOS/iPadOS, macOS, and macOS standalone register `kokoro` in their `Info.plist`. The normal path is the authentication session's completion handler. The existing SwiftUI `onOpenURL` paths also route Kokoro URLs to the same coordinator before profile import or unknown-URL error handling.

The parser requires the canonical scheme `kokoro`, host `oauth`, and path `/callback`; it rejects userinfo, ports (including an empty port), fragments (including an empty fragment), encoded/noncanonical authority or path, and duplicate security parameters, including duplicates with a missing value. It requires a constant-time state match against a live pending login and exactly one nonempty `code` or `error`, never both. Arbitrary error text is not forwarded to alerts.

The transaction is consumed before validation/exchange. Missing, wrong, expired or replayed state cannot exchange a code. An invalid callback ends that attempt, so retrying requires a new login. Callback URLs and authorization codes are never forwarded to another app.

Cold launch intentionally does **not** recover pending login. A process restart loses its in-memory verifier; the URL handler discards the callback and prompts the user to sign in again. It never exchanges a code without the saved verifier.

On macOS both app variants set `LSMultipleInstancesProhibited`, and the browser flow stays with the originating OS authentication session. No custom cross-process code forwarding is used. A manually launched process with no pending login rejects callbacks. Multiple different Kokoro clients sharing the scheme are still subject to the backend's single-client-per-device assumption.

See Apple's [ASWebAuthenticationSession documentation](https://developer.apple.com/documentation/authenticationservices/aswebauthenticationsession) and [Launch Services keys](https://developer.apple.com/library/archive/documentation/General/Reference/InfoPlistKeyReference/Articles/LaunchServicesKeys.html). These describe the intended OS behavior; compiling and testing the coordinator does not verify OS delivery on a device.

## Token exchange and refresh

Only a validated callback produces a `KokoroAuthorization` value. The session sends one JSON POST to `/app/auth/token`:

```json
{
  "grant_type": "authorization_code",
  "code": "<one-time callback code>",
  "redirect_uri": "kokoro://oauth/callback",
  "code_verifier": "<original verifier from this login>"
}
```

HTTP 400 (including expired/used codes or mismatched/missing verifier) and 422 (invalid verifier) are terminal. No retry, PKCE downgrade, or legacy exchange follows. The server's authorization code is valid for five minutes and can be used once. Lost verifiers require a new login.

`access_token`, `refresh_token`, `expires_in`, and `refresh_expires_in` retain their existing handling. Both tokens and their expiry dates are encoded into one Keychain item (`kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`), using update/add of the complete item.

Refresh sends only:

```json
{"grant_type":"refresh_token","refresh_token":"<current refresh token>"}
```

Concurrent refresh requests share one task. That task persists the rotated credential pair before releasing any waiter; a storage failure fails waiting requests. An access-protected request can refresh on its first 401 and replay once. Refresh 401 clears credentials. Logout invalidates in-flight refresh/exchange work so it cannot restore the revoked session.

## Sensitive data handling

- OAuth uses a dedicated ephemeral URLSession with no disk cache, cookie storage, or credential storage. HTTP redirects remain disabled.
- Token response errors expose only an HTTP status, not backend detail that might echo input. Network errors are mapped to fixed errors without URLSession's failing-URL userInfo.
- Browser errors and callback error fields are mapped to fixed local messages. Kokoro callbacks cannot reach the generic unknown-URL alert that includes a URL.
- The authentication path has no HTTP body logging, analytics events, or crash-report breadcrumbs. Pending secrets and request bodies are not attached to crash reports. Existing native/Go crash collection does not receive these values through this path; OS crash artifacts and third-party diagnostic capture still need review during device validation.
- Never paste real callback URLs, codes, verifiers, tokens, or subscription credentials into test output or reports. All unit-test values are synthetic; the RFC vector is test-only.

## Verification

Run `swift test` from the repository root. The package compiles the production OAuth, token session, and browser coordinator with HTTP, storage and browser test doubles. It does not require Libbox, real Keychain credentials, an osu! account, or the live backend.

Coverage includes the RFC 7636 vector, verifier format and random independence, login URL and token JSON, correct/missing/wrong/duplicate/expired state, URI forgery, denial, replay, cancellation, timeout, cold-start rejection, lost verifier, concurrent attempts, late callbacks, HTTP 400/422, single-flight refresh, persistence failure, refresh 401, and logout during refresh.

Build the `KokoroBoxI`, `KokoroBoxM`, and `SFM.System` schemes separately. The latter two produce the same app filename, and simultaneous builds in one DerivedData directory can conflict. tvOS has no Kokoro browser sign-in screen.

Before release, manually verify on a signed iPhone/iPad and both macOS variants:

1. An allowed osu! account completes browser login against the enforced-S256 backend and returns to the originating app/window.
2. Browser cancel, dismissing the subscription screen, denial, and timeout allow a fresh login.
3. Warm callbacks route correctly; force-quit/cold-launch callbacks show the re-login message without exchanging the old code.
4. Duplicate/forged callbacks and late callbacks cannot create a session or interfere with a completed exchange.
5. macOS Launch Services reuses the running app; no separate process receives a usable code.
6. Keychain rotation persists across relaunch, refresh works with real backend expiry, and diagnostic exports contain no authentication secrets.

Mocked callback and Keychain tests are not evidence of OS callback delivery, real Keychain entitlement behavior, or a live end-to-end OAuth exchange.

### Local validation, 2026-09-05

- `swift test`: 21 tests passed, zero failures.
- `KokoroBoxI`: Debug build for generic iOS Simulator passed.
- `KokoroBoxM` and `SFM.System`: Debug builds for macOS arm64 passed.
- All three builds used `CODE_SIGNING_ALLOWED=NO`, pinned package resolution and `-skipPackagePluginValidation`. Existing concurrency, dependency and extension-version warnings remain.
- App plist validation and `git diff --check` passed.
- No signed-device callback, real-Keychain, or live osu!/Kokoro end-to-end test was performed. The manual checks above remain required.
