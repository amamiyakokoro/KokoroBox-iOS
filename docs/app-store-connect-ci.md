# App Store Connect CI

The `iOS App Store Connect` GitHub Actions workflow builds the pinned sing-box core, runs the Swift tests, archives and cloud-signs `KokoroBoxI`, and either exports a signed IPA or uploads it to App Store Connect.

The workflow is manual by design. It never runs for pull requests or ordinary pushes, and upload is disabled unless the operator explicitly enables it.

## 1. Apple setup

An Account Holder or Admin must:

1. Accept all current Apple Developer and App Store Connect agreements.
2. Confirm that the App Store Connect app record for `com.amamiyakokoro.box` exists.
3. Confirm that the main app and every embedded extension App ID has the capabilities required by the project, including the App Group and Network Extension entitlements.
4. In **Users and Access → Integrations → App Store Connect API**, create a Team API key with the **Admin** role. Cloud-managed app distribution is granted to Account Holder and Admin roles by default; a Developer-role Team key cannot be granted that additional user permission after the key is created.
5. Download the `.p8` private key immediately and record its Key ID and Issuer ID. Apple only provides the private-key download once.

Use an Admin-role Team key for this unattended workflow. Key access levels cannot be edited; replace and revoke an unsuitable key. Keep the `.p8` private.

## 2. GitHub setup

In the repository, open **Settings → Environments** and create an environment named exactly:

```text
app-store-connect
```

Add a required reviewer and restrict deployment branches to `dev` if those controls are available. Then add these environment secrets:

| Secret | Value |
| --- | --- |
| `ASC_KEY_ID` | App Store Connect API Key ID |
| `ASC_ISSUER_ID` | App Store Connect Issuer ID |
| `ASC_PRIVATE_KEY` | Complete raw contents of the downloaded `.p8` file |

Use the raw multiline `.p8` content, not Base64.

## 3. First archive validation

Open **Actions → iOS App Store Connect → Run workflow** and select `dev`.

1. Enter an unused positive integer for `build_number`.
2. Leave **Upload the signed archive to App Store Connect** disabled.
3. Approve the protected environment deployment when prompted.

The workflow exports a signed IPA and keeps it as a workflow artifact for seven days. Inspect the archive/export logs and signing identities before enabling upload.

## 4. Upload

Run the workflow again with an unused build number and enable **Upload the signed archive to App Store Connect**. A successful workflow means Apple accepted the upload, not that processing or review is complete.

After the workflow finishes, check App Store Connect for processing status, export-compliance questions, TestFlight group assignment, and any Apple validation messages. External TestFlight and App Store distribution can still require review.

Never reuse a build number that App Store Connect has already accepted. If an upload times out and its result is unknown, check App Store Connect before retrying with the same number.

## Pinned toolchain inputs

- Runner: `xcode-27`
- Core source: `SagerNet/sing-box` tag `v1.15.0-alpha.8`
- Gomobile: `github.com/sagernet/gomobile` `v0.1.12`
- Client marketing version: `1.14.4`

Update these values together when the client or core version changes.
