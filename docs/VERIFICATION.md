# Native verification

October 18, 2026. Progress and acceptance status are maintained only in [IMPLEMENTATION_CHECKLIST.md](../IMPLEMENTATION_CHECKLIST.md). These are observed results and reproducible use cases, not claims that later milestones are complete.

## Stage 1 environment and commands

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

The ordinary window and tab behavior above was exercised on macOS. At the Stage 1 exit, full VoiceOver announcements, exhaustive light/dark review, all 320 pt content layouts, timer continuity, menu countdown, reports/examples, exports, clipboard, real login, and Slack remained unverified or unimplemented. Stage 2 results below supersede the timer/menu portions.

## Reproduce an isolated persistence failure

Quit the normal app first. Use a disposable test directory, create a regular file inside it, and pass that file as `DEEP_WORK_DATA_DIR` to the Debug app. A file cannot serve as a database directory. The app must report failure and preserve in-memory edits. Quit that test process and launch normally to return to the actual Application Support store. Do not make a real user database unreadable or corrupt to test this path.

## SQLite migration regression

Review exposed an unreadable-legacy-source bug: probing with `fileExists` could interpret access denial as absence and publish empty defaults. The implemented fix reads legacy files directly, treats only an actually absent source as absent, and refuses to publish the canonical database on a read/validation failure. Passing regressions cover denied source access and a non-directory source path. Independent native reproduction verified failure publishes no database, then restores the original preference after access is repaired and a new store is opened.

Known dummy acceptance data was moved, without deletion, into `.build/ui-acceptance-archive` after the test app exited. The final app was reopened on Journal with fresh SQLite defaults and a healthy saved status. No example records or dummy feedback remain in the normal store.


## Stage 2 — Focus, October 18, 2026

Stage 2 adds the deterministic timer, Focus controls, exact active-segment accounting, ordered background SQLite checkpoints, paused recovery, process ownership, and native status-item projection. The reference and initial JSON tracker remain unchanged. Progress by stable ID remains in the checklist.

### Native automated verification

Final verification commands:

| Command | Result |
| --- | --- |
| `./scripts/test.sh` | **99 passed: 78 core + 21 app**, both terminal summaries present; `.build/stage2-tests.log`. Parameterized cases run in addition to these test-function counts. |
| `./scripts/build-app.sh` | Native compile/package/ad hoc signing passed; `.build/stage2-build.log`. |
| `swift build -Xswiftc -strict-concurrency=complete` | Passed, no product-source concurrency warnings; `.build/stage2-strict-build.log`. |
| `python3 scripts/generate-xcode-project.py` | Generated 11 app source references and 6 core-test references. |
| `plutil -lint DeepWork/Resources/Info.plist DeepWork.xcodeproj/project.pbxproj` | Both OK. |
| `codesign --verify --strict ".build/Deep Work.app"` | Passed. |
| Manifest hash/length comparison | All 8 approved reference files unchanged; initial JSON tracker unchanged in Git. |
| `xcodebuild -project DeepWork.xcodeproj -scheme DeepWork -configuration Debug -destination 'platform=macOS' build` | Still blocked before compilation by the exact missing-Xcode error above. |

CLT's known linker search-path/test-runtime-floor warnings remain; they are separate from test results.

A synthetic `NSStatusBarButton.performClick` caused SwiftPM's hostless main run loop to exit with status 0 before later async tests finished. Native integration now dispatches the real button's configured target/action with `sendAction`, asserts successful dispatch, and records the foreground-activation request through an injected adapter. Production still calls native app activation; the compiled app's Command-0/Focus reopen path was exercised manually. No test-delegate, retention, or private-API workaround remains. AppKit suites serialize process-global window/focus access. `scripts/test.sh` now requires a terminal result for every started run; its guard rejected the captured incomplete run and accepted the complete final run.

- Timer engine cases cover AC-03–10/12/13: exact deadlines, repeated reconciliation, multiple crossed pairs, old Repeat value before a delayed change, stale same-phase identity, paused manual transitions, zero/17-second partial records, start-again identity, ceil countdown through 480:00, progress/copy, sleep-equivalent elapsed advances, forward/backward wall-clock changes, and sealed recovery.
- App/SQLite cases cover AC-02–13: exact custom errors and boundaries, handler revalidation, stored hidden custom choices, five-second checkpoints, transition records/checkpoint in one transaction, Quit drain, crash-point recovery, unchanged live UUID, no downtime, independent settings, storage failure with usable timing, and no false saved caption.
- Native AppKit cases cover actual windows and status-item target/action dispatch: hidden Settings → Focus with the same running/paused record, menu text/font/icons/accessibility projection, boundary reconciliation on tab change, and tab first-responder retention in setup/running/paused states.
- Reduced-motion presentation is injected into the native progress component without changing system preferences. The production adapter reads SwiftUI's native Reduce Motion environment. Actual system preference propagation and exhaustive VoiceOver remain Stage 6 acceptance.

### Native UI and process acceptance

All Stage 2 manual sessions below used the isolated Debug directory `.build/stage2-native-data`; they are not real user history.

| Case | Observed native result |
| --- | --- |
| UI-09: setup and validation | Fresh launch selected Journal. Focus showed blank selectors, Repeat on, disabled Start. Approved preset menus were present. Custom focus/break selected all of the defaults 75/15 for editing. Focus 0 displayed exactly “Choose a whole number from 1 to 480.” in the UI and field accessibility help; correcting to 1 cleared the error. Valid 1/1 choices updated the summary and enabled Start. |
| UI-10: real countdown/pause | Start hid setup and displayed Deep work / 01:00 / 1-minute break next. Progress advanced with elapsed time. Pause at 23.557982083 seconds remaining displayed 00:24 and the paused-time caption; repeated observation remained frozen. SQLite contained one sealed live checkpoint and no finalized row. |
| UI-11: graceful Quit/relaunch | Command-Q exited the process after checkpoint persistence. Relaunch opened Journal; Command-0 showed the recovery notice, Deep work paused, and the same 00:24 remainder. The original focus UUID and active segment were retained. Resume cleared recovery, then hiding from Settings with Command-W allowed the timer to cross its focus deadline. Command-0 reopened Focus in its final break. |
| UI-12: automatic completion | The real one-minute focus finalized once as Complete with exactly 60.0 seconds across two active segments. The original UUID was unchanged. Break time added no row. The final break reached Cycle complete / 00:00 / Saved to your journal, with 100 percent progress, Start again and End session, and no next-phase button. SQLite integrity_check was ok and the active checkpoint was absent. |
| UI-13: independent process ownership | A copied native app bundle with a distinct test-only bundle ID targeted the same isolated data directory. It displayed “Deep Work is already open” and refused to open a second controllable session. Dismissing OK exited that process. The owner remained paused with the same checkpoint. This exercises an actual second process, not only two lock objects. |
| UI-14: abrupt process recovery | Start again created a new UUID. After periodic saving, SIGKILL terminated only the known isolated acceptance process, bypassing Quit. Relaunch restored it paused at the exact last committed 49.61512375000004 seconds (display 00:50). Read-only SQLite comparison proved identical UUID, remaining seconds, and active segments; the earlier complete row remained exactly once. |
| UI-15: paused manual transition | Take break from recovered paused focus cleared recovery and started an unpaused full one-minute break. The existing positive focus was retained as Partial. Pause changed it to Break paused / Resume without adding focus. Quit saved the break checkpoint. Final-build relaunch restored Break paused at 00:54; Finish break completed immediately, and End session restored the saved 1/1 custom setup. |
| UI-16: accessible timer regression | Parent SwiftUI identifiers initially replaced leaf identifiers and adjacent static text merged the countdown into phase/recovery text. Explicit accessibility containers plus a distinct frequently updated timer element fixed it. Native AX inspection now exposes dw-recovery-note, dw-phase-name, dw-timer named Time remaining with value 00:50, dw-run-caption, dw-progress with its rounded percentage, and separate dw-pause/dw-next/dw-end buttons. |

### Regression and platform decisions verified

- Invalid duration error copy was corrected with unit/app validation cases; invalid raw edits cannot start using an older valid stored value.
- Tab appearance initially moved focus from the tab strip into Focus. The explicit menu focus request is now separate from normal tab selection. Native key routing checks Right/Left wrap and Home/End while retaining the actual segmented first responder and session identity.
- Changing tabs now reconciles crossed boundaries before presenting Journal and queues the corresponding snapshot; a deterministic integration test verifies the record in SQLite immediately after flushing.
- Pending/failed persistence cannot claim “Saved to your journal.” A completion shows saving until its transaction succeeds; failure shows an in-memory-only message.
- Quit freezes timer/configuration actions while its final writes drain, preventing Resume or edits from enqueueing work after the termination barrier.
- Button focus requests honor the user's macOS Keyboard navigation setting; the implementation does not change global preferences or create duplicate custom focus targets. Text-field focus/select-all was verified. See Apple's focus guidance in native decisions.

### Remaining verification boundaries

Full Xcode is still not installed: the exact `xcodebuild` blocker above remains. macOS 13 and Intel execution, actual physical sleep/wake, abrupt power loss, exhaustive VoiceOver announcements, system Reduce Motion preference propagation, light/dark and narrow-window review remain unverified. Clock-policy tests exercise sleep-equivalent elapsed time deterministically, and real hidden-window timing was observed; neither is presented as a physical sleep test.

Journal reports/examples/work-schedule editing, CSV/clipboard, actual login registration and Slack remain future milestones. J-052 is still incomplete because CSV must remain usable under storage failure; J-053 still needs actual live report rows/metrics. No JavaScript result was used as native completion evidence.
