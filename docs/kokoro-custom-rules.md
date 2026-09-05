# Kokoro Custom Rules (Apple client)

KokoroBox manages the signed-in user's server-side `default` rule set with the existing Kokoro App Bearer session. This is the only rule set applied as the default override when Kokoro generates a configuration. The client never sends a user ID, `proxy_uuid`, or management secret. Rules can contain private domains and process names, so request bodies, complete responses, and payloads must not be logged or attached to diagnostics.

## Client flow

The Custom Rules screen is available from **Settings → Kokoro Settings** on iOS, iPadOS, and macOS. Kokoro Settings owns account status, subscription usage, sign-in, and sign-out; the subscription creation screen only contains profile-generation options. If no Kokoro session exists, Kokoro Settings starts the existing system-browser PKCE login flow before loading data. The Custom Rules editor loads these resources together:

- `GET /app/custom-rules` to locate the case-insensitive `default` set and read its ordered rules, ID, and revision.
- `GET /app/custom-rules/options` for currently supported rule types, targets, domain providers, and limits.

The screen opens the `default` rules directly without a rule-set selection layer. Other sets returned by the API are ignored, and the client does not expose create, rename, or delete operations. If `default` is absent, the editor remains unavailable and offers a reload action.

The editor preserves the server's array order. Type, target, provider, and limit choices come from `/options`; regional targets and provider names are not compiled into the app. Before saving, the client refreshes options and validates the complete local draft. Saving sends one `PUT /app/custom-rules/sets/{default_set_id}/rules` with `expected_revision` and the complete ordered array. An empty array clears the default rules. A successful response replaces the local set and revision in full.

When a saved Kokoro session exists, the app preloads account, subscription-option, rule-state, and rule-option resources after launch and when returning to the foreground. A shared single-flight store keeps successful values in memory for five minutes, so opening Kokoro Settings, subscription creation, or Custom Rules reuses the in-progress request or fresh value. Nothing is persisted outside the existing Keychain credentials. Login, logout, and rule mutations invalidate the relevant cache before later reads.

## Conflict and unknown-result handling

A `409` never causes an automatic retry. The client first reloads the current remote set and asks the user to choose one of the following before saving again:

- Reapply the local draft on top of the newly loaded revision.
- Merge remote and locally unique rules, then review the result.
- Discard the local draft and use the remote version.

The merge keeps remote order, appends locally unique rules, and keeps a single `MATCH` at the end. It is only a draft; the user must review and explicitly save it.

When a rule replacement times out, the client reads `default` before deciding what happened. If the server content exactly matches the submitted ordered rules, the operation is treated as successful. Otherwise it enters the same conflict flow and does not blindly resend an old revision.

The existing session layer refreshes once after the first protected-request `401` and replays that request once. A `404` reloads/removes stale local state, `422` refreshes options before presenting the validation error, and `429` exposes a safe retry delay parsed from `Retry-After` without retrying a mutation automatically.

## Validation

Client validation mirrors the server contract without echoing payloads into errors:

- Non-`MATCH` rules require payloads; payload and target limits are enforced.
- Payloads and targets reject surrounding whitespace, commas, and control characters.
- `RULE-SET` accepts only providers whose current behavior is `domain`.
- A set can contain one `MATCH`, only at the end, and its target cannot be `REJECT`.

Server validation remains authoritative. Unknown response fields are ignored.

## Verification

Run `swift test` to test production model decoding, case-insensitive `default` selection when other sets are present, ordered rules, the exact replacement request, explicit `null` MATCH payloads, dynamic options validation, structured `409` revisions, `Retry-After`, unknown-result content comparison, preload single-flight behavior, cache invalidation, and the signed-out preload guard. The package also reruns all existing OAuth and refresh tests.

Unsigned iOS Simulator and macOS arm64 builds verify that the shared SwiftUI editor compiles on both platforms. Before release, a signed-device/live-backend pass must still verify real account data, website synchronization, target/provider changes, concurrent website edits, rate limiting, and a deliberately interrupted save. Local tests do not prove those external behaviors.
