# Deep Work for macOS

A native SwiftUI/AppKit application implementing the Stage 1 foundation of the approved Deep Work handoff. The specification defines **137 implementation items**; `IMPLEMENTATION_CHECKLIST.md` is the sole progress tracker. The timer is the next milestone.

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

- Native menu-bar behavior, real Launch at Login, and Slack authorization/status changes require macOS/service implementation; the browser preview cannot prove them complete.
- Feedback currently supports **Save Draft** and **Copy Feedback**. No Send button or delivery destination exists.
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

`test.sh` runs the native Swift Testing suites, including actual AppKit window integration. It resolves the Testing macro plugin shipped with standalone Command Line Tools; no dependency download is needed. The integration test briefly creates, minimizes, zooms, and closes a native test window. `build-app.sh` compiles and creates an ad hoc signed `.build/Deep Work.app` for local use. It is not a notarized distribution build.

After editing source, run the tests and build again. Quit the previous app before opening the rebuilt bundle, so the running process uses the new code. Keep this README current whenever setup, build, test, run, or data-migration commands change.

With full **Xcode 16+** installed:

```sh
open DeepWork.xcodeproj
```

Select scheme **DeepWork**, destination **My Mac**, then **Run** (Command-R). Command-U runs the scheme's core tests; `./scripts/test.sh` also covers app-model and AppKit integration tests. The project uses local ad hoc signing. If adding app or core test source files, regenerate explicit Xcode file references with `python3 scripts/generate-xcode-project.py`.

The corresponding Xcode command is:

```sh
xcodebuild -project DeepWork.xcodeproj -scheme DeepWork \
  -configuration Debug -destination 'platform=macOS' build
```

**Xcode validation is blocked on this machine:** `xcode-select -p` returns `/Library/Developer/CommandLineTools`; `xcodebuild` reports that it requires Xcode. The project and shared scheme are structurally validated, but that is not an Xcode build result. The native Swift build and test results are recorded in [VERIFICATION.md](docs/VERIFICATION.md).

## Local Git repository

The project is tracked on the local `main` branch. No remote origin is configured. Generated builds, test fixtures under `.build/`, and Xcode user state are ignored; the approved handoff, source, tests, shared project/scheme, and documentation are versioned.

```sh
git status --short --branch
git log --oneline -5
git remote -v
```

The last command should print nothing until a remote is explicitly added.

## Local data and current behavior

- Journal opens on launch. Focus, Journal, and Settings share one app-owned model; native window close hides the window. The idle menu-bar item or File → Show Deep Work reopens Focus. Quit exits the process.
- Valid duration preferences, Repeat, the saved work schedule, session records/checkpoint, launch preference, and explicitly saved feedback drafts use SQLite at `~/Library/Application Support/app.deepwork.mac/DeepWork.sqlite`. Foundation resolves the user-domain Application Support URL. Each journal record has its own database row; raw segments are retained without rounding.
- Writes use transactions. Existing interim JSON files are migrated without deleting the originals; unsupported/corrupt data is preserved and reported. WAL/SHM files may accompany the database; do not treat a copy of only the main file while the app runs as a backup.
- Save Draft persists feedback; unsaved edits survive tab changes but intentionally do not survive Quit. Report selection and unsaved schedule drafts remain transient as specified. No feedback is sent.
- Timer, reports, schedule editor, examples, CSV, clipboard, login registration, and Slack integration are not yet available. Their controls are disabled and do not simulate success. The checklist retains their pending acceptance checks.

For isolated development/UI testing, Debug builds accept a separate directory:

```sh
DEEP_WORK_DATA_DIR="$PWD/.build/manual-data" \
  ".build/Deep Work.app/Contents/MacOS/DeepWork"
```

Quit any running copy first. Release builds ignore this override. This location is useful for testing empty data, relaunch, migration, and failures without touching the normal store.

## Optional reference test run

If Node.js is available, the existing pure JavaScript reporting cases can be run from this folder with:

```sh
node --test reference/journal-report-core.test.cjs
```

These are behavior references for the Swift port. They are not native XCTest results. The browser automation tests are not bundled because they depend on the previous preview QA environment.
