---
name: asc-app-create-ui
description: Create an App Store Connect app using pre-cached Apple ID session from Blitz
---

Create an App Store Connect app using the `asc` CLI. The user's Apple ID session has already been captured by Blitz and bridged into the ASC CLI keychain, so **no password or 2FA is needed**.

Extract from the conversation context:
- `bundleId` — the bundle identifier (e.g. `com.blitz.myapp`)
- `sku` — the SKU string
- `appleId` — the Apple ID email (may be provided; if missing, ask the user)

## Steps

1. **Ask the user** what primary language the app should use. Common choices: `en-US` (English US), `en-GB` (English UK), `ja` (Japanese), `zh-Hans` (Simplified Chinese), `ko` (Korean), `fr-FR` (French), `de-DE` (German).

2. **Derive the app name** from the bundle ID: take the last component after the final `.`, capitalize the first letter.

3. **Run the create command** — auth is pre-cached, no prompts expected:

```bash
asc apps create \
  --apple-id "<appleId>" \
  --bundle-id "<bundleId>" \
  --sku "<sku>" \
  --primary-locale "<locale>" \
  --name "<appName>"
```

4. Report the App ID and store URL back to the user on success.

5. If the command fails with an auth error, tell the user to re-authenticate through Blitz (Release > Overview > "Automatically create using Claude Code") and try again.