# Kokoro Custom Rules (Apple client)

KokoroBox manages the signed-in user's server-side rule sets with the existing Kokoro App Bearer session. The client never sends a user ID, `proxy_uuid`, or management secret. Rules can contain private domains and process names, so request bodies, complete responses, and payloads must not be logged or attached to diagnostics.

## Client flow

The Custom Rules screen is available directly from Settings on iOS, iPadOS, and macOS. If no Kokoro session exists, the screen starts the existing system-browser PKCE login flow before loading data. It loads these resources together:

- `GET /app/custom-rules` for ordered rule sets, rules, IDs, and revisions.
- `GET /app/custom-rules/options` for currently supported rule types, targets, domain providers, and limits.

The editor preserves the server's array order. Type, target, provider, and limit choices come from `/options`; regional targets and provider names are not compiled into the app. Before each mutation, the client refreshes options and validates the complete local draft.

Creating, renaming, and deleting use the server-provided set ID and current revision. The `default` set cannot be renamed or deleted. Saving rules sends one `PUT /app/custom-rules/sets/{set_id}/rules` with `expected_revision` and the complete ordered array. An empty array clears a set. A successful response replaces the local set and revision in full.

## Conflict and unknown-result handling

A `409` never causes an automatic retry. The client first reloads the current remote set and asks the user to choose one of the following before saving again:

- Reapply the local draft on top of the newly loaded revision.
- Merge remote and locally unique rules, then review the result.
- Discard the local draft and use the remote version.

The merge keeps remote order, appends locally unique rules, and keeps a single `MATCH` at the end. It is only a draft; the user must review and explicitly save it.

When a rule replacement times out, the client reads the set before deciding what happened. If the server content exactly matches the submitted ordered rules, the operation is treated as successful. Otherwise it enters the same conflict flow and does not blindly resend an old revision. Rename and delete timeouts are also checked with a read before another attempt.

The existing session layer refreshes once after the first protected-request `401` and replays that request once. A `404` reloads/removes stale local state, `422` refreshes options before presenting the validation error, and `429` exposes a safe retry delay parsed from `Retry-After` without retrying a mutation automatically.

## Validation

Client validation mirrors the server contract without echoing payloads into errors:

- Rule set names are trimmed and limited by server options.
- Non-`MATCH` rules require payloads; payload and target limits are enforced.
- Payloads and targets reject surrounding whitespace, commas, and control characters.
- `RULE-SET` accepts only providers whose current behavior is `domain`.
- A set can contain one `MATCH`, only at the end, and its target cannot be `REJECT`.

Server validation remains authoritative. Unknown response fields are ignored.

## Verification

Run `swift test` to test production model decoding, ordered rules, exact request paths/methods/bodies, explicit `null` MATCH payloads, dynamic options validation, structured `409` revisions, `Retry-After`, and unknown-result content comparison. The package also reruns all existing OAuth and refresh tests.

Unsigned iOS Simulator and macOS arm64 builds verify that the shared SwiftUI editor compiles on both platforms. Before release, a signed-device/live-backend pass must still verify real account data, website synchronization, target/provider changes, concurrent website edits, rate limiting, and a deliberately interrupted save. Local tests do not prove those external behaviors.
