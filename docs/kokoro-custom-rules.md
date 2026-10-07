# Kokoro Custom Rules (Apple client)

KokoroBox manages the signed-in user's server-side `default` rule set with the existing Bearer session. It is the only default override used for generated configurations. Never send a user ID, `proxy_uuid`, or management secret, or log rule payloads and responses.

## Client flow

The Custom Rules screen is available from **Settings → Kokoro Settings** on iOS, iPadOS, and macOS. Kokoro Settings owns account status, subscription usage, sign-in, and sign-out; the subscription creation screen only contains profile-generation options. If no Kokoro session exists, Kokoro Settings starts the existing system-browser PKCE login flow before loading data. The Custom Rules editor loads these resources together:

- `GET /app/custom-rules` to locate the case-insensitive `default` set and read its ordered rules, ID, and revision.
- `GET /app/custom-rules/options` for currently supported rule types, targets, domain providers, and limits.

The screen opens the `default` rules directly without a rule-set selection layer. Other sets returned by the API are ignored, and the client does not expose create, rename, or delete operations. If `default` is absent, the editor remains unavailable and offers a reload action.

The editor preserves the server's array order. Type, target, provider, and limit choices come from `/options`; regional targets and provider names are not compiled into the app. Before saving, the client refreshes options and validates the complete local draft. Saving sends one `PUT /app/custom-rules/sets/{default_set_id}/rules` with `expected_revision` and the complete ordered array. An empty array clears the default rules. A successful response replaces the local set and revision in full.

With a saved session, the app preloads account, subscription, and rule data at launch and foreground entry. A shared single-flight cache reuses successful values for five minutes; login, logout, and rule changes invalidate relevant entries. Only credentials persist in Keychain.

## Create a rule from a connection

On iOS, iPadOS, and macOS, select **Create Routing Rule** in a connection's context menu or details screen. Active and closed connections use the same flow. A single rule editor opens directly, loads the account's default set and options, and prefills the connection rule. If needed, it offers Kokoro sign-in in the same screen. The Custom Rules list is not an intermediate destination.

- A recorded domain suggests `DOMAIN-SUFFIX` first using its registrable domain (for example, `api.example.com` → `example.com`, `api.example.co.uk` → `example.co.uk`). `DOMAIN` keeps the full hostname. The bundled [Public Suffix List](https://publicsuffix.org/list/) includes ICANN and private suffixes, wildcard rules, exceptions, and internationalized domains; `cdn.user.github.io` therefore becomes `user.github.io`. Bare public suffixes and single-label hosts only offer `DOMAIN`.
- A destination IPv4 address suggests `IP-CIDR` with `/32`; IPv6 suggests `IP-CIDR6` with `/128`. Endpoint ports and IPv6 brackets are removed.
- Only currently supported rule types and valid values are offered. A matching routing group from the connection chain is preferred as the target, followed by the outbound, `DIRECT`, or the first available server target. The user can change the target before adding.

**Save** places the rule at the beginning of the submitted set so it takes precedence over existing rules; an identical rule is moved to the beginning instead of duplicated. Existing rules keep their relative order, including a final `MATCH`. Count limits and full-set validation apply. If the connection has no supported domain/IP suggestion, the screen explains this; manual rules can still be managed from Kokoro Settings.

Tap **Save** once to submit the rule through the existing revision-aware replacement. The editor closes only after a confirmed save. Errors preserve the input. On a conflict, it stays on the same screen and asks the user to review the rule and save again; that explicit retry prepends only the edited connection rule to the latest remote set, preserving other changes. Timeout reconciliation checks whether the submitted set was saved before closing. After a confirmed save (including a reconciled timeout), the client immediately updates all local remote profiles using the authenticated Kokoro configuration endpoint, even if periodic auto-update is disabled or not yet due. Updates validate the downloaded configuration before writing and reload the selected connected profile when its content changes. A forced refresh waits for an older in-flight download, then fetches again so it cannot reuse a configuration fetched before the rule save. Other subscription providers are not updated. If any update fails, the client explains that the rules are already saved and offers **Retry Subscription Update**; retrying only downloads profiles and does not submit rules again. The connection editor stays open on update failure and closes after a successful retry or when cancelled. The full Custom Rules screen uses the same update flow after any saved edit.

The list is stored in `Library/Network/Resources/public_suffix_list.txt`, with its upstream version, commit, and MPL 2.0 notice preserved. Refresh it from `https://publicsuffix.org/list/public_suffix_list.dat` during maintenance; rule creation does not download data. If the resource is unavailable, the client falls back to the exact `DOMAIN` suggestion.

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

Run `swift test` for decoding, `default` selection, ordering, replacement requests, dynamic validation, connection suggestions (domain, IPv4, IPv6, and supported options), priority insertion, duplicate handling, conflicts, unknown outcomes, and cache behavior. The suite also covers OAuth and refresh.

Unsigned iOS Simulator and macOS arm64 builds verify that the shared SwiftUI editor compiles on both platforms. Before release, a signed-device/live-backend pass must still verify real account data, website synchronization, target/provider changes, concurrent website edits, rate limiting, and a deliberately interrupted save. Local tests do not prove those external behaviors.
