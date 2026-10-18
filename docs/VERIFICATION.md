# Native verification

October 18, 2026. Progress and acceptance status are maintained only in [IMPLEMENTATION_CHECKLIST.md](../IMPLEMENTATION_CHECKLIST.md). These are observed results and reproducible use cases, not claims that later milestones are complete.

## Stage 1 environment and commands

- macOS 27.0.1 (26A434), arm64; Apple Swift 6.4; Command Line Tools SDK.
- Current supported platform: Apple Silicon (arm64), macOS 15+. Earlier macOS 13/Intel references below record historical scope, superseded by the October 18 platform clarification. Intel and older macOS are unsupported.
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

These are historical Stage 2 results. The latest Close/Quit clarification restores Command-W continuation observed in UI-11. An intervening close-and-pause implementation was an incorrect interpretation and is superseded. Current hide/Quit verification is recorded below; icon evidence remains separate.

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

## Historical close protection and icon work — October 18, 2026

**Superseded lifecycle interpretation:** this implementation mistakenly applied pause/save to red close and Command-W. The user clarified that only full Quit should pause/save; current behavior and replacement regressions are recorded in [Close and Quit clarification](#close-and-quit-clarification--october-18-2026). UI-17–UI-19 below document the old behavior, not current acceptance. The icon and Quit-failure evidence remain relevant.

### Automated regression coverage

- `./scripts/test.sh`: **107 Swift tests passed: 78 core + 29 app**, with both terminal summaries present in `.build/close-icon-tests.log`. Eight new lifecycle functions include parameterized boundary and independent-store failure cases.
- Real SQLite integration verifies retained configuration, saved schedule, historical records, settings and explicit feedback draft; focus and break recovery retain their exact remainder, segments, and live UUID without adding closed time. Unsaved feedback and schedule drafts survive window close in memory without replacing the explicitly saved versions.
- Actual AppKit close-button target/action dispatch verifies immediate pause, save-before-hide, setup/already-paused close, delayed boundary reconciliation without duplicate records, either-store failure, blocked controls during saves, reopen cancellation of pending hide, Close/Quit overlap, and failed Quit restoring usable controls. Minimize and background saves retain running state.
- The persistent failure banner was made state-neutral: after failed Close/Quit, the user can Resume without leaving a false “timer paused” claim. Regression tests check both the continuing timer and truthful copy.
- Synthetic `NSWindow.performClose` has the same hostless SwiftPM run-loop exit limitation as `NSStatusBarButton.performClick`. The test-script completion guard rejected that incomplete run. Tests dispatch the native traffic-light button's real configured target/action with `sendAction`; real red-button clicks and Command-W were exercised in the compiled app below.
- `swift build -Xswiftc -strict-concurrency=complete`: passed, with no product-source concurrency warnings; `.build/close-icon-strict-build.log`. Existing CLT linker-path warnings remain.
- `./DeepWorkTests/Icon/test-app-icon.sh` (also run by `scripts/test.sh`): **7 native packaging cases passed**. The supplied ICNS decodes through AppKit/ImageIO in all ten standard/Retina sizes; every representation matches the production asset catalog's pixels. Missing metadata/resource, corruption, incomplete sizes, and changed artwork are rejected; delivery files and extracted catalog bytes match the original ZIP.
- `./scripts/build-app.sh`: native compile, approved ICNS packaging/pixel validation, and ad hoc signing passed; `.build/close-icon-build.log`. `plutil -lint DeepWork/Resources/Info.plist DeepWork.xcodeproj/project.pbxproj` and `codesign --verify --strict ".build/Deep Work.app"` passed. The project uses the native AppIcon asset catalog; actual Xcode/`actool` execution is still blocked by the exact missing-Xcode error above, reproduced after this change.
- All eight approved reference files remain byte-identical to the manifest; the initial JSON tracker is unchanged. Checklist validation confirms 137 unique IDs and 36 DONE markers consistent with their statuses.

### Compiled-app acceptance

All test sessions used `.build/close-icon-native-data` or the disposable regular-file fixture `.build/close-feature-blocked-store`. The normal Application Support history was not used for these sessions.

| Case | Observed native result |
| --- | --- |
| UI-17: red close during focus | Start a 60/10 pair with Repeat off, then click the red traffic light. The window hides after saving. Command-0 reopens **Deep work paused / Resume / 59:54**. Read-only SQLite comparison shows the same live UUID, sealed segments and exact remainder **3593.399417208 seconds**; preferences/schedule are unchanged and no finalized row was added by Close. The close button's native label is “Close window and pause timer,” with help “Save changes and pause timer.” |
| UI-18: Command-W during break | Take break explicitly finalizes the positive focus as one Partial row and starts the break. Command-W saves and pauses it; reopening shows **Break paused / Resume / 09:57**. SQLite retains **596.365034917 seconds**, the single earlier row and saved configuration/schedule. Clean Quit retains the same remainder and row; integrity_check is ok. |
| UI-19: failed Close | Launch against the disposable regular file, then click Close. The native window stays visible and exposes `dw-lifecycle-error`: “Changes could not be saved. Keep Deep Work open to preserve changes that are still in memory.” The existing store failure stays visible; no false save is reported. |
| UI-20: failed Quit choices | Command-Q in that failure instance opens the native warning with **Keep Open** first/default and **Quit Without Saving** second. Keep Open dismisses the warning and restores the usable window. A second Quit followed by explicit Quit Without Saving exits only that test process. In setup, the alert correctly omits a claim that a timer is paused. |
| UI-21: final-build relaunch | Rebuild and relaunch against the same isolated healthy data. Journal retains its one historical row. Command-0 shows the recovery notice and **Break paused / 09:57 / Resume**, preserving the saved remainder and Repeat off. No process downtime was counted. |
| UI-22: actual app icon/cache regression | Initially the existing bundle identity still displayed a generic icon in About despite valid resource metadata and native decoding. Quit, refresh the rebuilt bundle's root modification time, and reopen: AppKit's native About panel displays the supplied blue ring icon. The CLI build now performs that bundle refresh after signing, matching ordinary rebuilt-app discovery, without clearing global caches or overriding icon images in application code. The final app was returned to Journal on its normal data directory. |

Full Xcode, macOS 13/Intel runtime, physical sleep/wake, power-loss durability and exhaustive VoiceOver remain unverified as described above. Failure announcement dispatch and AX labels are implemented; they are not a complete screen-reader acceptance pass. Force Quit/crash still restores only the last committed checkpoint and can lose the uncommitted interval.

## Icon source cleanup — October 18, 2026

The subsequent user-requested cleanup removes the top-level `icons/` delivery folder. `DeepWork/Resources/Assets.xcassets/AppIcon.appiconset` is now the sole production source. The supplied PNG, ICNS and ZIP were moved byte-for-byte into ignored `.local-artifacts/icon-delivery-archive/`, outside disposable build output. Every production catalog file matched the ZIP, and the supplied master matched the largest catalog PNG exactly. Provenance and current paths are in [APP_ICON.md](APP_ICON.md).

- `./DeepWorkTests/Icon/test-app-icon.sh`: **12 cases passed**, `.build/icon-cleanup-tests.log`. The CLI derives ICNS from unchanged catalog PNGs using `iconutil`; native validation proves all ten point/pixel sizes and pixel parity. Tests cover metadata/resource corruption, missing input/catalog, malformed metadata, deterministic output, source immutability, refusal to generate inside the catalog, and preserving the previous good output after failure. Builds/tests have no delivery-folder or archive dependency.
- `./scripts/build-app.sh`: passed native compile, generated-icon validation, packaging, ad hoc signing and bundle timestamp refresh; `.build/icon-cleanup-build.log`. `codesign --verify --strict ".build/Deep Work.app"`, project/plist lint and changed-shell-script syntax checks passed.
- Relaunched the rebuilt native app and inspected About: it displays the approved blue ring icon. Returned the app to Focus. The asset catalog contains no generated ICNS or ZIP; the delivery archive is ignored by Git; `reference/` remains byte-identical.
- No application Swift behavior changed. At that cleanup, the prior 107-test Swift result was the last full-suite result; the cleanup ran the affected native icon checks and app build. The later lifecycle verification below supersedes the Swift result. Actual Xcode/`actool` compilation remains unverified because full Xcode is not installed.

## Close and Quit clarification — October 18, 2026

This replaces the incorrect close-and-pause behavior recorded above. Red close and Command-W only hide the retained window; running cycles continue, paused cycles stay paused, and menu-bar click brings Focus forward. Only full Quit pauses and waits for durable saves before exiting. Menu titles use the full **Deep work** and **Break** phase names.

### Current automated results

- `./scripts/test.sh`: **109 Swift tests passed (78 core + 31 app)** and **12 native icon packaging cases passed**; both complete Swift Testing summaries are in `.build/hide-quit-tests.log`.
- `./scripts/test.sh --filter ClosePersistenceTests`: **9 lifecycle test functions passed**, including parameterized cases, plus the 12 icon checks; `.build/close-hide-focused.log`.
- Close regressions dispatch the actual AppKit traffic-light target/action. They verify immediate hiding, automatic ticker-driven SQLite checkpoints while hidden, multiple crossed phase boundaries, exactly-once records, same live UUID/window after reopening, setup and already-paused states, historical/settings/schedule/saved-draft retention, independent store failures, and deliberately blocked writes. Hiding never freezes controls or leaves a deferred hide that could dismiss a reopened window.
- Quit regressions verify pause at the Quit instant, ordered persistence after earlier hidden writes, no duplicate records, paused recovery without process downtime, and usable controls after independent or combined save failures. Explicit unsaved draft semantics remain covered.
- Menu integration dispatches the actual `NSStatusBarButton` target/action and asserts countdown/title before reopening, hidden focus-to-break transitions, retained running or paused state, the same window/session, and foreground activation requests. Core tests cover full phase labels and countdown rounding. Hostless `performClick`/`performClose` remain unsuitable because they can stop the SwiftPM main run loop; `sendAction` exercises the native button wiring, and the completion guard rejects truncated runs.
- `./scripts/build-app.sh`: native compile, icon packaging/pixel validation and ad hoc signing passed; `.build/hide-quit-build.log`.
- `swift build -Xswiftc -strict-concurrency=complete`: passed without product-source concurrency warnings; `.build/hide-quit-strict-build.log`. Existing CLT linker search-path warnings remain.
- `plutil -lint DeepWork/Resources/Info.plist DeepWork.xcodeproj/project.pbxproj`, `codesign --verify --strict ".build/Deep Work.app"`, and `git diff --check`: passed. All eight reference hashes match; the initial JSON tracker is unchanged. Checklist validation confirms 137 unique IDs, 36 DONE, and matching status/checkbox values.

### Current compiled-app acceptance

Used `.build/hide-quit-native-data` with the rebuilt native app; acceptance records did not enter the normal Application Support store.

| Case | Observed native result |
| --- | --- |
| UI-23: red close and hidden focus | Start a 60/10 pair with Repeat off. Click red close: reopening retains **Deep work / Pause**, not Resume. Then Command-W hides again. Two read-only SQLite observations before reopening show the same live UUID, focus remainder decreasing from **3586.087713375** to **3570.565491542** seconds, and zero finalized rows. Command-0 brings Focus forward still running. The native close label is “Close window and keep timer running.” |
| UI-24: Command-W during break | Take break creates one Partial focus row, then Command-W hides. Before reopening, SQLite break checkpoints advance from **595.32835075** to **555.088328** seconds; the historical row count stays one. Command-0 brings the same break forward with **Pause**, still running. |
| UI-25: Quit and recovery | Command-Q exits the actual test process successfully. SQLite retains break remainder **537.664724** seconds; integrity_check is ok. Relaunch initially shows Journal with one saved session; Focus shows the recovery notice, **Break paused / 08:58 / Resume**. Command-W/reopen preserves that paused display. A later Quit retains exactly **537.664724** seconds and the same one historical row, proving downtime and the already-paused hidden interval were excluded. |

Menu-item behavior is verified through real AppKit button dispatch; compiled-app Command-0 verifies the shared handler's foreground/window behavior. A physical menu-extra mouse click was not independently observed in this run: the UI adapter exposes the app window and application menus but not its status item, and selecting SystemUIServer returned `timeoutReached (-10005)`. Do not treat the adapter-level test as a recorded desktop mouse click. The manual menu-click steps remain in README.

Full Xcode remains unavailable with the exact `xcodebuild` error recorded above. macOS 13/Intel, physical sleep/wake, power loss, and exhaustive accessibility/visual sweeps remain unverified. The icon is unchanged by this correction, and its native packaging checks pass again.

## GitHub release packaging — October 18, 2026

The initial release implementation produced a universal optimized app ZIP, `SHA256SUMS` and `release-metadata.json`, with no local settings or journal data. Ad hoc signing is explicit; `security find-identity -v -p codesigning` reported **0 valid identities**. Stable release tags are rejected until Developer ID signing and notarization are implemented. The user subsequently restricted support to Apple Silicon and macOS 15+; no universal release was published. Hosted workflow and publication results must be assessed separately from local checks.

- At commit `b83efa0`, `./scripts/package-release.sh v0.1.0-preview.1 1` completed both optimized architecture builds, icon generation, ad hoc signing, archive extraction/verification and atomic output; `.build/release-native-package.log`.
- `./DeepWorkTests/Release/test-release.sh .build/releases/v0.1.0-preview.1 v0.1.0-preview.1`: **20 policy tests and 15 real archive regressions passed**; `.build/release-native-tests.log`. Cases include version/source validation, failed-output preservation, exact bundle contents, missing or stripped executable permissions/types, corrupted signature, unexpected SQLite/private files, symlinks, wrong architecture, per-slice minimum macOS, checksum/metadata changes, and Debug-only data override rejection.
- `python3 DeepWorkTests/Release/test-publish-release.py`: **33 publication regression tests passed**. Real temporary Git repositories exercise commit and annotated-tag rules; mocked GitHub/curl boundaries cover incorrect context, duplicate releases/drafts, upload/download failures, changed tag/draft identity, corrupted public downloads and ambiguous publication outcomes. These tests do not establish actual GitHub publication.
- Workflow YAML parsing, shell syntax checks and `git diff --check` passed. The workflow uses read-only test/package jobs and a tag-only publication job with write permission; it downloads and verifies assets before and after publication. PR builds use disposable run-specific package versions so a published tag cannot break later PR checks.
- The clean optimized build exposed a missing main-actor annotation in the native tab coordinator that the earlier incremental strict build had not reported. Marked the coordinator `@MainActor`; a native target/action regression verifies all three tab bindings and ignores no-selection input. `./scripts/test.sh --filter WindowIntegrationTests` passed 2 native tests plus 12 icon checks; fresh optimized strict builds passed on both architectures without product-source concurrency warnings. Logs: `.build/navigation-actor-tests.log`, `.build/navigation-actor-release-arm64.log`, `.build/navigation-actor-release-x86_64.log`. CI additionally treats Swift warnings as errors. Existing Command Line Tools search-path and x86_64 compatibility-library linker warnings are toolchain limits; the later platform clarification removes Intel support.
- After the actor fix, `./scripts/test.sh` passed **110 native Swift tests (78 core + 32 app)** and **12 icon checks**, with complete summaries; `.build/release-full-native-tests.log`.

Hosted checks and publication evidence are recorded below. Packaging does not advance the 36/137 product acceptance count.

### Apple Silicon support and CI capture correction

The user narrowed support before publication: Apple Silicon (M1 or later) only, with macOS 15 selected as the minimum. SwiftPM, Xcode, bundle metadata, local builds, release archives and CI now follow that boundary. The ZIP name ends in `macOS-arm64.zip`; archive verification rejects Intel/universal executables and a lower deployment target. This changes platform compatibility only; SQLite schema and existing user data are unchanged. Earlier universal artifacts were local validation output and were not published.

The first hosted run ([39107299114](https://github.com/lukin-io/deep-work/actions/runs/39107299114)) exposed an invalid F-015 capture assumption: `NSHostingView.cacheDisplay` returned identical images on macOS 15 despite different progress values. The original capture did not establish whether those images contained the native control. The regression now waits for the production view's real `NSProgressIndicator` value and requires a visible determinate bar, valid range and updates from 0.374 to 1 for both motion policies. Core Animation pixel differences are additionally required when capture supplies nontransparent pixels; equal nonempty images still fail. Unsupported capture is explicitly logged as unverified appearance, not inferred from equality. Both local motion-policy captures produced distinct nontransparent pixels; `./scripts/test.sh --filter FocusPresentationTests` passed both test functions (`.build/focus-native-control-tests.log`). Actual desktop appearance/accessibility remains separately recorded under UI-16.

Explicit `self` in Swift Testing throwing closures removes the older hosted Swift toolchain's capture warnings without changing assertions. `./scripts/test.sh --filter TimerEngineTests` passed 33 native tests and 12 icon checks (`.build/release-timer-compatibility-tests.log`).

The revised platform build passed locally: 4 platform checks, 110 native Swift tests and 12 icon checks (`.build/release-arm64-native-tests.log`). `./scripts/build-app.sh` produced an arm64-only executable with Mach-O and bundle minimum version 15.0 and a valid ad hoc signature (`.build/apple-silicon-build.log`). Packaging policy tests (20), real arm64 archive regressions (17) and publication regressions (33) passed; the additional artifact cases reject both Intel-only and universal binaries/metadata and incorrect deployment floors (`.build/release-arm64-artifact-tests.log`). These isolated fixture checks do not establish publication.

Raising the deployment floor exposed deprecated SwiftUI change handlers. All eight callbacks now use the supported zero/two-argument overload, preserving new-value behavior and `initial: false`. `swift build -Xswiftc -strict-concurrency=complete -Xswiftc -warnings-as-errors` passed with only the existing CLT linker search-path warnings; 18 affected native Focus/window/app-model/Close tests plus 4 platform and 12 icon checks passed (`.build/swiftui-modernization-build.log`, `.build/swiftui-modernization-tests.log`).

### Hosted Apple Silicon verification

[PR CI run 39107935588](https://github.com/lukin-io/deep-work/actions/runs/39107935588) passed for head `9e1cfe299583a3c18f6e19e88540ec99cceaf1c1` before the release was tagged. The hosted runner used Apple Silicon and macOS 15.7.9.

- `./scripts/test.sh`: **110 native Swift tests, 4 platform checks and 12 icon checks passed**. The native F-015 control/value/motion-policy assertions passed. Core Animation capture was unavailable/transparent for both policies on this runner, so CI does not establish pixel appearance; local nontransparent pixel checks and recorded UI-16 remain the separate visual evidence.
- `python3 DeepWorkTests/Release/test-publish-release.py`: **33 publication regressions passed**. Strict concurrency compilation with Swift warnings treated as errors and project/plist lint passed.
- `xcodebuild -project DeepWork.xcodeproj -scheme DeepWork -configuration Release -destination 'platform=macOS' -derivedDataPath .build/Xcode CODE_SIGNING_ALLOWED=NO build`: **BUILD SUCCEEDED**, using **Xcode 16.4 and macOS SDK 15.5**. This includes actual asset-catalog compilation. Local Xcode remains unavailable; the earlier local blocker does not describe the hosted result.
- The optimized Apple Silicon package and archive verification passed, followed by **20 release policy tests and 17 archive regressions**. PR publication correctly remained skipped; its temporary Actions artifact is not a public app release.
- Local packaging at the same source commit also passed: `./scripts/package-release.sh v0.1.0-preview.1 1`, then `./DeepWorkTests/Release/test-release.sh .build/releases/v0.1.0-preview.1 v0.1.0-preview.1` (20 policy + 17 artifact tests). Logs: `.build/release-arm64-final-package.log`, `.build/release-arm64-final-tests.log`.

### Published preview and public-download verification

[Release v0.1.0-preview.1](https://github.com/lukin-io/deep-work/releases/tag/v0.1.0-preview.1) was published on October 18, 2026 at 07:38:53 UTC by [successful tag workflow 39108209226](https://github.com/lukin-io/deep-work/actions/runs/39108209226). The annotated tag points to `9e1cfe299583a3c18f6e19e88540ec99cceaf1c1`; the app PR remains open and unmerged.

- [Download the compiled app](https://github.com/lukin-io/deep-work/releases/download/v0.1.0-preview.1/Deep-Work-v0.1.0-preview.1-macOS-arm64.zip): **Apple Silicon only, macOS 15+**, version 0.1.0, build 3, Release configuration. Hosted packaging used Swift 6.1.2 and macOS SDK 15.5.
- The tag workflow reran and passed **110 native Swift tests, 4 platform checks, 12 icon checks, 33 publication regressions, 20 release policy tests and 17 archive regressions**, plus strict compilation, project/plist lint and the Xcode Release build. Pixel-capture limitations match the PR run above.
- The publisher created a draft, uploaded all three assets, verified downloaded bytes and native bundle contents, published as a prerelease with Latest disabled, and verified unauthenticated public downloads. The final publication job and overall workflow both succeeded.
- Independently downloaded all three assets through their public browser URLs, without credentials, to `.build/downloaded-releases/v0.1.0-preview.1`. `shasum -a 256 -c SHA256SUMS` passed for the app ZIP and metadata. `./scripts/verify-release.sh .build/downloaded-releases/v0.1.0-preview.1 v0.1.0-preview.1 9e1cfe299583a3c18f6e19e88540ec99cceaf1c1` passed archive safety, executable permissions, arm64-only architecture, Mach-O and plist minimum macOS 15.0, icon pixels, license, signature, source metadata and checksums.
- The app ZIP is **1,929,997 bytes**, SHA-256 `f411dc1e1b8806a35aa422d635c332f7cf95861ca67b4cb4e0579f6a6868f918`. Its only companion assets are `SHA256SUMS` and `release-metadata.json`; no user settings, journals or SQLite files are included.

This is an **ad hoc signed, unnotarized preview**. Developer ID signing, notarization and Gatekeeper acceptance remain unverified/unimplemented, as stated in its release notes. Physical sleep/wake, full VoiceOver/appearance acceptance and a physical status-item click remain separate product acceptance limits; successful publication does not change the 36/137 accepted product items. Intel and macOS versions before 15 are unsupported, not pending test targets.

## CI hardening and first-Mac guidance — October 18, 2026

- `security find-identity -v -p codesigning` again reported **0 valid identities**. README now starts its release-readiness TODO with that missing Developer ID identity, followed by the unimplemented stable signing/notarization path. The Apple guide links official guidance and distinguishes GitHub distribution from App Store-only conditions.
- `python3 DeepWorkTests/Build/test-ci-policy.py`: **22 environment/workflow regressions passed** (`.build/ci-policy-tests.log`). They cover minimum/newer explicit toolchains, absent/mismatched tools, non-macOS/Intel hosts, SDK/compiler drift, triggers, permissions, job dependencies and publication gating. They do not establish real hosted results.
- `python3 DeepWorkTests/Release/test-publish-release.py`: **38 publication regressions passed** (`.build/main-ancestry-publication-tests.log`). Five added cases cover accepted ancestors of main, unmerged commits, stale/missing refs, fetch failures and history replacement during draft verification. Four negative cases were reproduced against the previous publisher before validating the correction (`.build/main-ancestry-regression-before.log`). The publisher refreshes main and checks ancestry both before creating a draft and immediately before publication.
- Shell syntax and `git diff --check` pass. No application behavior or database schema changed; no new release was published for these CI/docs changes. Hosted matrix results and merge provenance are recorded after their actual completion.

### Current CI result, merge and next branch

[PR run 39109011793](https://github.com/lukin-io/deep-work/actions/runs/39109011793) **passed** on exact head `0381dafa55568d9c656300e0701c9320721bdabe` before merging:

| Runner | Verified toolchain | Native and policy results | Xcode Release |
| --- | --- | --- | --- |
| macOS 15.7.9, arm64 | Xcode 16.4, Swift 6.1.2, SDK 15.5 | 110 Swift, 4 platform, 12 icon, 22 CI policy, 38 publication tests passed | BUILD SUCCEEDED |
| macOS 26.6.2, arm64 | Xcode 26.6, Swift 6.3.3, SDK 26.5 | 110 Swift, 4 platform, 12 icon, 22 CI policy, 38 publication tests passed | BUILD SUCCEEDED |

Both strict-concurrency/warnings-as-errors builds and plist/project checks passed. F-015 native control checks passed on both; macOS 26 also produced distinct nontransparent progress pixels for both motion policies. macOS 15's capture remained unavailable/transparent, explicitly unverified for appearance.

The package job ran after both matrix jobs passed, built the optimized arm64 app, and passed **20 policy + 17 archive regressions**. Publication correctly remained skipped for this PR event. The changed main-ancestry publishing guard is covered by the 38 fixture regressions; no new live release was created merely to test that guard.

PR #1 was merged with its history preserved into `main` as `2ea0b94bc3cb320087921fbb3ff0670d361a44dc`. The merge API used the verified expected head SHA and returned `merged: true`. After fetching the merged remote, local `main` fast-forwarded to it; only then was `feature/journal-stage-3` created. Git ancestry verifies that the branch includes the complete reviewed head and published-preview source. The Stage 3 plan and post-merge evidence are documentation changes, not a Stage 3 implementation or new product acceptance.
