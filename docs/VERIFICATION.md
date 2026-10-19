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

## Stage 3 — Journal and work schedule — October 19, 2026

Implemented on `feature/journal-stage-3`, based on the merged Stage 1/2 app. This is source implementation and PR validation; **no new release is published**, and preview `v0.1.0-preview.1` remains immutable with Stage 1/2 behavior. The report engine consumes existing raw records and checkpoints; SQLite schema/version and stored session timestamps are unchanged.

### Native automated verification

- `./scripts/test.sh`: **170 native Swift tests passed (115 core + 55 app)**, plus **4 platform checks and 12 icon checks**; complete summaries in `.build/stage3-final-tests.log`. Parameterized cases include all seven week starts, weekday/shift boundaries, 0/1/12/13/25 rows and slow-save/Quit cases. These are native Swift/SQLite/AppKit results, not JavaScript reference tests.
- `JournalReportTests` ports all ten reporting-reference arithmetic scenarios through valid native records. Additional coverage includes half-open bounds, completion-only rows, positive clipped partial/live focus, subsecond preservation, all overlapping dates, future/zero/off-day dates, maximum elapsed bounds, weekly forcing, Kyiv 23/25-hour DST dates, missing/repeated cutoffs, strict local input parsing, pre-anchor rotation, invalid records and duplicate IDs. Examples cover the specified 35-date pattern and omit future-ended records.
- `JournalIntegrationTests` verifies one app-owned projection, actual/example isolation, SQLite absence of examples, live/pause/break accounting, exactly-once finalization, grouping/page retention and reset, retained raw bounds, time-zone reinterpretation, valid/invalid schedule drafts, Save/Cancel/relaunch and unchanged raw history. A real SQLite trigger rejects schedule writes to verify retained edits and failure status. A gate around a real SQLite store delays Save while timer boundaries and Quit occur; the final saved schedule, records and checkpoint match the latest state.
- Two regressions were reproduced before validating fixes: report selection after a delayed timer deadline incorrectly omitted completion (`.build/stage3-delayed-report-before.log`, three failed assertions); an idle cutoff without its scheduled refresh left the projection unpublished (`.build/stage3-idle-cutoff-before.log`, failed refresh assertion). The final suite covers both, including re-arming the idle cutoff after a failed Quit. An earlier attempted idle regression run was stopped by a CLT SwiftUI macro compilation error and is not treated as behavioral evidence.
- `WorkScheduleDraftTests` exercises missing/invalid/raw text, validation priority, inactive-mode retention, zero weekdays, 1/31 limits, 00:00/23:59, invalid anchors and 14-day previews through DST. `WorkSchedulePresentationTests` edits actual native `NSTextField` delegates and verifies no implicit saved-schedule mutation. Native tab key events verify returning to an open draft does not steal tab-strip focus.
- `JournalPresentationTests` verifies the actual `NSTableView`: four read-only columns, original timestamps, right-aligned duration/outcome, native headers, alternating rows, independent scroll view and updated rows. Presentation tests cover complete/partial/live/paused/outside-range labels, planned versus total duration, exact accessible chart descriptions and the zero baseline/relative scale.
- Four actual `NSWindow`/`NSHostingView` layout cases pass at 320 and 696 points in light/dark appearances: twelve table rows, three independent scroll containers, horizontal chart overflow and all Range/rotating-shift text fields within the window bounds. Initial optional layer captures produced uniform backgrounds, so that capture helper was removed; these tests prove geometry and appearance propagation, not pixel readability. J-002 and W-013 retain their visual acceptance gaps.
- `swift build -Xswiftc -strict-concurrency=complete -Xswiftc -warnings-as-errors` passed (`.build/stage3-strict-build.log`). Existing CLT linker search-path warnings remain; no production Swift warnings are accepted.
- `./scripts/build-app.sh`: native compilation, icon validation, arm64 bundle packaging and ad hoc signing passed (`.build/stage3-app-build.log`). Project references regenerated with `python3 scripts/generate-xcode-project.py`; `plutil -lint DeepWork/Resources/Info.plist DeepWork.xcodeproj/project.pbxproj` passed. All eight `REFERENCE_MANIFEST.json` hashes match; `reference/` and `implementation-tracker.json` are unchanged.

### Compiled-app observations

Ran the actual Debug app with `DEEP_WORK_DATA_DIR="$PWD/.build/stage3-ui-data"`; no sample or acceptance records were written to the normal Application Support database. The local environment is Apple Silicon/macOS 27.0.1/Swift 6.4 and Command Line Tools. The observations below do not establish full VoiceOver or physical sleep/wake acceptance.

| Case | Observed result |
| --- | --- |
| UI-26: initial report and drilldown | Fresh empty store opens Journal/Week with the labelled Example data banner. The report showed 2h 30m, two complete records and 1/7 days; seven accessible daily buttons exposed full date, duration, cycles and off-day state. Clicking a day opened its full Day report. The native table retained original Started/Ended timestamps and planned durations. |
| UI-27: raw Range validation | Blank, malformed and equal From/Until values showed the error, zeroed metrics and removed chart/rows. Correcting Until restored the report. Range controls explicitly show local-time format and exclusive-end guidance; unavailable Export CSV stays disabled. |
| UI-28: schedule validation, Save and relaunch | Rotating shifts with Work `1.5` disabled Save and cleared the preview. Correcting to 3 work / 2 rest and cutoff `04:00` restored fourteen dates. Save updated the exact summary and report classification while retaining raw Range inputs. Quit and a direct SQLite read/relaunch confirmed the saved schedule, zero actual records and no persisted examples. A midnight-to-midnight range spanning a 04:00 cutoff correctly overlapped eight reporting dates. |
| UI-29: draft retention and Cancel | Any day displayed its explanation and fourteen Work dates. Settings → Journal retained that unsaved mode. Escape invoked Cancel; the report returned to the saved 3/2 schedule. Save/Cancel behavior is also covered against real SQLite. |
| UI-30: chart grouping and paging | A Sep 15–Oct 26 example range showed 74 sessions, 81h 30m, 64 completed cycles, 10 partial sessions and 30/41 days. Next changed 1–12 to 13–24 without changing totals. By week changed the chart to six weekly buckets while keeping the same page and totals. The native table independently scrolls with its header; the daily chart exposes horizontal scrolling for the longer range. |
| UI-31: empty actual history | Show my journal removed the sample banner and produced zero metrics, empty date buckets and the approved empty-state message. Start a focus cycle opened Focus with no timer started. The duration-picker focus step remains unverified under this Mac's keyboard-navigation preference. |

Compiled accessibility inspection found merged container identifiers in the initial UI. Explicit containment separates source-banner actions, shift fields, footer/storage and empty-state actions. The native Range/shift text controls, table cells and chart button descriptions were re-observed after rebuilding. The metric regression was also reproduced in the compiled accessibility tree: one combined element incorrectly carried only the focus-time ID. Explicit per-metric labels/values now expose all three distinct IDs (`dw-stat-time`, `dw-stat-cycles`, `dw-stat-days`) with their correct names and values. This is a reproducible native acceptance case because the hostless AX tree cannot exercise it. Native UI fixes and remaining accessibility limits are tracked under the original IDs, rather than counted as complete from a model-only test.

### Verification limits and next milestone

- `NSApplication.shared.isFullKeyboardAccessEnabled` reports **false** on this Mac. Apple documents activation-focus eligibility for button-like controls under that preference. Tests do not change it. Initial Reporting days focus, return-to-Schedule focus, all weekday keyboard activation, chart keyboard activation/live focus retention and the empty-action duration focus remain **unverified**. The hostless SwiftUI accessibility tree is empty on this local runner; tests require the real native editor/table/scroll adapters and explicitly log unavailable AX checks. A skipped AX branch is not acceptance.
- Full VoiceOver traversal and spoken announcements, physical system time-zone notification delivery, physical sleep/wake and complete visual/platform sweeps remain unverified. Injected time-zone/clock and asynchronous cutoff tests prove the implemented behavior at those boundaries, not an observed physical system change.
- Full Xcode remains unavailable locally (`xcode-select -p` selects `/Library/Developer/CommandLineTools`; `xcodebuild` requires full Xcode). Hosted CI results for this branch are recorded separately below when available; earlier Stage 2 CI does not verify this implementation.
- J-017–J-020 include All Sessions export isolation in their shared completion checks, and J-052 includes export during storage failure. Those checks remain open until **Stage 4**, alongside J-048–J-051 CSV serialization/native save/cancel/failure, Settings export and feedback clipboard. The chart IDs also retain their shared keyboard completion gate. The checklist records 83/137 accepted IDs and the exact remaining checks.

### Hosted CI compatibility correction

The first Stage 3 [PR run 39235692951](https://github.com/lukin-io/deep-work/actions/runs/39235692951) exposed an Xcode 16.4/Swift 6.1.2 test-compilation difference: `[0, 23 * 3_600, 0]` was inferred as `[Int]` inside the Swift Testing macro despite a `[TimeInterval]` comparison. The DST fixture now declares `[TimeInterval]` explicitly; the expected values and production code are unchanged. `./scripts/test.sh --filter JournalReportTests` passes all 22 affected native tests locally, plus platform/icon checks (`.build/stage3-xcode16-fixture-tests.log`). Hosted verification must pass on the corrected revision before claiming matrix success.

### Hosted Stage 3 result

[PR run 39236029448](https://github.com/lukin-io/deep-work/actions/runs/39236029448) **passed** for source head `fbb590580f8efb990894f066013eab14e40d1c8a`, tested as GitHub's merge preview `1c06b24` against `main` at `2ea0b94bc3cb320087921fbb3ff0670d361a44dc`.

| Runner | Verified toolchain | Native/policy tests | Xcode Release |
| --- | --- | --- | --- |
| macOS 15.7.9, arm64 | Xcode 16.4, Swift 6.1.2, SDK 15.5 | 170 Swift, 4 platform, 12 icon, 22 CI policy and 38 publication regressions passed | BUILD SUCCEEDED |
| macOS 26.6.2, arm64 | Xcode 26.6, Swift 6.3.3, SDK 26.5 | 170 Swift, 4 platform, 12 icon, 22 CI policy and 38 publication regressions passed | BUILD SUCCEEDED |

Both strict-concurrency builds with Swift warnings treated as errors and project/plist validation passed. Both runners passed the four native report/schedule geometry cases; hostless SwiftUI chart/picker accessibility remained unavailable and explicitly unverified. Hosted success does not change the remaining keyboard/VoiceOver/visual acceptance gates.

The dependent package job built the optimized arm64/macOS 15+ app, verified the archive and passed **20 release-policy plus 17 actual archive regressions**. Its temporary `macOS-release` Actions artifact is 2,181,510 bytes (artifact ID `12179421907`); it is not a GitHub Release or public app download. Publication correctly remained **skipped**. At the Stage 3 handoff, PR #2 was open against `main`; no merge or new version tag had been requested or performed. Its later authorized merge is recorded in Stage 4 below. The follow-up documentation commit records this completed run without changing product code or tests.

## Stage 4 — CSV export and feedback — October 19, 2026

### Starting revision and scope

PR #2 head `29d7eebbf93b63964d98fb0e470507acfe861ace` passed [CI run 39241084249](https://github.com/lukin-io/deep-work/actions/runs/39241084249): both native/Xcode matrix jobs and packaging succeeded; tag-only publication was skipped. It was then merged into `main` as `e2cee410dfe1e5fe87e54c6a186416a2ab453425`. After fetching and fast-forwarding local `main`, `codex/settings-export-stage-4` was created from that merge. This stage adds shared CSV export, native saving and feedback draft/clipboard behavior. It does not publish a release, enable login registration or connect Slack.

### Local native verification

Environment remains Apple Silicon, macOS 27.0.1, Swift 6.4 and `/Library/Developer/CommandLineTools`. Full Xcode is unavailable locally; project/plist validation is not an Xcode build.

| Check | Result |
| --- | --- |
| `./scripts/test.sh` | 232 native Swift tests: 133 core + 99 app; 4 platform and 12 native icon checks pass. |
| `swift build -Xswiftc -strict-concurrency=complete -Xswiftc -warnings-as-errors` | Production compilation passes. Existing CLT linker search-path warnings are separate from Swift diagnostics. |
| `./scripts/build-app.sh` | Compiles and packages the ad hoc signed `.build/Deep Work.app`; native icon verification passes. |
| `python3 scripts/generate-xcode-project.py` | Explicit references regenerated for 19 app sources and 9 core test sources. |
| `plutil -lint DeepWork/Resources/Info.plist DeepWork.xcodeproj/project.pbxproj` | Both pass. |
| `git diff --check` | Passes. Approved `reference/` and initial JSON tracker remain unchanged. |

Local logs remain ignored under `.build/`: `stage4-full-tests.log`, `stage4-final-build.log`, `stage4-feedback-strict-final.log`, and the focused regression logs below. These are local evidence, not hosted CI or release evidence.

- **CSV contract:** `ReportCSVExporterTests` checks every column and quoted/BOM/CRLF byte contract, filenames, millisecond rounding, UTC/DST offsets, clipped versus lifetime focus, completed-boundary membership, live/paused rows, examples, empty/invalid inputs, duplicate records and all-history independence from report range. The half-millisecond regression first failed (`stage4-csv-rounding-before.log`) and passes after explicit rounding.
- **Export integration:** `ExportIntegrationTests` exercises both entry points, more than one page, actual/example separation, invalid/empty/zero-live availability, live summary updates in Settings, overdue-phase reconciliation exactly once, immutable snapshots during delayed saves, duplicate export suppression, stale scope acknowledgments, failed SQLite with usable in-memory export, and accepted-write Quit success/failure/retry.
- **Native saving:** `CSVFileExportServiceTests` uses real file creation/replacement and failure preservation, actual NSSavePanel configuration/response mapping, cancellation, late chooser responses, delayed accepted writes and failed-Quit retry. Quit ordering initially reproduced nine failed assertions (`stage4-export-quit-before.log`); all 18 service tests then pass (`stage4-file-export-tests.log`). Injected chooser responses prove service behavior, not actual user interaction with a sheet.
- **Feedback:** typed validation covers optional/invalid email priority, raw UTF-16 boundaries, trimming, empty and over-limit input and exact payloads. Real SQLite and a named native pasteboard prove Save A → Copy B → relaunch A, retained launch preference, failed-store copying and stale asynchronous acknowledgments. A rejected pasteboard write tests failure presentation and selection intention. Native editor tests cover Unicode select-all, input limits, multiline Return, Undo/Redo synchronization, responder transitions, disabled editing during Quit and re-enabling without content loss. Regressions are in `stage4-feedback-focus-fix.log` and `stage4-feedback-disabled-fix.log`.

### Compiled-app observations

- Journal example Week Oct 19–26 exported 3 rows, 12,600 focus seconds and 3 completions. Settings Current Journal Report produced byte-identical output for that snapshot. Both used the actual native Save panel and exposed success text in the accessibility tree.
- Selecting Quit Deep Work from the native app menu while an untouched Save panel was open cancelled the panel and exited the isolated process; the separate personal app remained running. No new CSV was written.
- Cancelling the Settings Save panel produced no success claim. Settings All Sessions correctly disabled exporting for an empty actual journal even while Journal displayed examples.
- Range Sep 15–Oct 26 showed 75 sessions, 82h30m and 65 completed cycles. Export while page 2 displayed rows 13–24 saved all 75 rows; parsed CSV contained 297,000 focus seconds and 65 completions. Files in `.build/stage4-ui-exports` were checked using Python's independent standard-library CSV reader. At the user's request, a 3-row example export was also saved and verified in `~/Downloads/deep-work-example-2026-10-19-to-2026-10-26.csv`.
- Settings exposes distinct stable identifiers for the export and feedback controls. The compiled accessibility tree initially showed inherited container IDs; adding an explicit containing accessibility group fixes the child identifiers.
- Command-Return saved a multiline draft, with plain Return inserting a message newline. Copy Feedback produced the exact current form payload and success caption while SQLite still held the earlier explicitly saved text. Quit/relaunch restored that earlier draft with “Your saved draft is ready.” Native Save validation identifies email before message; message focus was corrected after the compiled email-to-message case exposed the previous SwiftUI/native focus bridge problem.

Final rebuilt-app keyboard regression passed: invalid email Return kept email focus; clearing it then Return showed the message error and moved focus to the message editor; multiline Return plus Command-Return saved exactly the expected draft. Editing email and switching Journal → Settings retained the unsaved edit without changing SQLite. A later explicit Return saved it. Quit exited only the isolated app. Full native suite on this final source passes **232 tests (133 core + 99 app)**; the focused feedback suite passes 23 (`stage4-feedback-return-fix.log`). The native email adapter fixes Return submission, prevents implicit Save on blur and preserves Undo/Redo/status through unchanged focus changes.

### Limits and test isolation

Full VoiceOver announcement reception, full keyboard traversal/Copy-button focus with macOS Keyboard navigation, integrated clipboard-rejection focus, and final light/dark/narrow visual acceptance are **unverified**. The implementation Mac has Keyboard navigation disabled; tests did not change that preference. Native editor harnesses establish selection, geometry, Undo/Redo and disabled-state behavior, not the complete screen-reader workflow or an app-wide Redo command. Launch at Login and Slack remain Stage 5. Developer ID/notarization remains unavailable; the published preview is unchanged.

An early UI test copy shared the `DeepWork` executable name. After automation Quit/relaunch, it opened the normal Application Support store and the personal timer was found paused. The original app was restored and its existing session resumed; no journal records were deleted or fabricated. The test setup was corrected to a distinct executable and bundle, with an explicit Debug data override on every launch and ownership-lock verification. A later Launch Services launch blocked opening a Downloads-based fixture; its stack showed the file open, so testing moved to a temporary-directory fixture instead of changing system permissions. Test app edits and exports were kept separate from personal history. README and AGENTS now require this isolation.

### Hosted Stage 4 verification

The initial [PR #3 run 39246280425](https://github.com/lukin-io/deep-work/actions/runs/39246280425) exposed a test synchronization issue on macOS 15: the input-limit fixture waited for the model's clipped text, then asserted the native editor before SwiftUI had rendered that text. The corrected wait requires both observable values; the original maximum-length and replacement assertions remain. This changes the fixture, not production behavior. The corrected local `./scripts/test.sh --filter Feedback` passes all 23 affected native tests, plus platform/icon checks (`stage4-feedback-ci-render-wait.log`).

[Corrected PR run 39246777987](https://github.com/lukin-io/deep-work/actions/runs/39246777987) tested source head `65437072a80f87ca02ffe8d5f68bcb22a495559c` as merge preview `60a392f4a6ee5364a361e008c1582d88b37241ea` against `main` at `e2cee410dfe1e5fe87e54c6a186416a2ab453425`.

| Hosted environment | Native / Xcode result |
| --- | --- |
| macOS 15.7.9, arm64, Xcode 16.4, SDK 15.5 — job `118041112584` | All 232 Swift tests pass; strict concurrency compilation and Xcode Release build pass. |
| macOS 26.6.2, arm64, Xcode 26.6, SDK 26.5 — job `118041112256` | All 232 Swift tests pass; strict concurrency compilation and Xcode Release build pass. |

Each runner also passes 22 CI policy regressions, 4 platform checks, 12 icon checks and 38 release-publication regressions. These hosted results verify the supported toolchains; they do not establish the remaining interactive accessibility acceptance or local full-Xcode availability.

Package job `118042957194` also **passed**: optimized arm64/macOS 15+ build, archive verification, 20 release-policy tests and 17 actual archive regressions. The temporary `macOS-release` Actions artifact is 2,254,825 bytes (artifact ID `12184600250`), with the verified icon, ad hoc signature, license, source metadata and checksums. Tag-only publication was correctly **skipped**. This is a CI artifact, not a new GitHub Release or a notarized app.

At the Stage 4 handoff, PR #3 remained open against `main`. The follow-up documentation commit recorded the verified production/test revision above without changing app code or tests. Its later authorized merge is recorded below.

## Stage 5 — Native services — October 19, 2026

### Starting revision and scope

PR #3 head `113a6c42b1f982eecff96562dd6748b0136e7098` passed [CI run 39247749536](https://github.com/lukin-io/deep-work/actions/runs/39247749536). It was then merged into `main` as `731e0e71d7d82993e1672de0a7b2df9fffd445c9`. After fetching and fast-forwarding local `main`, `codex/native-services-stage-5` was created from that merge. This stage adds native menu commands, actual login registration, Slack authorization/status adapters and SQLite recovery receipts. The owner chose to configure the Slack app afterward; no live Slack credentials, consent or remote status changes are claimed.

### Local native verification

Environment: Apple Silicon, macOS 27.0.1, Swift 6.4 and `/Library/Developer/CommandLineTools`. Full Xcode remains unavailable locally. The complete suites, strict production compilation and packaging pass; a project/plist lint is not an Xcode build.

| Check | Result |
| --- | --- |
| `./scripts/test.sh` | 335 native Swift tests: 144 core + 191 app; 4 platform and 12 icon checks pass. |
| `swift build -Xswiftc -strict-concurrency=complete -Xswiftc -warnings-as-errors` | Pass; the existing CLT linker search-path warnings are separate from Swift diagnostics. |
| `./scripts/build-app.sh` | Pass; produces the ad hoc signed `.build/Deep Work.app` and verifies its native icon. |
| `python3 scripts/generate-xcode-project.py` | Explicit project references regenerated for 26 app sources and 10 core test sources. |
| `plutil -lint DeepWork/Resources/Info.plist DeepWork.xcodeproj/project.pbxproj` | Both pass. |
| `git diff --check` and unchanged `reference/` / initial JSON | Pass. |

Ignored logs: `.build/stage5-full-tests.log`, `stage5-strict-build.log`, `stage5-app-build.log` and the focused `stage5-*-tests.log` files. No product data or credentials are included in test evidence.

- **Menus:** real AppKit command dispatch and native editor responders cover Settings from running/paused/hidden windows, retained window/model identity, Quit guards and Undo/Redo without implicitly saving feedback. Hostless runners cannot establish the application's key-window menu dispatch; compiled shortcuts were checked separately below.
- **Login items:** native status mapping, approval, revocation, missing services, registration/unregistration failure, concurrent requests and cancellation are exercised through the injectable ServiceManagement boundary. Real SQLite integration covers stale stored Booleans, status refresh, successful/failed writes, unsaved/saved draft preservation, delayed registration and Quit draining. Automated tests never register the person's real app as a login item.
- **Authentication and Keychain:** random PKCE/state, S256, exact callback/state validation, cancellation, scopes, user/workspace identity, null/malformed errors, HTTP/offline failures, 429 cooldown and rotating-token serialization are covered. An isolated actual Keychain service verifies create/read/atomic replacement/delete. Injected HTTP responses establish adapter behavior, not real Slack consent or API acceptance. Debug fixture directories receive separate Keychain namespaces.
- **Slack ownership:** meaningful transitions only, paused-focus retention, break/end/disconnect/Quit restoration, expired prior statuses, detected manual changes, pre-existing identical status, write-ahead storage failure, ambiguous remote writes, crash recovery, missing/mismatched accounts, delayed writes and retry are covered. Integration tests combine the actual timer, SQLite and a native window with a recorded Slack client. Local accounting remains usable during service failures.
- **SQLite migration:** schema 1 → 2 preserves journal/settings/checkpoint bytes, creates one validated ownership document, rolls back schema conflicts, and retries safely. Missing/malformed/future receipt documents are preserved and surfaced without disabling valid journal/settings stores. Future database schemas remain untouched. Failed receipt clearing rolls back. Downgrading to Stage 1–4 binaries is unsupported.
- **Quit regressions:** failed Quit does not reapply Slack while the user is still choosing Keep Open versus Quit Without Saving; only explicit Keep Open reprojects the paused focus. Rotated credentials whose Keychain commit failed remain in memory for retry; Quit flushes that pending commit and stays cancellable on failure. With no receipt or pending commit, a locked credential store does not unnecessarily block Quit.

### Compiled-app observations and isolation

The disposable bundle used executable `DeepWorkStage5Acceptance`, bundle ID `app.deepwork.mac.stage5acceptance` and a temporary `DEEP_WORK_DATA_DIR` embedded in its Debug `LSEnvironment`. It was installed under `~/Applications` for ServiceManagement testing. The open ownership lock was verified inside the fixture before edits and after relaunch; personal storage and running sessions were not used. The fixture copy removed its OAuth URL registration to avoid claiming the production callback scheme.

- Command-comma opened the existing Settings tab; Command-0 returned to Focus. Command-Z removed the typed feedback draft and Shift-Command-Z restored it using the native menu responder chain. Switching tabs preserved the unsaved draft.
- The actual `SMAppService.mainApp` registration succeeded and the switch showed enabled. Unregistering succeeded and showed disabled. Both operations preserved the unsaved draft. Inspecting real SQLite afterward confirmed `launchAtLogin=false` and the saved feedback message still empty. The test item was unregistered before Quit.
- On this ad hoc isolated bundle, the native status was `notFound` before registration and again after a later relaunch, even under Applications. Registration still succeeded. This exposed misleading “unavailable/move to Applications” copy; the regression and corrected retry wording are recorded below. Actual logout/login, approval and external revocation were not exercised.
- Unconfigured Focus shows Preview, a disabled Connect Slack control and “Slack is not configured in this build. No status changes are made.” The card keeps the approved status preview and makes no restoration claim.
- A disposable 60-minute focus continued through Settings and Command-W/Show Focus navigation. The automation's observation can reopen a hidden window, so this check proves continued timing, not a new independent hidden-display measurement; existing status-button/hidden-checkpoint integration and prior compiled lifecycle evidence remain applicable.
- Command-Q exited the isolated process. Relaunch opened Journal with the same paused session and 28 seconds of focus, without counting downtime; Settings restored only the explicitly saved empty draft and kept login Off. The isolated process was then quit again.

### Remaining acceptance and next stage

**Stage 5 is IN PROGRESS.** G-002 is newly accepted; total **105/137**. F-027–F-029 are BLOCKED until the owner configures the public Slack Client ID and performs sign-in/live remote checks in [SLACK_SETUP.md](SLACK_SETUP.md). S-003–S-005 remain IN PROGRESS until actual enable/disable login cycles, approval and externally changed OS state are exercised. This session does not log out the active Mac user. Full screen-reader reception, keyboard traversal, appearance/layout and physical sleep/wake remain unverified.

**Stage 6 is the one remaining implementation stage**, alongside these Stage 5 checks: keyboard/VoiceOver, light/dark/narrow layouts, background/recovery and final cross-feature regressions. Developer ID signing/notarization remains unavailable. No release or published download is produced by this PR; the existing preview remains Stage 1/2.

The `.notFound` copy regression failed before the fix (`.build/stage5-login-not-found-before.log`). Corrected wording describes the observed missing login item and offers enabling again; the switch remains actionable. The focused suite then passed **36 login tests**, plus 4 platform and 12 icon checks (`stage5-login-not-found-fixed.log`). It covers successful registration from both notRegistered and notFound, real SQLite status persistence and the exact new caption. The final full suite includes this regression.

The final rebuilt acceptance app displayed the corrected caption through its native accessibility tree. After unregistering the disposable login item and quitting, the test bundle was moved back into ignored `.build/`; no acceptance login item remains enabled.

**Login accessibility regression:** before the fix, the compiled `dw-launch-login` switch exposed the helper but omitted “Launch at Login” from its AX description. Adding an explicit native accessibility label preserves the helper/status and Off value while exposing `Description: Launch at Login`. Reproduce by opening Settings with Command-comma and inspecting that switch in the compiled app. This case passed after rebuilding; the 36 focused login tests and native app build also pass (`stage5-login-label-tests.log`, `stage5-login-label-build.log`). Hostless SwiftUI AX trees are unavailable, so this regression uses a recorded compiled-app acceptance case rather than claiming automated screen-reader coverage.
