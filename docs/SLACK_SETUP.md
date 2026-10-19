# Slack setup

Deep Work uses one connected Slack user/workspace. It changes only your custom status, to **❌ Deep WORK, DND** during focus. It does not snooze Slack notifications, change presence, send messages or enable macOS Focus.

This source build has no Slack Client ID yet. The connection stays unavailable until configured. The owner chose to configure Slack after implementation; automated tests do not establish live authorization or workspace acceptance.

## Configure a Slack app

1. Create a dedicated app in [Slack's app settings](https://api.slack.com/apps), in a workspace where you can install it. Workspace administrator approval may be required.
2. Under **OAuth & Permissions**, enable **PKCE**. Slack treats this as a public desktop client; enabling PKCE is one-way. Prefer a dedicated new app instead of changing an unrelated existing integration.
3. Add this exact redirect URL: `app.deepwork.mac://slack/oauth`.
4. Add only these **User Token Scopes**: `users.profile:read` and `users.profile:write`. No bot scopes are needed.
5. Copy the public **Client ID** from Basic Information. Do not copy the Client Secret, signing secret or a user token into source, shell history, this chat or SQLite.

Slack documents public-client PKCE, custom callback URLs and secret-free token exchange in [Using PKCE](https://docs.slack.dev/authentication/using-pkce/). The app creates a random verifier and state for each browser authorization, checks the exact callback, and uses Apple's [ASWebAuthenticationSession](https://developer.apple.com/documentation/authenticationservices/aswebauthenticationsession).

## Build and connect

From the repository root, replace the example public ID with your app's ID:

```sh
/usr/libexec/PlistBuddy -c 'Set :DeepWorkSlackClientID 123456789.987654321' DeepWork/Resources/Info.plist
./scripts/test.sh
./scripts/build-app.sh
open ".build/Deep Work.app"
```

Quit an older app copy before opening the new build. The public ID may be committed when ready; it is configuration, not a credential. The same `Info.plist` is used by Xcode and release packaging. Do not edit an already signed app bundle. Normal release rules still require a clean committed revision on `main` and passing CI.

In **Focus → Connect Slack**, select the intended account and approve the two profile permissions. Cancelling changes no status. Connecting during a new or resumed focus cycle applies the focus status; a recovered paused cycle waits for Resume. Connecting in setup or break does not change status. The existing three tabs remain unchanged.

Credentials use one device-local Keychain item, separate from journals and SQLite. Access tokens rotate using their returned expiry; replacement access/refresh tokens are saved together before use. Slack's PKCE refresh tokens expire after 30 days, so reconnection can be required. See [token rotation](https://docs.slack.dev/authentication/using-token-rotation/). A locked/inaccessible Keychain or denied permission produces a visible error; it does not stop the timer.

If a rotated token cannot be saved, the app retains it in memory and retries the Keychain commit before further requests or Quit. A persistent failure keeps Quit cancellable; explicitly quitting without saving may require reconnection later.

## Status ownership and recovery

- Before setting focus status, Deep Work commits the previous text, emoji and expiration plus the intended status and account identity to SQLite. No tokens are stored there.
- Normal Pause keeps the focus status. Break, End session, Quit and Disconnect restore only when the remote status still exactly matches the app's status. Detected manual changes are kept. An already expired previous status is cleared instead of revived.
- Quit waits for accepted status work. A failed restoration offers Keep Open or the existing explicit Quit Without Saving option. The restoration receipt survives; reopening attempts recovery and leaves the timer paused. After a failed Quit, only choosing Keep Open reapplies the paused focus status.
- Focus status has no remote expiration so an indefinitely paused focus retains it. A crash or offline Quit can therefore leave it visible until recovery succeeds or you change it manually in Slack.
- Slack has no documented conditional profile-write API. Reading before restoration protects detected edits, but a manual change made between that read and the subsequent write can still race with it. See [profile get](https://docs.slack.dev/reference/methods/users.profile.get/) and [profile set](https://docs.slack.dev/reference/methods/users.profile.set/).
- **Retry** respects Slack's rate-limit delay. Failed operations never claim that a status was applied/restored. No timer tick polls Slack.
- **Disconnect** restores owned status before removing credentials from this Mac. It does not uninstall the workspace app or revoke its grant in Slack; use Slack's app settings for that. A failed disconnect retains credentials for retry.

## Required live acceptance after configuration

Use a disposable Slack account/workspace and temporary native data fixture. Verify authorization/cancel, focus → pause → resume → break, End, Quit/relaunch, expired previous status, manual status changes, denied permissions, offline restore/retry and disconnect. Confirm actual remote results in Slack; injected HTTP tests cannot replace these checks. Do not test against a colleague's account or a personal running focus session.

For Launch at Login, separately install the app at a stable Applications path, enable/disable the switch, check System Settings → General → Login Items, and verify both results through a deliberate logout/login. The implementation session does not log out the active Mac user.
