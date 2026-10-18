# Stage 1 native verification

October 18, 2026. Progress and acceptance status are maintained only in [IMPLEMENTATION_CHECKLIST.md](../IMPLEMENTATION_CHECKLIST.md). These are observed results and reproducible use cases, not claims that later milestones are complete.

## Environment and commands

- macOS 27.0.1 (26A434), arm64; Apple Swift 6.4; Command Line Tools SDK.
- Production deployment floor: macOS 13. macOS 13 runtime and Intel hardware are unverified. The installed Swift Testing runtime targets macOS 14+.
- `./scripts/build-app.sh`: native SwiftUI/AppKit application compilation, local `.app` packaging, and ad hoc signing pass. Output: `.build/Deep Work.app`.
- `./scripts/test.sh`: **45 tests passed** after the final SQLite changes: 39 model/store/feedback tests and 6 app-state/AppKit tests. The core production module also compiles with complete Swift concurrency checking.
- `codesign --verify --strict ".build/Deep Work.app"`: pass for the locally packaged app.
- `plutil -lint DeepWork/Resources/Info.plist DeepWork.xcodeproj/project.pbxproj`: pass. Project source references, local package product references, and shared scheme targets were checked against files.
- All eight `reference/` files match the byte lengths and SHA-256 digests in `REFERENCE_MANIFEST.json`. No reference source was changed. JavaScript tests do not count as native evidence and were not used to accept this milestone.

Full Xcode build was attempted:

```sh
xcodebuild -project DeepWork.xcodeproj -scheme DeepWork \
  -configuration Debug -destination 'platform=macOS' build
```

It fails before compilation with:

```text
xcode-select: error: tool 'xcodebuild' requires Xcode, but active developer directory '/Library/Developer/CommandLineTools' is a command line tools instance
```

This is the exact local tooling blocker. The Xcode build and Xcode test runner remain unverified. The app was compiled and exercised natively through the installed Swift toolchain instead.

Standalone CLT does not contain XCTest, and its default Swift Testing invocation omitted the macro plugin lookup path. `scripts/test.sh` resolves the installed `libTestingMacros.dylib` through `xcrun` and passes it explicitly when present. CLT emits missing legacy framework/library-search-path warnings and a test-runtime minimum-version warning; these are toolchain warnings, not failed assertions. No claim is made that tests ran on macOS 13.

## Native test coverage

- Model tests: defaults, duration boundaries, UUID uniqueness, absolute timestamp validity, positive ordered/nonoverlapping segments, completed/partial/live rules, checkpoint consistency, civil dates, weekday/cutoff/shift validation.
- Feedback tests: explicit saved draft validation, UTF-16 lengths for emoji/composed text, ECMAScript trim rules, optional email grammar/limits, email error priority, unknown feedback type fallback.
- SQLite integration tests: actual per-session rows, round trips, configuration/schedule/checkpoint/settings preservation, domain isolation, serialized writes, transaction rollback, failed/locked storage, corruption and unsupported versions, private permissions, and one-time legacy migration with original data preserved.
- App-model tests: initial Journal/Week, shared-owner navigation, Repeat/report/schedule-draft/feedback retention, explicit draft versus unsaved edits on relaunch, visible failed-save status with in-memory edits retained, and independent corrupt settings while journal writes succeed.
- AppKit integration: real NSWindow show/hide and close delegate, minimize/deminimize state, zoom and restored frame, title, minimum dimensions, full-screen capability, preferred tab widths after deferred resizing, and native arrow/Home/End handling.

Test names include stable handoff IDs. Core tests are in `DeepWorkTests/Core`; app and window tests are in `DeepWorkTests/App`.

## Native UI acceptance and regression use cases

| Case | Reproduction and observed result |
| --- | --- |
| UI-01: initial/navigation | Launch compiled `.app`: title is Deep Work; Journal is selected, Week is selected, and the three tabs expose native accessibility selection. Click Focus, Journal, Settings: only the corresponding panel is shown with its reference width. |
| UI-02: panel/resize regression | Initially a tab click resized the window during `@Published`'s pre-assignment emission, leaving the preceding panel visible. Fix: deliver resize on `RunLoop.main`. Repeated mouse/keyboard transitions then showed the selected panel. AppKit regression test also verifies deferred Settings/Focus widths and retained edits. |
| UI-03: keyboard/draft retention | Type unsaved feedback B after saving A. Focus the tab strip: Left from Focus selects/focuses Settings; Right wraps to Focus; End selects Settings; Home selects Focus. B remains in the feedback field, and Repeat stays off. Key handling is scoped to the native segmented control. |
| UI-04: label/helper regression | Verify visible labels Deep work and Break, placeholders Deep work cycle and Break cycle. Repeat on shows “Deep work, then break. Repeat until unchecked.”; off shows “One deep work cycle and one break, then stop.” The helper-state assertion is included in the app-model test. |
| UI-05: explicit draft/relaunch | Save A, edit B without saving, Quit/relaunch. Journal opens first; Settings restores A. With SQLite, legacy A migrates; save C, edit D without saving, and relaunch to restore C without reimporting A. |
| UI-06: real failure presentation | Debug launch with `DEEP_WORK_DATA_DIR` pointing to a regular file. Journal shows Saving unavailable; Settings says it could not be saved. Save a valid draft: failure is explicit, edits remain usable, navigation works, and there is no false saved result. This UI case was exercised before the backend conversion; the same failure path was rerun against SQLite in the native app-model/store tests. Timer/CSV/clipboard are not yet available, so their failure-path acceptance remains pending. |
| UI-07: native window controls | AppKit integration proves minimize/deminimize, zoom/restore, and close/hide without destroying owner state. The green control entered full screen; Control-Command-F entered/exited full screen and returned the native title-bar controls while retaining the draft. |
| UI-08: SQLite on normal path | Native app shows Saved on this device and Settings saved on this device. Read-only inspection of `~/Library/Application Support/app.deepwork.mac/DeepWork.sqlite` reports integrity_check=ok, user_version=1, journal_mode=wal, and the expected three tables. Directory permissions are 0700 and database permissions 0600. The known acceptance draft migrated successfully. |

The ordinary window and tab behavior above was exercised on macOS. Full VoiceOver announcements, exhaustive light/dark review, all 320 pt content layouts, actual timer continuity, menu countdown, reports/examples, exports, clipboard, real login, and Slack remain unverified or unimplemented according to their later stages.

## Reproduce an isolated persistence failure

Quit the normal app first. Use a disposable test directory, create a regular file inside it, and pass that file as `DEEP_WORK_DATA_DIR` to the Debug app. A file cannot serve as a database directory. The app must report failure and preserve in-memory edits. Quit that test process and launch normally to return to the actual Application Support store. Do not make a real user database unreadable or corrupt to test this path.

## SQLite migration regression

Review exposed an unreadable-legacy-source bug: probing with `fileExists` could interpret access denial as absence and publish empty defaults. The implemented fix reads legacy files directly, treats only an actually absent source as absent, and refuses to publish the canonical database on a read/validation failure. Passing regressions cover denied source access and a non-directory source path. Independent native reproduction verified failure publishes no database, then restores the original preference after access is repaired and a new store is opened.

Known dummy acceptance data was moved, without deletion, into `.build/ui-acceptance-archive` after the test app exited. The final app was reopened on Journal with fresh SQLite defaults and a healthy saved status. No example records or dummy feedback remain in the normal store.
