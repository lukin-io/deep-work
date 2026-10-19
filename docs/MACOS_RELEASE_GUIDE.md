# First macOS release: 10 things to get right

Checked against Apple's guidance on **October 18–19, 2026** and the current Deep Work sources. This guide covers our native **Apple Silicon, macOS 15+ app distributed through GitHub**. It distinguishes the production Developer ID distribution path, conditional Mac App Store requirements, and recommended engineering/Human Interface Guidelines practices. It is not an exhaustive statement of Apple's agreements or every feature-specific requirement. Implementation progress remains in [IMPLEMENTATION_CHECKLIST.md](../IMPLEMENTATION_CHECKLIST.md).

The published `v0.1.0-preview.2` and earlier preview are **ad hoc signed and unnotarized**. Passing compilation, tests, signature-integrity checks, or GitHub publication does not establish Developer ID identity, notarization, or Gatekeeper acceptance. Current release evidence is in [VERIFICATION.md](VERIFICATION.md#preview-2--stages-16--october-19-2026).

## 1. Obtain the right signing identity and protect its private key

**Production direct distribution.** Use an Apple Developer Program team and a **Developer ID Application** signing identity for the `.app`. A downloadable `.cer` alone cannot sign: the corresponding private key is also required. A Developer ID Installer identity is relevant if we later ship a signed installer package; it does not replace the app identity. Keep exported identities, passwords, and notarization credentials in secure secret storage, never Git, release assets, or logs. [Apple: Developer ID](https://developer.apple.com/developer-id/), [signing identities and private keys](https://developer.apple.com/documentation/xcode/sharing-your-teams-signing-certificates).

**Deep Work:** the last local identity check found no valid signing identities. That does **not** prevent CI signing once an authorized identity and notarization credentials are securely provided to an isolated release job. The current [workflow](../.github/workflows/release.yml) only uses GitHub credentials; it has no Apple signing integration. No account enrollment or certificate provisioning has been performed by this guide.

## 2. Sign the final Release app with Hardened Runtime and a secure timestamp

**Production direct distribution.** Developer ID signing, **Hardened Runtime**, and a secure signing timestamp are prerequisites for notarizing this new app. Do not ship the development `get-task-allow` entitlement. Grant only entitlements actually needed, and sign any nested executable code appropriately before signing the outer app. Build and assemble resources before final signing; later changes can invalidate the signature. [Apple: distribution signing](https://developer.apple.com/documentation/xcode/creating-distribution-signed-code-for-the-mac), [notarization prerequisites](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution).

**Deep Work:** [package-release.sh](../scripts/package-release.sh) currently uses `codesign --sign -`, an ad hoc signature. Production identity, runtime, timestamp, and entitlement verification must be implemented and tested together. A successful `codesign --verify` currently proves integrity, not trusted publisher identity.

## 3. Notarize, staple, then test the actual download

**Production direct distribution.** Submit the signed artifact with `notarytool`, wait for **Accepted**, and inspect the notary log. Notarization is an automated security check, not App Review. Staple the ticket to the app for offline verification. A ZIP itself cannot be stapled: staple the contained app, then create the final ZIP and its checksums. Test that downloaded, quarantined copy through Gatekeeper on a clean Mac/user environment; local build launch is insufficient. [Apple: custom notarization workflow](https://developer.apple.com/documentation/security/customizing-the-notarization-workflow), [Gatekeeper assessment](https://developer.apple.com/library/archive/technotes/tn2206/).

**Deep Work:** notarization, stapling and Gatekeeper acceptance are not implemented. The current pipeline intentionally rejects stable tags. Its draft/upload/download verification is useful distribution evidence, but does not replace these Apple checks. Never instruct users to disable Gatekeeper or strip quarantine to make installation succeed.

## 4. Keep identity, versions, and supported Macs consistent

**Distribution correctness.** Keep a stable bundle identifier, advance the app version for new versions, and increase the Mac build number across versions. Align deployment target, executable architecture, bundle metadata, and release notes. The SDK used to compile is separate from the oldest OS supported at runtime. [Apple: preparing an app for distribution](https://developer.apple.com/documentation/xcode/preparing-your-app-for-distribution), [minimum macOS metadata](https://developer.apple.com/documentation/bundleresources/information-property-list/lsminimumsystemversion).

**Deep Work:** [Info.plist](../DeepWork/Resources/Info.plist) uses `app.deepwork.mac`; [Package.swift](../Package.swift), the Xcode project and release verifier enforce **arm64, macOS 15+**. Preserve the published identity unless a deliberate migration is planned. Release tags, numeric bundle version and build metadata must agree; fixes get new tags/assets. Intel and pre-15 macOS are outside support, not missing release targets.

## 5. Treat an app upgrade as a data-preservation operation

**Platform recommendation and product requirement.** Store app-owned durable data in Foundation's user-domain Application Support location, outside the app bundle. Changing the bundle ID, sandboxing, or storage layout can change where data is found. Test old-version data, migration failure, interrupted writes and downgrade refusal before shipping schema changes. [Apple: Application Support directories](https://developer.apple.com/library/archive/documentation/FileManagement/Conceptual/FileSystemProgrammingGuide/MacOSXDirectories/MacOSXDirectories.html).

**Deep Work:** [LocalStore.swift](../DeepWork/Data/LocalStore.swift) uses `Application Support/app.deepwork.mac/DeepWork.sqlite`, transactions and version validation; [store tests](../DeepWorkTests/Core/StoreTests.swift) cover migration/data preservation. Before a manual backup, fully quit successfully and copy the **entire data directory**; copying only a live SQLite main file can omit WAL data. A future in-app live backup needs a coherent SQLite backup operation. CSV is a report, not a restorable backup. Never include journals or feedback in downloadable app assets.

## 6. Sandbox and permissions depend on the distribution route and feature

**Conditional requirement.** App Sandbox is required for Mac App Store submission; it is optional for Developer ID distribution through GitHub. Hardened Runtime is a different protection. If we adopt sandboxing, test the container migration and add only needed entitlements. Protected resources can also require user consent and purpose strings; an entitlement alone does not grant consent. [Apple: App Sandbox](https://developer.apple.com/documentation/xcode/configuring-the-macos-app-sandbox).

**Deep Work:** the current app is not sandboxed and has no need for camera, microphone or broad Accessibility-control permissions. Native accessible UI does not require permission to control other apps. CSV export uses the native save panel; a sandboxed version would need the appropriate user-selected-file access. Do not turn on unrelated permissions merely because a tutorial includes them.

## 7. Audit privacy accurately; a manifest is not a universal Mac release checkbox

**Conditional requirements.** Apple's current required-reason API article names iOS, iPadOS, tvOS, visionOS and watchOS; it does not establish a blanket manifest requirement for this native GitHub macOS app. App Store submission has separate privacy disclosures and a privacy-policy URL requirement. Listed third-party SDKs can trigger manifest/signature requirements. Recheck the actual platform, distribution route, SDKs and API use when these change. [Apple: required-reason APIs](https://developer.apple.com/documentation/bundleresources/describing-use-of-required-reason-api), [SDK requirements](https://developer.apple.com/support/third-party-SDK-requirements/), [App Store privacy](https://developer.apple.com/help/app-store-connect/manage-app-information/manage-app-privacy/).

**Deep Work:** no third-party packages or privacy manifest are currently bundled. Journals and explicitly saved feedback remain local; feedback is never sent. Optional Slack authorization exchanges tokens and profile status with Slack after consent, using only profile read/write scopes and device-local Keychain credentials. See [Slack setup and data behavior](SLACK_SETUP.md). The storage code uses `lstat`, `fstat` and file attributes for existence/type/permissions, which deserve specific review if a future applicable API audit is needed. Do not invent an approved reason or claim an audit is complete from a text search. Keep Slack disclosures and secure credential storage aligned with its actual profile-only behavior; reassess before adding analytics or crash-reporting SDKs.

## 8. Follow the Human Interface Guidelines for real Mac behavior

**Recommended platform design and approved product behavior.** Use native menus, standard shortcuts, predictable focus, window resizing and full-screen behavior. Preserve macOS distinctions between closing a window, hiding an app and quitting it. Keep the menu-bar item useful when the main window is hidden. These are user-experience requirements, not substitutes for signing. [Apple: designing for macOS](https://developer.apple.com/design/human-interface-guidelines/designing-for-macos).

**Deep Work:** [AppDelegate](../DeepWork/App/DeepWorkApp.swift), [WindowController](../DeepWork/App/WindowController.swift) and [MenuBarController](../DeepWork/App/MenuBarController.swift) implement the approved contract: close/⌘W hides while timing continues; ⌘Q pauses, saves and quits; menu click reopens Focus. Keep Focus, Journal and Settings and the approved visual design. Full interaction/appearance acceptance remains separate from target/action integration tests.

Stage 5 adds **Settings… / ⌘,** and **Redo / ⇧⌘Z**, with native menu and responder-chain tests. Compiled keyboard routing is recorded separately in verification. Preserve the approved Settings tab: its placement is an intentional product choice, while a standard Settings command can open that existing tab. Apple normally describes a separate settings window; changing this product's window structure requires an explicit design decision. [Apple: settings](https://developer.apple.com/design/human-interface-guidelines/settings), [undo and redo](https://developer.apple.com/design/human-interface-guidelines/undo-and-redo).

## 9. Make accessibility part of acceptance, not a final cosmetic pass

**Recommended platform design and project requirement.** Test keyboard-only use and VoiceOver, meaningful labels/values, focus order, validation announcements, contrast, light/dark appearance and Reduce Motion. Avoid color-only meaning and overriding system shortcuts. Native controls help, but do not prove the complete workflow is accessible. [Apple: accessibility HIG](https://developer.apple.com/design/human-interface-guidelines/accessibility).

**Deep Work:** native keyboard and accessibility labels have regression coverage under [DeepWorkTests/App](../DeepWorkTests/App). The [verification record](VERIFICATION.md) records Stage 6 compiled keyboard and light/dark/narrow layout checks. Full VoiceOver reception, system Reduce Motion propagation and a physical menu-bar-item click remain separate acceptance gaps. Preserve these distinctions instead of promoting a CI screenshot or successful AX lookup to complete accessibility acceptance.

## 10. Budget background work and respect login-service consent

**Recommended efficiency; conditional service requirements.** Measure CPU/wakeups while visible, hidden, paused and idle. Count elapsed time independently of refresh frequency, because background scheduling can be delayed. Do not keep the Mac awake simply to animate a countdown. For Launch at Login, use `SMAppService` and reflect its actual status, including approval required or consent revoked; a saved Boolean is not registration success. [Apple: efficient timers](https://developer.apple.com/library/archive/documentation/Performance/Conceptual/power_efficiency_guidelines_osx/Timers.html), [Service Management](https://developer.apple.com/documentation/servicemanagement/smappservice), [approval status](https://developer.apple.com/documentation/servicemanagement/smappservice/status-swift.enum/requiresapproval).

**Deep Work:** [TimerClock](../DeepWork/App/TimerClock.swift) uses continuous elapsed time; [AppModel](../DeepWork/App/AppModel.swift) refreshes every 250 ms only while running and checkpoints about every five seconds. These policies need real energy/App Nap and physical sleep/wake observation, not only injected-clock tests. [LoginItemService](../DeepWork/App/LoginItemService.swift) now registers the main app and reports actual status; [SettingsView](../DeepWork/Features/Settings/SettingsView.swift) exposes approval, revocation and errors. Tests isolate native operations from personal login items. Actual login-cycle acceptance remains separate from a successful registration call or injected test.

Mac App Store distribution would be a separate project decision, adding App Store Connect metadata, App Review and its applicable privacy/capability requirements. Neither that route nor new feature scope is implied by publishing a GitHub release.
