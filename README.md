# Deep Work for macOS

A native SwiftUI/AppKit application implementing the Stage 1 foundation and Stage 2 focus timer of the approved Deep Work handoff. The specification defines **137 implementation items**; `IMPLEMENTATION_CHECKLIST.md` is the sole progress tracker. Journal reporting and work schedules are the next milestone.

## Download the app

Built apps are published under [GitHub Releases](https://github.com/lukin-io/deep-work/releases). Select a preview and download **Deep-Work-<tag>-macOS-universal.zip** from Assets, extract it, and move **Deep Work.app** to Applications. The universal app includes Apple Silicon and Intel executables. GitHub's automatic Source code ZIP is for developers, not an installed app.

Previews are **ad hoc signed and unnotarized**; macOS may block first launch. Only open a build you trust, following [Apple's app-opening guidance](https://support.apple.com/en-us/102445). Stable notarized releases are not yet available. Each release lists its tested platforms and known limitations; macOS 13+ is the deployment target, not a claim that every OS version was tested.

Download `SHA256SUMS` and `release-metadata.json` alongside the app ZIP and verify them with `shasum -a 256 -c SHA256SUMS`. The metadata records the source commit and build configuration. Quit an older running copy before replacing it; user data stays in Application Support.

## Start here

| File | Use it for |
| --- | --- |
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

## Important implementation boundaries

- The native menu-bar timer and close/reopen behavior are implemented. Real Launch at Login and Slack authorization/status changes remain later milestones.
- The approved feedback surface contains **Save Draft** and **Copy Feedback**. Native Save Draft works; clipboard copy remains Stage 4. No Send button or delivery destination exists.
- CSV is a session report export, not a lossless backup or import format.
- The three dashboard metrics are Focus time, Completed cycles, and Days with focus. No averaging metric is implemented in this baseline.
- The detailed specification records unresolved native policies and small prototype quirks so they can be resolved deliberately without accidentally redesigning the app.

## Build, test, and run locally

Requires macOS and a Swift toolchain. The app targets **macOS 13+**; local verification used **macOS 27.0.1, Apple Silicon, Swift 6.4**. Running on macOS 13 or Intel hardware has not been verified. The installed Swift Testing runtime requires macOS 14+ for tests.

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

`test.sh` runs the native Swift Testing suites, including actual AppKit window integration. It resolves the Testing macro plugin shipped with standalone Command Line Tools; no dependency download is needed. It also rejects an incomplete test run even if the hostless runner exits with status 0. The AppKit suites briefly create, minimize, zoom, hide, and reopen native test windows and exercise real status-item buttons. They serialize access to AppKit’s shared application state. `build-app.sh` compiles and creates an ad hoc signed `.build/Deep Work.app` for local use. It is not a notarized distribution build.

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

**Xcode validation is blocked on this machine:** `xcode-select -p` returns `/Library/Developer/CommandLineTools`; `xcodebuild` reports that it requires Xcode. The project and shared scheme are structurally validated, but that is not an Xcode build result. The native Swift build and test results are recorded in [VERIFICATION.md](docs/VERIFICATION.md).

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

Follow `AGENTS.md` for tests, progress evidence, and commit/PR wording. Use GitHub's pull-request UI or an authenticated GitHub client after pushing; no GitHub CLI is required to build or test. Before the initial app PR merges, run `git switch --track origin/feature/native-macos-stage-2` in a fresh clone to build the native app.

Pushing requires GitHub authentication. This development machine uses an existing authorized SSH key; its `origin` is `git@github.com:lukin-io/deep-work.git`. To use an already configured GitHub SSH key after an HTTPS clone:

```sh
git remote set-url origin git@github.com:lukin-io/deep-work.git
git remote -v
```

## Build and publish a preview release

The release pipeline uses the native macOS tools already described above, plus Python 3 and Git. GitHub-hosted runners include these tools and the GitHub CLI. No local GitHub CLI or long-lived upload token is needed: pushing an annotated preview tag triggers `.github/workflows/release.yml` with its scoped job token.

Before tagging, commit the changes and release notes, ensure the numeric version in `DeepWork/Resources/Info.plist` matches the tag, and require the PR's native test/package checks to pass. Preview tags follow `vX.Y.Z-preview.N`, with N starting at 1. For the first preview:

```sh
./scripts/test.sh
python3 DeepWorkTests/Release/test-publish-release.py
./DeepWorkTests/Release/test-release.sh
./scripts/package-release.sh v0.1.0-preview.1 1
./scripts/verify-release.sh .build/releases/v0.1.0-preview.1 v0.1.0-preview.1 "$(git rev-parse HEAD)"
./DeepWorkTests/Release/test-release.sh .build/releases/v0.1.0-preview.1 v0.1.0-preview.1
```

The package script requires a clean committed checkout, builds both architectures with Swift's **Release** configuration, generates the icon, signs the app ad hoc, validates an extracted archive, and writes the ZIP/checksums/metadata to `.build/releases/<tag>/`. It refuses an existing output directory to protect earlier artifacts. A local package does not upload anything and is not a published release. The release build ignores the debug-only data-directory override.

Create a new annotated tag at the exact verified commit and push that tag, using the next unused preview number for subsequent releases:

```sh
git tag -a v0.1.0-preview.1 -m "Deep Work 0.1.0 preview 1"
git push origin v0.1.0-preview.1
```

Do not repeat those commands once the version exists or move a published tag. Normal releases should be based on reviewed `main`; the initial requested preview may come from the app feature branch while PR #1 is open.

The workflow runs native tests on Apple Silicon and Intel, builds and tests a universal package, and creates a draft GitHub prerelease. It uploads the app ZIP, checksums and metadata, downloads and verifies them, then publishes with Latest disabled. PR runs only validate and retain temporary Actions artifacts; they cannot publish. A failed upload or verification leaves an unpublished draft for inspection. Fix the failure and use a new version; never replace published release bytes. Read [AGENTS.md](AGENTS.md) for release rules and [verification evidence](docs/VERIFICATION.md) for actual results.

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
- Reports, schedule editor, examples, CSV, clipboard, login registration, and Slack integration are not yet available. Their controls are disabled and do not simulate success. The checklist retains their pending acceptance checks.

For isolated development/UI testing, Debug builds accept a separate directory:

```sh
DEEP_WORK_DATA_DIR="$PWD/.build/manual-data" \
  ".build/Deep Work.app/Contents/MacOS/DeepWork"
```

Quit any running copy first. Release builds ignore this override. This location is useful for testing empty data, relaunch, migration, and failures without touching the normal store.

## Focus milestone verification

Run all native tests, or select the relevant suites:

```sh
./scripts/test.sh
./scripts/test.sh --filter TimerEngineTests
./scripts/test.sh --filter NativeApplicationTests
./scripts/test.sh --filter ClosePersistenceTests
swift build -Xswiftc -strict-concurrency=complete
python3 scripts/generate-xcode-project.py
plutil -lint DeepWork/Resources/Info.plist DeepWork.xcodeproj/project.pbxproj
codesign --verify --strict ".build/Deep Work.app"
```

The engine tests use an injected clock for exact deadlines, multi-cycle delays, pauses, clock changes and recovery. SQLite integration verifies real persisted records/checkpoints; AppKit integration exercises windows, tab focus and status-button actions. Close/Quit regressions cover automatic hidden ticking, slow/failed saves, same-window reopening, and Quit-only pause/recovery. Full Xcode, macOS 13/Intel execution, physical sleep/wake, and complete VoiceOver/light/dark acceptance remain separately identified in the verification record.

For a short manual check with the isolated data command above: choose Custom → 1 minute for both phases, turn Repeat off, and start. Press Command-W: the menu-bar timer must keep counting with the current phase name. Click it to bring Focus to the front at the current remaining time. Repeat with the red close button during the break. One complete 60-second focus record should precede Cycle complete after its break. An already paused cycle must remain paused across close/reopen. Quit with an unfinished phase and relaunch using the same isolated directory: it must restore paused with the same remainder. Reports are Stage 3, so the current Journal presents saved-record availability rather than report metrics.

Native button focus follows macOS Keyboard navigation preferences. Tab-strip arrows/Home/End retain focus on the tab strip. No test changes the user's system preferences. The progress view reads the system Reduce Motion environment and disables interpolation when requested.

## Optional reference test run

If Node.js is available, the existing pure JavaScript reporting cases can be run from this folder with:

```sh
node --test reference/journal-report-core.test.cjs
```

These are behavior references for the Swift port. They are not native XCTest results. The browser automation tests are not bundled because they depend on the previous preview QA environment.
