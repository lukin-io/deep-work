# Deep Work for macOS

A native SwiftUI/AppKit application with the Stage 1 foundation, Stage 2 focus timer, Stage 3 Journal and work schedules, and Stage 4 CSV export and local feedback tools. The specification defines **137 implementation items**; `IMPLEMENTATION_CHECKLIST.md` is the sole progress tracker and records remaining native acceptance checks.

## Download the app

[Download Deep Work 0.1.0 preview 1](https://github.com/lukin-io/deep-work/releases/download/v0.1.0-preview.1/Deep-Work-v0.1.0-preview.1-macOS-arm64.zip), extract the ZIP, and move **Deep Work.app** to Applications. Read the [release notes and checksums](https://github.com/lukin-io/deep-work/releases/tag/v0.1.0-preview.1), or browse [all releases](https://github.com/lukin-io/deep-work/releases). Requires **Apple Silicon (M1 or later) and macOS 15 or later**. Intel Macs are unsupported. GitHub's automatic Source code ZIP is for developers, not an installed app.

Previews are **ad hoc signed and unnotarized**; macOS may block first launch. Only open a build you trust, following [Apple's app-opening guidance](https://support.apple.com/en-us/102445). Stable notarized releases are not yet available. Each release lists its tested platforms and known limitations; macOS 15+ is the deployment target, not a claim that every OS version was tested.

The published first preview contains **Stage 1/2 only**; Stage 3/4 source changes require a local build until a new release is published. The first preview passed [release CI and public-download verification](https://github.com/lukin-io/deep-work/actions/runs/39108209226). Download `SHA256SUMS` and `release-metadata.json` alongside the app ZIP and verify them with `shasum -a 256 -c SHA256SUMS`. The metadata records the source commit and build configuration. Quit an older running copy before replacing it; user data stays in Application Support.

## TODO

- [ ] **This Mac has no Developer ID signing identity.** Configure an Apple Developer Program team's **Developer ID Application** certificate and its matching private key, either in this Mac's signing keychain or a protected CI signing environment. The local check is `security find-identity -v -p codesigning`; it currently reports zero valid identities. Never commit certificates, private keys or passwords.
- [ ] Implement and verify the stable distribution path: hardened runtime, secure timestamp, notarization with `notarytool`, stapling on the app before the final ZIP, and Gatekeeper checks. Current automation intentionally publishes only clearly labelled unnotarized previews.
- [ ] Complete the remaining physical Mac acceptance checks, including VoiceOver/keyboard access, light/dark appearance, menu-bar clicking and sleep/wake. Product acceptance stays in `IMPLEMENTATION_CHECKLIST.md`.

Read the [10-point Apple development and distribution guide](docs/MACOS_RELEASE_GUIDE.md) for requirements, conditional App Store rules, current gaps and official sources. This TODO covers release readiness; it does not replace the product progress tracker.

## Start here

| File | Use it for |
| --- | --- |
| [AGENTS.md](AGENTS.md) | Required development workflow, Swift/Apple practices, tests, verification, and release rules |
| [CHANGELOG.md](CHANGELOG.md) | One consolidated change summary per PR or stage, with release links when available |
| [Apple development and distribution guide](docs/MACOS_RELEASE_GUIDE.md) | Detailed Apple guidance, Human Interface Guidelines, official sources, and applicability to development or distribution; consult relevant sections as required by `AGENTS.md` |
| `DEEP_WORK_SPECIFICATION.md` | Full behavior reference, all controls and states, data/CSV rules, native decisions, build order and 29 integration acceptance scenarios |
| `IMPLEMENTATION_CHECKLIST.md` | Editable progress by view → feature → element, with status, owner, evidence and notes |
| `implementation-tracker.json` | Initial structured import for your issue tracker or coding tool |
| `reference/deep-work-preview.html` | Current self-contained visual/interactive reference; open locally in a browser |
| `reference/journal-app.js` | Existing runtime behavior to translate into Swift models and services |
| `reference/journal-report-core.js` | Exact reporting and calendar arithmetic |
| `reference/journal-report-core.test.cjs` | Ten existing reporting behavior tests to port as native test cases |
| `REFERENCE_MANIFEST.json` | Source hashes and documentation-coverage results |

The native project is `DeepWork.xcodeproj`, with a shared `DeepWork` scheme. `Package.swift` builds the same production sources and native tests without third-party dependencies. The approved HTML remains a visual/behavior reference, not a native implementation. See [native decisions](docs/NATIVE_DECISIONS.md) and [verification evidence](docs/VERIFICATION.md) for implementation boundaries.

## Coverage and baseline

| Area | Items |
| --- | ---: |
| Shared shell | 14 |
| Focus | 29 |
| Journal | 54 |
| Journal → Work schedule | 19 |
| Settings | 21 |
| **Total** | **137** |

The three top-level tabs are **Focus, Journal, Settings**. Work schedule stays within Journal. The documentation maps **122/122 static DOM IDs**, **54/54 interactive controls**, every control without an ID, and the generated chart, table and schedule elements. Original source bytes were copied unchanged. The previous frozen two-view v1 was not edited; the bundled reference is the later three-view version that includes the requested Settings view.

## Tracking convention

Use `IMPLEMENTATION_CHECKLIST.md` as the manual source of progress. Change TODO to IN PROGRESS, BLOCKED, or DONE and fill in owner/evidence/notes. Check a box only when the item is DONE. A feature is accepted when all child items are accepted. Keep IDs such as F-016 or S-019 in commits and tests so implementation can be traced to its behavior.

The JSON is an initial import snapshot, not a live mirror of the Markdown checklist. Choose one progress source after importing it into another tool. The prototype's Working/Simulated/Decorative status stays separate from native completion.

## Stage 3 — Journal and work schedule

Stage 3 was merged through [PR #2](https://github.com/lukin-io/deep-work/pull/2) after its CI passed. The Journal now provides:

- Day, Week and custom Range reports with exact clipped focus time, completed cycles and days with focus.
- Daily/weekly activity bars, full-period drilldown, a native four-column table and 12-row pagination.
- Separate example data, live/paused timer observations and restored history from SQLite.
- A nested work-schedule editor: chosen weekdays, Any day, rotating shifts, week start, reporting-day cutoff and a 14-day preview. Save waits for SQLite; failure retains the draft. Cancel discards edits, and tab changes retain them.

The [Stage 3 plan](docs/STAGE_3_PLAN.md) records the original scope; [native verification](docs/VERIFICATION.md#stage-3--journal-and-work-schedule--october-19-2026) and the checklist record actual results and remaining keyboard/VoiceOver checks. Existing data needs **no schema migration**. Stage 4 adds the shared export and feedback behavior below.

## Stage 4 — CSV export and feedback

Journal **Export CSV** saves every row in the current report, including rows on other pages. Settings **All Sessions** exports actual history and a positive live observation; **Current Journal Report** uses the retained Journal range and actual/example source. A native Save panel chooses the destination. Cancel makes no success claim; a write failure remains visible. Exporting does not pause the timer. Quit cancels an untouched panel and waits for an accepted file write; failed writes keep the app open for retry.

Both export paths use the same 13-column CSV contract: UTF-8 BOM, quoted fields, CRLF separators, precise focus seconds and local timestamps with UTC offsets. Example exports are explicitly labelled. CSV is a report, not a full database backup.

Feedback supports validated optional email, a 5–5,000 UTF-16-unit message, multiline editing and Undo/Redo. **Save Draft** commits to SQLite; **Copy Feedback** copies the current form without changing the saved draft. Nothing is sent. Return from the email field or Command-Return submits Save Draft; Return in the message inserts a newline. Relaunch restores only the explicitly saved draft. Launch at Login and Slack remain Stage 5 work.

No dependency, permission prompt or schema migration is added. See [Stage 4 verification](docs/VERIFICATION.md#stage-4--csv-export-and-feedback--october-19-2026) for native tests, compiled-app checks and remaining keyboard/VoiceOver acceptance. One consolidated entry is kept in [CHANGELOG.md](CHANGELOG.md).

## Important implementation boundaries

- The native menu-bar timer and close/reopen behavior are implemented. Real Launch at Login and Slack authorization/status changes remain later milestones.
- The approved feedback surface contains **Save Draft** and **Copy Feedback**. Save Draft persists explicitly to SQLite; Copy Feedback uses the native clipboard without saving edits. No Send button or delivery destination exists.
- CSV is a session report export, not a lossless backup or import format.
- The three dashboard metrics are Focus time, Completed cycles, and Days with focus. No averaging metric is implemented in this baseline.
- The detailed specification records unresolved native policies and small prototype quirks so they can be resolved deliberately without accidentally redesigning the app.

## Build, test, and run locally

Requires Swift 6 or later from Xcode 16+ or current Command Line Tools. The app requires **Apple Silicon (M1 or later), macOS 15+**; local verification used **macOS 27.0.1, Apple Silicon, Swift 6.4**. Intel Macs and macOS versions before 15 are unsupported. Tests use the same minimum macOS version.

Check the selected developer tools first:

```sh
xcode-select -p
swift --version
```

If the Command Line Tools are missing, run `xcode-select --install` and finish Apple's installer before building. Full Xcode is optional for the verified command-line workflow below; install Xcode 16+ to use its project editor and scheme runner. No Homebrew packages, database server, third-party Swift packages, or manual SQLite setup are required.

From this project directory, run these commands in order:

```sh
./scripts/test.sh
./scripts/build-app.sh
open ".build/Deep Work.app"
```

`test.sh` runs the native Swift Testing suites, including actual AppKit window integration. It resolves the Testing macro plugin shipped with standalone Command Line Tools; no dependency download is needed. It checks the Apple Silicon/macOS 15 build settings and rejects unsupported local build hosts. It also rejects an incomplete test run even if the hostless runner exits with status 0. The AppKit suites briefly create, minimize, zoom, hide, and reopen native test windows and exercise real status-item buttons. They serialize access to AppKit’s shared application state. `build-app.sh` compiles and creates an ad hoc signed `.build/Deep Work.app` for local use. It is not a notarized distribution build.

For focused Stage 4 checks:

```sh
./scripts/test.sh --filter 'ReportCSVExporterTests|CSVFileExportServiceTests|ExportIntegrationTests|FeedbackTests|FeedbackClipboardTests|FeedbackIntegrationTests|FeedbackPresentationTests'
swift build -Xswiftc -strict-concurrency=complete -Xswiftc -warnings-as-errors
plutil -lint DeepWork/Resources/Info.plist DeepWork.xcodeproj/project.pbxproj
```

For manual acceptance with disposable data, **quit the normal app first**, then launch the Debug executable explicitly:

```sh
test_data_dir="${TMPDIR%/}/deep-work-manual"
mkdir -p "$test_data_dir"
DEEP_WORK_DATA_DIR="$test_data_dir" \
  ".build/Deep Work.app/Contents/MacOS/DeepWork"
```

Reuse the same test directory and launch command on every test relaunch: opening the app normally uses the real Application Support store. The override is Debug-only. For simultaneous automated UI testing, use a separate test bundle with a distinct executable and bundle identifier, preserve the override for every launch, and verify its store ownership lock points inside the fixture directory before editing. Never quit or alter a running personal session for acceptance testing.

The approved app icon has one source: `DeepWork/Resources/Assets.xcassets/AppIcon.appiconset`. Xcode compiles that catalog; the command-line build packages its unchanged PNGs with the macOS `iconutil` tool and validates all ten representations. Generated ICNS files stay in build output. No image editor or extra setup is needed. See [icon organization and provenance](docs/APP_ICON.md) for replacement steps and the preserved local originals. The test script also runs native icon packaging checks. To check only the icon or an existing built bundle:

```sh
./DeepWorkTests/Icon/test-app-icon.sh
swift scripts/verify-app-icon.swift ".build/Deep Work.app" \
  DeepWork/Resources/Assets.xcassets/AppIcon.appiconset
```

After editing source, run the tests and build again. Quit the previous app before opening the rebuilt bundle, so the running process uses the new code. Keep this README current whenever setup, build, test, run, or data-migration commands change.

With full **Xcode 16+** installed:

```sh
open DeepWork.xcodeproj
```

Select scheme **DeepWork**, destination **My Mac**, then **Run** (Command-R). Command-U runs the scheme's core tests; `./scripts/test.sh` also covers app-model and AppKit integration tests. The project uses local ad hoc signing. If adding app or core test source files, regenerate explicit Xcode file references with `python3 scripts/generate-xcode-project.py`.

If Xcode is installed but the selected developer directory is still Command Line Tools, select it first (adjust the path if you installed Xcode elsewhere):

```sh
sudo xcode-select --switch /Applications/Xcode.app/Contents/Developer
sudo xcodebuild -runFirstLaunch
```

The corresponding Xcode build command is:

```sh
xcodebuild -project DeepWork.xcodeproj -scheme DeepWork \
  -configuration Debug -destination 'platform=macOS' build
```

**Local full Xcode remains unavailable:** `xcode-select -p` returns `/Library/Developer/CommandLineTools`; local `xcodebuild` requires an Xcode installation. Separately, [Stage 3 hosted CI passed](https://github.com/lukin-io/deep-work/actions/runs/39236029448) all 170 native tests and Apple Silicon Xcode Release builds on **macOS 15/Xcode 16.4/SDK 15.5** and **macOS 26/Xcode 26.6/SDK 26.5**, followed by optimized packaging and archive tests. CI uses this project-build check; the downloadable app is packaged and signed separately by the release script:

```sh
xcodebuild -project DeepWork.xcodeproj -scheme DeepWork \
  -configuration Release -destination 'platform=macOS' \
  -derivedDataPath .build/Xcode CODE_SIGNING_ALLOWED=NO build
```

Local, hosted, and distribution verification are recorded separately in [VERIFICATION.md](docs/VERIFICATION.md).

## Git repository

The GitHub repository is [lukin-io/deep-work](https://github.com/lukin-io/deep-work), with `main` as the pull-request target. This checkout uses `origin` for that repository. Generated builds, test fixtures under `.build/`, Xcode user state, and local icon delivery archives are ignored; the approved handoff, source, tests, shared project/scheme, and documentation are versioned.

For a new checkout:

```sh
git clone https://github.com/lukin-io/deep-work.git
cd deep-work
```

Implement changes on a feature branch, run the relevant verification above, then commit and push it for a pull request targeting `main`:

```sh
git fetch origin
git switch -c feature/your-change origin/main
git status --short --branch
git diff --check
git add <changed-files>
git commit
git push -u origin HEAD
```

Follow `AGENTS.md` for tests, progress evidence, and commit/PR wording. Use GitHub's pull-request UI or an authenticated GitHub client after pushing; no GitHub CLI is required to build or test.

Pushing requires GitHub authentication. This development machine uses an existing authorized SSH key; its `origin` is `git@github.com:lukin-io/deep-work.git`. To use an already configured GitHub SSH key after an HTTPS clone:

```sh
git remote set-url origin git@github.com:lukin-io/deep-work.git
git remote -v
```

## GitHub Actions CI

The implemented pipeline is [`.github/workflows/release.yml`](.github/workflows/release.yml). PRs targeting `main`, pushes to `main`, and version tags run it:

| Job | Actual checks |
| --- | --- |
| Native tests — macOS 15 / Xcode 16.4 / SDK 15.5 | Apple Silicon environment validation; CI policy, model, SQLite, AppKit, platform, icon and publisher tests; complete concurrency checking with Swift warnings as errors; plist/project lint; Xcode Release build |
| Native tests — macOS 26 / Xcode 26.6 / SDK 26.5 | The same native checks on the newer supported OS/toolchain, still arm64 only |
| Package — macOS 15 / Xcode 16.4 | Wait for both native jobs, build the optimized arm64 app, verify its exact deployment floor and contents, run archive regressions, retain the ZIP/checksums/metadata as temporary artifacts |
| Publish — version-tag pushes only | Verify annotated tag, source and `main` ancestry; upload a draft prerelease, verify downloaded bytes, publish, then verify public downloads without credentials |

Every job explicitly selects `DEVELOPER_DIR`; `scripts/verify-ci-environment.sh` rejects unexpected architecture, OS, Xcode, SDK or Swift selection. Update the pinned toolchain and tests together when runner images change. The [official macOS 15 image](https://github.com/actions/runner-images/blob/main/images/macos/macos-15-arm64-Readme.md) and [macOS 26 image](https://github.com/actions/runner-images/blob/main/images/macos/macos-26-arm64-Readme.md) list installed versions. Only superseded PR runs cancel automatically; a tag publication runs to completion. Actions are pinned to commit SHAs, and only the tag-only publication job has repository write permission.

For CI/release-script changes, run the native checks above plus:

```sh
python3 DeepWorkTests/Build/test-ci-policy.py
python3 DeepWorkTests/Release/test-publish-release.py
./DeepWorkTests/Release/test-release.sh
bash -n scripts/verify-ci-environment.sh scripts/package-release.sh scripts/publish-release.sh
```

This pipeline is verified preview infrastructure. A production signed/notarized job remains gated by the TODO above: provision a protected signing environment with a temporary keychain, sign with Developer ID and Hardened Runtime, notarize/staple, verify Gatekeeper, and only then package the final downloadable ZIP. The current workflow never treats missing Apple credentials as a successful stable release. Protect `main` and release tags in GitHub rulesets when managing collaborators; workflow checks do not themselves configure repository access policy.

## Build and publish a preview release

The release pipeline uses the native macOS tools already described above, plus Python 3 and Git. GitHub-hosted runners include these tools and the GitHub CLI. No local GitHub CLI or long-lived upload token is needed: pushing an annotated preview tag triggers `.github/workflows/release.yml` with its scoped job token.

Before tagging, prepare `docs/releases/<tag>.md`, commit the changes and release notes, ensure the numeric version in `DeepWork/Resources/Info.plist` matches the tag, and require the PR's native test/package checks to pass. Preview tags follow `vX.Y.Z-preview.N`, with N starting at 1. **`v0.1.0-preview.1` is the first release; do not recreate or move it.** The next commands use `v0.1.0-preview.2` as an example: first fetch tags and choose the next unused version and a positive local build number.

```sh
git fetch origin --tags
git tag --list 'v0.1.0-preview.*'
release_tag='v0.1.0-preview.2' # Replace if already used; match the committed notes.
release_build=2
./scripts/test.sh
python3 DeepWorkTests/Release/test-publish-release.py
./DeepWorkTests/Release/test-release.sh
./scripts/package-release.sh "$release_tag" "$release_build"
./scripts/verify-release.sh ".build/releases/$release_tag" "$release_tag" "$(git rev-parse HEAD)"
./DeepWorkTests/Release/test-release.sh ".build/releases/$release_tag" "$release_tag"
```

The package script requires a clean committed checkout, builds arm64 with Swift's **Release** configuration, generates the icon, signs the app ad hoc, validates an extracted archive, and writes the ZIP/checksums/metadata to `.build/releases/<tag>/`. It refuses an existing output directory to protect earlier artifacts. A local package does not upload anything and is not a published release. The release build ignores the debug-only data-directory override.

Create a new annotated tag at the exact verified commit and push that tag, using the next unused preview number for subsequent releases:

```sh
git tag -a "$release_tag" -m "Deep Work $release_tag"
git push origin "$release_tag"
```

Do not repeat those commands once the version exists or move a published tag. New releases must already belong to `origin/main`; the publisher refreshes that ref and verifies ancestry before creating a draft and again before publication. The initial preview was created before PR #1 merged and remains immutable.

The workflow runs native tests on Apple Silicon, checks the Xcode Release build, builds and tests an arm64 package, and creates a draft GitHub prerelease. It uploads the app ZIP, checksums and metadata, downloads and verifies them, then publishes with Latest disabled and verifies the public downloads without authentication. PR runs only validate and retain temporary Actions artifacts; they cannot publish. CI assigns its run number as the packaged build number.

Failure before publication retains any created draft. If GitHub does not confirm the publication operation, inspect the release state before retrying. If publication succeeds but public-download verification fails, the release remains published and its download is reported as unverified; nothing is deleted or replaced. Fixes use a new version. Read [AGENTS.md](AGENTS.md) for release rules and [verification evidence](docs/VERIFICATION.md) for actual results.

Stable tags are rejected until Developer ID signing, hardened runtime, timestamping, notarization, stapling and Gatekeeper verification are implemented. No signing identities are available on the current development machine. Apple's [distribution packaging](https://developer.apple.com/documentation/xcode/packaging-mac-software-for-distribution) and [notarization guidance](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution) define that future distribution path.

## Local data and current behavior

- Journal opens on launch. Focus, Journal, and Settings share one app-owned model. The red close button or Command-W only hides the main window: running timers, phase transitions and SQLite checkpoints continue; already paused timers stay paused. The native menu bar shows the running countdown and **Deep work** or **Break**. Click that timer to bring the same window to the front on Focus without restarting; File → Show Deep Work (Command-0) does the same. Hide (Command-H) and Minimize also preserve timing.
- Full Quit (Command-Q) pauses, saves, and finishes queued writes before exiting. Relaunch restores the unfinished phase paused until Resume. If saving fails, Quit offers **Keep Open** by default or an explicit **Quit Without Saving**. Closing the main window never waits for disk writes or forces a pause; storage failures remain available in the retained app state and visible on reopening.
- Valid duration preferences, Repeat, the saved work schedule, session records/checkpoint, launch preference, and explicitly saved feedback drafts use SQLite at `~/Library/Application Support/app.deepwork.mac/DeepWork.sqlite`. Foundation resolves the user-domain Application Support URL. Each journal record has its own database row; raw segments are retained without rounding.
- Writes run in order off the UI thread and use transactions. Existing interim JSON files are migrated without deleting the originals; unsupported/corrupt data is preserved and reported. WAL/SHM files may accompany the database; do not treat a copy of only the main file while the app runs as a backup.
- Focus supports the approved presets and custom whole minutes 1–480, Repeat, Pause/Resume, Take break, Skip/Finish break, Start again, and End session. Only active focus segments count; zero-time abandoned cycles are discarded. Full duration creates one Complete record; an early exit retains positive time as Partial.
- While a cycle is running, elapsed time includes background operation and Mac sleep. Hiding the main window does not interrupt timing; only explicit Pause or Quit pauses it. Wall-clock changes do not alter accounting. Closed-process downtime never counts: relaunch restores unfinished focus/break paused at its last committed remainder, with explicit Resume required. Checkpoints are saved about every five seconds and at actions/boundaries; Force Quit or a crash can lose the latest uncommitted interval.
- One process owns each data directory through an advisory lock. Normal `open` reuses the app; an independent second process targeting the same store is refused. Do not remove `DeepWork.owner.lock` while an owner is running.
- Save Draft persists feedback; unsaved edits survive tab changes but intentionally do not survive Quit. Report selection and unsaved schedule drafts remain transient as specified. No feedback is sent.
- Journal reports use half-open `[From, Until)` bounds in the current device time zone. Range text accepts `YYYY-MM-DDTHH:mm`; invalid, reversed, nonexistent local times or ranges exceeding 3,660 elapsed days show an error and clear the report. Above 93 elapsed days, grouping switches to By week and stays there until changed. Today leaves Range for Day without erasing its inputs.
- Schedules affect reporting only. They never start timers or discard off-day focus. Changing the schedule or time zone reinterprets raw history without rewriting session timestamps. An idle cutoff wakeup keeps Today and the draft preview current even when no timer runs.
- Examples are generated once per launch, clearly labelled and never written to SQLite. Starting a real cycle selects actual history. Report period/range/grouping/source, paging and unsaved schedule drafts are transient; saved schedules survive Quit/relaunch.
- CSV export and clipboard copy are implemented in source. Login registration and Slack integration remain unavailable; their controls do not simulate success.

Use the isolated Debug launch steps in [Build, test, and run locally](#build-test-and-run-locally) for empty data, relaunch, migration and failure checks. Release builds ignore the override.

## Native milestone verification

Stage 4 passes **232 native Swift tests (133 core + 99 app)**, 4 platform checks and 12 icon checks locally, plus strict concurrency compilation and app packaging. Compiled-app CSV Save/Cancel, full-report export, feedback Return/Command-Return, clipboard and SQLite restoration checks pass. The [verification record](docs/VERIFICATION.md#stage-4--csv-export-and-feedback--october-19-2026) separates local results, compiled UI observations, hosted CI and unverified keyboard/VoiceOver/visual checks.

Run all native tests, or select the relevant suites:

```sh
./scripts/test.sh
./scripts/test.sh --filter TimerEngineTests
./scripts/test.sh --filter JournalReportTests
./scripts/test.sh --filter WorkScheduleDraftTests
./scripts/test.sh --filter JournalIntegrationTests
./scripts/test.sh --filter JournalPresentationTests
./scripts/test.sh --filter WorkSchedulePresentationTests
./scripts/test.sh --filter NativeApplicationTests
./scripts/test.sh --filter ClosePersistenceTests
swift build -Xswiftc -strict-concurrency=complete -Xswiftc -warnings-as-errors
python3 scripts/generate-xcode-project.py
plutil -lint DeepWork/Resources/Info.plist DeepWork.xcodeproj/project.pbxproj
codesign --verify --strict ".build/Deep Work.app"
```

The engine tests use an injected clock for exact deadlines, multi-cycle delays, pauses, clock changes and recovery. SQLite integration verifies real persisted records/checkpoints; AppKit integration exercises windows, tab focus and status-button actions. Close/Quit regressions cover automatic hidden ticking, slow/failed saves, same-window reopening, and Quit-only pause/recovery. Local full Xcode, physical sleep/wake, and complete VoiceOver/light/dark acceptance remain separately identified in the verification record.

For a short manual check with the isolated data command above: choose Custom → 1 minute for both phases, turn Repeat off, and start. Press Command-W: the menu-bar timer must keep counting with the current phase name. Click it to bring Focus to the front at the current remaining time. Repeat with the red close button during the break. One complete 60-second focus record should precede Cycle complete after its break. An already paused cycle must remain paused across close/reopen. Quit with an unfinished phase and relaunch using the same isolated directory: it must restore paused with the same remainder. Open Journal during focus and pause: time and the Live/Paused row must grow only during active focus; completion appears exactly once.

For Journal acceptance in the same isolated store:

1. Start empty: verify the Example data banner; switch to your journal and use Start a focus cycle without starting automatically.
2. Select Day/Week/Range, edit both raw bounds, try equal/invalid bounds, then restore a valid range. Compare metrics with chart/rows; select a bar to open its full day/week. More than 12 matches shows pagination without changing totals.
3. Open Schedule, try all modes, blank/fractional shift counts, zero weekdays and cutoff `04:00`. Invalid active fields disable Save and clear the preview. Switch tabs to retain edits; Cancel restores the saved schedule. Save, Quit and relaunch to verify persistence.
4. With macOS **System Settings → Keyboard → Keyboard navigation** enabled by the tester, traverse chart buttons and weekdays, activate with Space, verify focus survives live updates and returns after Cancel/Save. Repeat with VoiceOver, light/dark appearance and a narrow window. Automated checks never change system preferences; unperformed checks remain unverified.

Native button focus follows macOS Keyboard navigation preferences. Tab-strip arrows/Home/End retain focus on the tab strip. No test changes the user's system preferences. The progress view reads the system Reduce Motion environment and disables interpolation when requested.

## Optional reference test run

If Node.js is available, the existing pure JavaScript reporting cases can be run from this folder with:

```sh
node --test reference/journal-report-core.test.cjs
```

These are behavior references for the Swift port. They are not native XCTest results. The browser automation tests are not bundled because they depend on the previous preview QA environment.
