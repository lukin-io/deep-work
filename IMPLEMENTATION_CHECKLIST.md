# Deep Work implementation checklist

**Baseline:** October 17, 2026 · **Progress:** 36 of 137 items accepted in native Swift.

This is the canonical manual progress tracker for the current three-view app. The initial handoff started with every item TODO; current native evidence is recorded below. Each ID links to its full use case, behavior, input rules, source reference, and acceptance checks in `DEEP_WORK_SPECIFICATION.md`.

Use **TODO**, **IN PROGRESS**, **BLOCKED**, or **DONE** in the Status line. Check the box only when status is DONE and evidence is recorded. Put the owner, commit/test result, blocker or implementation note under the item. A prototype value such as Working does not count as native completion.

Feature completion means all of its child items are DONE. View completion means all its features are DONE. The initial JSON file is a task-import snapshot; it does not synchronize with edits here. If moving to an issue tracker, designate that as the sole progress source.

## Progress rollup

| View or subview | Total | Done | Remaining |
| --- | ---: | ---: | ---: |
| Shared shell | 14 | 10 | 4 |
| Focus | 29 | 26 | 3 |
| Journal | 54 | 0 | 54 |
| Journal work schedule | 19 | 0 | 19 |
| Settings | 21 | 0 | 21 |
| **Total** | **137** | **36** | **101** |

Work schedule remains inside Journal; its separate rollup is for tracking the nested editor.

## Build stages

| Stage | Focus |
| ---: | --- |
| 1 | App, shared navigation, state ownership, durable model and storage |
| 2 | Focus engine, configuration, controls, accounting and recovery |
| 3 | Journal reports, chart/table, work schedule and examples |
| 4 | Settings, shared CSV save, feedback draft and clipboard |
| 5 | Native menu bar, Launch at Login and resolved Slack integration |
| 6 | Native accessibility, visual and cross-feature acceptance |

Stages guide build order. Dependencies are component prerequisites; use the detailed specification for unresolved native policies. No time estimates are assumed.

## Stage 1 implementation record — October 18, 2026

The native application foundation now contains the three-view shell, one shared application-state owner, typed session/configuration/schedule/settings models, and SQLite persistence. The user explicitly requested SQLite and Apple platform guidelines during implementation. The database belongs at the Foundation-resolved user Application Support path `app.deepwork.mac/DeepWork.sqlite`; legacy local JSON migration preserves its sources. `reference/` and the initial JSON tracker remain unchanged.

At the Stage 1 exit, G-007 and G-008 met their complete native acceptance. The other ten Stage 1 IDs remained IN PROGRESS because their full definitions also require later timer/report/export/platform behavior or final visual acceptance; their partial evidence is recorded under each ID. Scaffolding and successful storage tests do not satisfy those later checks.

The native Swift build and test evidence, UI regression use cases, and exact Xcode tooling blocker are in [VERIFICATION.md](docs/VERIFICATION.md). Native design choices and deferred policies are in [NATIVE_DECISIONS.md](docs/NATIVE_DECISIONS.md). Full Xcode compilation remains unverified until Xcode is installed; the project and shared scheme are present and structurally validated.

## Stage 2 implementation record — October 18, 2026

F-001–F-026 now meet the Focus milestone acceptance under the recorded native policies. Timer controls, exact active-segment accounting, repeat/boundary handling, background checkpoints, paused recovery, and process ownership are implemented. G-003–G-012 are accepted, including the earlier G-007/G-008; there are **36 accepted items** overall. Native Keyboard navigation preferences are respected. Full VoiceOver/system Reduce Motion/light-dark/platform-version sweeps remain Stage 6 checks.

`./scripts/test.sh` completes **99 native tests**; `./scripts/build-app.sh` produces the native app. Real UI/SQLite cases include hidden-window timing, an exact 60-second complete record across two segments, Quit/relaunch, SIGKILL recovery, and denial of a second owner. The test script rejects incomplete hostless runs even if SwiftPM returns status 0. The full Xcode build remains blocked by the missing Xcode installation. Commands, evidence and exact limits are in [VERIFICATION.md](docs/VERIFICATION.md).

The initial local repository commit is `bee5c07`; Stage 2 is `f5d07f0`. The repository was local-only at those milestone exits; `origin` now points to [lukin-io/deep-work](https://github.com/lukin-io/deep-work). The approved reference and initial JSON tracker remain unchanged. Stage 3 is journal reporting, examples and work-schedule editing; CSV, clipboard, login and Slack retain their later milestones.

## Close and Quit clarification — October 18, 2026

The user corrected the earlier close-and-pause interpretation: red close and Command-W **only hide the main window**. Running focus/break cycles, phase transitions and SQLite checkpoints continue; already paused cycles stay paused. The menu-bar item shows the countdown with **Deep work** or **Break** and brings the existing Focus window to the front. Only Command-Q pauses, saves, drains and quits; recovery stays paused. Failed or slow saves never block hiding. Failed Quit retains the Keep Open/default and explicit Quit Without Saving choices. `reference/` remains unchanged.

Native verification: **109 Swift tests passed (78 core + 31 app)** plus **12 icon packaging cases**. Regressions cover automatic hidden ticking/checkpoints, native close/status-button target/action dispatch, hidden boundaries, same-window reopening, settings/history retention, slow/failed writes, and Quit-only pause/recovery. The native build passes. Compiled-app observations and adapter/tooling limits are in [current lifecycle verification](docs/VERIFICATION.md#close-and-quit-clarification--october-18-2026). The accepted count remains **36/137**; this correction updates existing IDs.

Icon source cleanup: G-001 uses the existing `Assets.xcassets/AppIcon.appiconset` as its single production source. Top-level delivery duplicates are moved to an ignored local archive, and the CLI build generates ICNS into build output. [Icon organization](docs/APP_ICON.md) describes the current paths; [cleanup verification](docs/VERIFICATION.md#icon-source-cleanup--october-18-2026) records focused packaging results. This structural cleanup changes no acceptance counts.

## Shared shell

Release delivery is recorded in `docs/VERIFICATION.md` and the repository's GitHub Releases. Packaging and publication do not complete additional product IDs; the accepted count remains 36/137. The preview includes the Stage 1/2 implementation and clearly identifies later features as unavailable.

### Window chrome

**Progress:** 3 / 4 accepted.

- [ ] **G-001 — Deep Work window and title** ([behavior and acceptance](DEEP_WORK_SPECIFICATION.md#g-001))

    Status: **IN PROGRESS** · Stage: **1** · Owner: Codex  
    Evidence / commit: `./scripts/test.sh` — 109 native Swift tests; [current lifecycle evidence](docs/VERIFICATION.md#close-and-quit-clarification--october-18-2026).  
    Blocker / notes: Native window, title, resizing, approved app icon and corrected hide/Quit behavior are implemented. Full light/dark and narrow-content acceptance remains Stage 6.  
    Swift: `DeepWork/App/WindowController.swift`, `DeepWork/App/AppModel.swift`

- [x] **G-006 — Red close button: hide and keep running** ([behavior and acceptance](DEEP_WORK_SPECIFICATION.md#g-006))

    Status: **DONE** · Stage: **1** · Owner: Codex  
    Evidence / commit: `./scripts/test.sh` — 109 native Swift tests; [hide/Quit evidence](docs/VERIFICATION.md#close-and-quit-clarification--october-18-2026).  
    Blocker / notes: Red close/Command-W hide immediately without pausing, ending or resetting the timer. Native close-button action, automatic hidden ticking and SQLite writes, multi-boundary accounting, slow/failed saves, same-window reopen and Quit-only pause/recovery pass. Existing paused state and saved settings/schedule/history are preserved; Close creates no partial record.  
    Swift: `DeepWork/App/WindowController.swift`, `DeepWork/App/AppModel.swift`

- [x] **G-007 — Yellow minimize traffic light** ([behavior and acceptance](DEEP_WORK_SPECIFICATION.md#g-007))

    Status: **DONE** · Stage: **1** · Owner: Codex  
    Evidence / commit: `./scripts/test.sh` — 109 native Swift tests; [current lifecycle evidence](docs/VERIFICATION.md#close-and-quit-clarification--october-18-2026).  
    Blocker / notes: Native minimize/deminimize continues to pass with the retained app owner; earlier native evidence remains valid.  
    Swift: `DeepWork/App/WindowController.swift`, `DeepWork/App/AppModel.swift`

- [x] **G-008 — Green zoom traffic light** ([behavior and acceptance](DEEP_WORK_SPECIFICATION.md#g-008))

    Status: **DONE** · Stage: **1** · Owner: Codex  
    Evidence / commit: `./scripts/test.sh` — 99 native tests; [Stage 2 native evidence](docs/VERIFICATION.md#stage-2--focus-october-18-2026).  
    Blocker / notes: Native zoom/restore integration passes; prior actual full-screen entry/exit evidence remains valid.  
    Swift: `DeepWork/App/WindowController.swift`, `DeepWork/App/AppModel.swift`

### Menu bar

**Progress:** 3 / 4 accepted.

- [ ] **G-002 — Deep Work, File and Window menu labels** ([behavior and acceptance](DEEP_WORK_SPECIFICATION.md#g-002))

    Status: **IN PROGRESS** · Stage: **5** · Owner: Codex  
    Evidence / commit: `./scripts/test.sh` — 109 native Swift tests; [current lifecycle evidence](docs/VERIFICATION.md#close-and-quit-clarification--october-18-2026).  
    Blocker / notes: Real application menus exist; Show Focus, Close and Quit paths work. Remaining menu-command acceptance is not claimed.  
    Swift: `DeepWork/App/MenuBarController.swift`, `DeepWork/App/DeepWorkApp.swift`

- [x] **G-003 — Menu-bar timer item and reopen action** ([behavior and acceptance](DEEP_WORK_SPECIFICATION.md#g-003))

    Status: **DONE** · Stage: **5** · Owner: Codex  
    Evidence / commit: `./scripts/test.sh` — 109 native Swift tests; [current lifecycle evidence](docs/VERIFICATION.md#close-and-quit-clarification--october-18-2026).  
    Blocker / notes: Real status-button target/action dispatch reopens hidden Settings on Focus with the same running/paused cycle, window and UUID, including a hidden focus-to-break boundary. Compiled-app Command-0 verifies foreground activation through the shared handler. Physical menu-extra clicking remains an adapter limitation recorded in verification.  
    Swift: `DeepWork/App/MenuBarController.swift`, `DeepWork/App/DeepWorkApp.swift`

- [x] **G-004 — Menu-bar countdown and phase text** ([behavior and acceptance](DEEP_WORK_SPECIFICATION.md#g-004))

    Status: **DONE** · Stage: **5** · Owner: Codex  
    Evidence / commit: `./scripts/test.sh` — 109 native Swift tests; [current lifecycle evidence](docs/VERIFICATION.md#close-and-quit-clarification--october-18-2026).  
    Blocker / notes: Real status title uses full Deep work/Break labels, the shared ceil countdown and tabular NSFont digits; hidden focus/break transitions, pause, idle/completion and 480:00 cases pass in native integration.  
    Swift: `DeepWork/App/MenuBarController.swift`, `DeepWork/App/DeepWorkApp.swift`

- [x] **G-005 — Timer and paused menu-bar icons** ([behavior and acceptance](DEEP_WORK_SPECIFICATION.md#g-005))

    Status: **DONE** · Stage: **5** · Owner: Codex  
    Evidence / commit: `./scripts/test.sh` — 99 native tests; [Stage 2 native evidence](docs/VERIFICATION.md#stage-2--focus-october-18-2026).  
    Blocker / notes: One native template timer/pause symbol, paused accessibility prefix, and completion reset verified in AppKit integration.  
    Swift: `DeepWork/App/MenuBarController.swift`, `DeepWork/App/DeepWorkApp.swift`

### View navigation

**Progress:** 4 / 4 accepted.

- [x] **G-009 — Focus tab** ([behavior and acceptance](DEEP_WORK_SPECIFICATION.md#g-009))

    Status: **DONE** · Stage: **1** · Owner: Codex  
    Evidence / commit: `./scripts/test.sh` — 99 native tests; [Stage 2 native evidence](docs/VERIFICATION.md#stage-2--focus-october-18-2026).  
    Blocker / notes: Mouse/keyboard Focus navigation preserves setup, running, paused and complete state; preferred width and first-responder regression verified.  
    Swift: `DeepWork/App/RootView.swift`, `DeepWork/App/AppModel.swift`

- [x] **G-010 — Journal tab and initial landing view** ([behavior and acceptance](DEEP_WORK_SPECIFICATION.md#g-010))

    Status: **DONE** · Stage: **1** · Owner: Codex  
    Evidence / commit: `./scripts/test.sh` — 99 native tests; [Stage 2 native evidence](docs/VERIFICATION.md#stage-2--focus-october-18-2026).  
    Blocker / notes: Initial/recovered launch selects Journal. Tab switching reconciles and commits crossed boundaries without pausing; contents remain separate Stage 3 work.  
    Swift: `DeepWork/App/RootView.swift`, `DeepWork/App/AppModel.swift`

- [x] **G-011 — Settings tab** ([behavior and acceptance](DEEP_WORK_SPECIFICATION.md#g-011))

    Status: **DONE** · Stage: **1** · Owner: Codex  
    Evidence / commit: `./scripts/test.sh` — 99 native tests; [Stage 2 native evidence](docs/VERIFICATION.md#stage-2--focus-october-18-2026).  
    Blocker / notes: Settings retains running/paused timer and unsaved edits; all three native tab segments fit and remain enabled at 320 pt.  
    Swift: `DeepWork/App/RootView.swift`, `DeepWork/App/AppModel.swift`

- [x] **G-012 — Keyboard navigation across the three tabs** ([behavior and acceptance](DEEP_WORK_SPECIFICATION.md#g-012))

    Status: **DONE** · Stage: **1** · Owner: Codex  
    Evidence / commit: `./scripts/test.sh` — 99 native tests; [Stage 2 native evidence](docs/VERIFICATION.md#stage-2--focus-october-18-2026).  
    Blocker / notes: Actual NSWindow first-responder routing verifies wrap/Home/End in setup/running/paused states while retaining live UUID and unsaved edits.  
    Swift: `DeepWork/App/RootView.swift`, `DeepWork/App/AppModel.swift`

### Accessibility feedback

**Progress:** 0 / 1 accepted.

- [ ] **G-013 — Shared action announcements** ([behavior and acceptance](DEEP_WORK_SPECIFICATION.md#g-013))

    Status: **IN PROGRESS** · Stage: **6** · Owner: Codex  
    Evidence / commit: `./scripts/test.sh` — 99 native tests; [Stage 2 native evidence](docs/VERIFICATION.md#stage-2--focus-october-18-2026).  
    Blocker / notes: Focus phase, validation, Repeat and summary announcements use native accessibility notifications. Full VoiceOver and later-view announcements remain unverified.  
    Swift: `DeepWork/App/RootView.swift`, `DeepWork/Accessibility/Announcements.swift`

### Prototype disclosure

**Progress:** 0 / 1 accepted.

- [ ] **G-014 — Standalone preview explanation** ([behavior and acceptance](DEEP_WORK_SPECIFICATION.md#g-014))

    Status: **TODO** · Stage: **6** · Owner: _unassigned_  
    Evidence / commit: _none_  
    Blocker / notes: _none_  
    Swift: `DeepWork/App/RootView.swift`, `DeepWork/Accessibility/Announcements.swift`

## Focus

### Session setup

**Progress:** 7 / 7 accepted.

- [x] **F-001 — Set your rhythm heading and setup group** ([behavior and acceptance](DEEP_WORK_SPECIFICATION.md#f-001))

    Status: **DONE** · Stage: **2** · Owner: Codex  
    Evidence / commit: `./scripts/test.sh` — 99 native tests; [Stage 2 native evidence](docs/VERIFICATION.md#stage-2--focus-october-18-2026).  
    Blocker / notes: Native setup/session visibility and retained End-session choices verified; first launch remains Journal.  
    Swift: `DeepWork/Features/Focus/FocusView.swift`, `DeepWork/Core/FocusConfiguration.swift`, `DeepWork/Data/JournalStore.swift`

- [x] **F-002 — Deep work duration selector** ([behavior and acceptance](DEEP_WORK_SPECIFICATION.md#f-002))

    Status: **DONE** · Stage: **2** · Owner: Codex  
    Evidence / commit: `./scripts/test.sh` — 99 native tests; [Stage 2 native evidence](docs/VERIFICATION.md#stage-2--focus-october-18-2026).  
    Blocker / notes: 60/90/Custom options, blank default, focus/select-all, stored selection and hidden custom retention verified.  
    Swift: `DeepWork/Features/Focus/FocusView.swift`, `DeepWork/Core/FocusConfiguration.swift`, `DeepWork/Data/JournalStore.swift`

- [x] **F-003 — Custom deep work minutes** ([behavior and acceptance](DEEP_WORK_SPECIFICATION.md#f-003))

    Status: **DONE** · Stage: **2** · Owner: Codex  
    Evidence / commit: `./scripts/test.sh` — 99 native tests; [Stage 2 native evidence](docs/VERIFICATION.md#stage-2--focus-october-18-2026).  
    Blocker / notes: Custom default 75 and whole-minute boundaries 1–480 verified; invalid raw edits cannot start using older saved values.  
    Swift: `DeepWork/Features/Focus/FocusView.swift`, `DeepWork/Core/FocusConfiguration.swift`, `DeepWork/Data/JournalStore.swift`

- [x] **F-005 — Break duration selector** ([behavior and acceptance](DEEP_WORK_SPECIFICATION.md#f-005))

    Status: **DONE** · Stage: **2** · Owner: Codex  
    Evidence / commit: `./scripts/test.sh` — 99 native tests; [Stage 2 native evidence](docs/VERIFICATION.md#stage-2--focus-october-18-2026).  
    Blocker / notes: 10/20/Custom options, blank default, focus/select-all, and persisted choice verified.  
    Swift: `DeepWork/Features/Focus/FocusView.swift`, `DeepWork/Core/FocusConfiguration.swift`, `DeepWork/Data/JournalStore.swift`

- [x] **F-006 — Custom break minutes** ([behavior and acceptance](DEEP_WORK_SPECIFICATION.md#f-006))

    Status: **DONE** · Stage: **2** · Owner: Codex  
    Evidence / commit: `./scripts/test.sh` — 99 native tests; [Stage 2 native evidence](docs/VERIFICATION.md#stage-2--focus-october-18-2026).  
    Blocker / notes: Custom default 15, validation endpoints/invalid edits, and hidden custom retention verified.  
    Swift: `DeepWork/Features/Focus/FocusView.swift`, `DeepWork/Core/FocusConfiguration.swift`, `DeepWork/Data/JournalStore.swift`

- [x] **F-008 — Selected duration summary** ([behavior and acceptance](DEEP_WORK_SPECIFICATION.md#f-008))

    Status: **DONE** · Stage: **2** · Owner: Codex  
    Evidence / commit: `./scripts/test.sh` — 99 native tests; [Stage 2 native evidence](docs/VERIFICATION.md#stage-2--focus-october-18-2026).  
    Blocker / notes: Choose-both and valid-duration summaries track raw inputs; setup-only rendering and native status announcements implemented.  
    Swift: `DeepWork/Features/Focus/FocusView.swift`, `DeepWork/Core/FocusConfiguration.swift`, `DeepWork/Data/JournalStore.swift`

- [x] **F-009 — Start deep work** ([behavior and acceptance](DEEP_WORK_SPECIFICATION.md#f-009))

    Status: **DONE** · Stage: **2** · Owner: Codex  
    Evidence / commit: `./scripts/test.sh` — 99 native tests; [Stage 2 native evidence](docs/VERIFICATION.md#stage-2--focus-october-18-2026).  
    Blocker / notes: Start revalidates raw input, snapshots durations and creates one live UUID; duplicate Start is a no-op. Native button focus honors macOS Keyboard navigation preferences.  
    Swift: `DeepWork/Features/Focus/FocusView.swift`, `DeepWork/Core/FocusConfiguration.swift`, `DeepWork/Data/JournalStore.swift`

### Duration validation

**Progress:** 2 / 2 accepted.

- [x] **F-004 — Custom deep work validation message** ([behavior and acceptance](DEEP_WORK_SPECIFICATION.md#f-004))

    Status: **DONE** · Stage: **2** · Owner: Codex  
    Evidence / commit: `./scripts/test.sh` — 99 native tests; [Stage 2 native evidence](docs/VERIFICATION.md#stage-2--focus-october-18-2026).  
    Blocker / notes: Exact error copy and field association verified in native UI; invalid/corrected/preset cases covered by app tests.  
    Swift: `DeepWork/Features/Focus/FocusView.swift`, `DeepWork/Core/FocusConfiguration.swift`, `DeepWork/Data/JournalStore.swift`

- [x] **F-007 — Custom break validation message** ([behavior and acceptance](DEEP_WORK_SPECIFICATION.md#f-007))

    Status: **DONE** · Stage: **2** · Owner: Codex  
    Evidence / commit: `./scripts/test.sh` — 99 native tests; [Stage 2 native evidence](docs/VERIFICATION.md#stage-2--focus-october-18-2026).  
    Blocker / notes: Exact break error and invalid/corrected/preset cases covered; native field accessibility help uses the error.  
    Swift: `DeepWork/Features/Focus/FocusView.swift`, `DeepWork/Core/FocusConfiguration.swift`, `DeepWork/Data/JournalStore.swift`

### Repeat behavior

**Progress:** 2 / 2 accepted.

- [x] **F-010 — Repeat cycles checkbox** ([behavior and acceptance](DEEP_WORK_SPECIFICATION.md#f-010))

    Status: **DONE** · Stage: **2** · Owner: Codex  
    Evidence / commit: `./scripts/test.sh` — 99 native tests; [Stage 2 native evidence](docs/VERIFICATION.md#stage-2--focus-october-18-2026).  
    Blocker / notes: Finish-current-pair behavior, paused/completed toggles, and previous-Repeat reconciliation pass deterministic/native integration cases.  
    Swift: `DeepWork/Features/Focus/FocusView.swift`, `DeepWork/Core/TimerEngine.swift`

- [x] **F-011 — Repeat and stop-timing helper** ([behavior and acceptance](DEEP_WORK_SPECIFICATION.md#f-011))

    Status: **DONE** · Stage: **2** · Owner: Codex  
    Evidence / commit: `./scripts/test.sh` — 99 native tests; [Stage 2 native evidence](docs/VERIFICATION.md#stage-2--focus-october-18-2026).  
    Blocker / notes: All setup/focus/break/paused/completed helper strings are projected from the engine and verified.  
    Swift: `DeepWork/Features/Focus/FocusView.swift`, `DeepWork/Core/TimerEngine.swift`

### Session display

**Progress:** 4 / 4 accepted.

- [x] **F-012 — Phase heading and focus/break icons** ([behavior and acceptance](DEEP_WORK_SPECIFICATION.md#f-012))

    Status: **DONE** · Stage: **2** · Owner: Codex  
    Evidence / commit: `./scripts/test.sh` — 99 native tests; [Stage 2 native evidence](docs/VERIFICATION.md#stage-2--focus-october-18-2026).  
    Blocker / notes: Native headings/icons reflect focus, break, paused and complete states. Partial pairs remain partial in SQLite.  
    Swift: `DeepWork/Features/Focus/FocusView.swift`, `DeepWork/Core/TimerEngine.swift`

- [x] **F-013 — Large remaining-time display** ([behavior and acceptance](DEEP_WORK_SPECIFICATION.md#f-013))

    Status: **DONE** · Stage: **2** · Owner: Codex  
    Evidence / commit: `./scripts/test.sh` — 99 native tests; [Stage 2 native evidence](docs/VERIFICATION.md#stage-2--focus-october-18-2026).  
    Blocker / notes: Ceil countdown through 480:00, freeze/resume, menu parity and zero completion verified. External native AX exposes Time remaining independently (UI-16).  
    Swift: `DeepWork/Features/Focus/FocusView.swift`, `DeepWork/Core/TimerEngine.swift`

- [x] **F-014 — Next-phase and journal caption** ([behavior and acceptance](DEEP_WORK_SPECIFICATION.md#f-014))

    Status: **DONE** · Stage: **2** · Owner: Codex  
    Evidence / commit: `./scripts/test.sh` — 99 native tests; [Stage 2 native evidence](docs/VERIFICATION.md#stage-2--focus-october-18-2026).  
    Blocker / notes: Session-duration captions, paused exclusion and final-break copy verified. Saved caption waits for commit and reports pending/failure truthfully.  
    Swift: `DeepWork/Features/Focus/FocusView.swift`, `DeepWork/Core/TimerEngine.swift`

- [x] **F-015 — Current-phase progress bar** ([behavior and acceptance](DEEP_WORK_SPECIFICATION.md#f-015))

    Status: **DONE** · Stage: **2** · Owner: Codex  
    Evidence / commit: `./scripts/test.sh` — 99 native tests; [Stage 2 native evidence](docs/VERIFICATION.md#stage-2--focus-october-18-2026).  
    Blocker / notes: Phase-clamped progress and rounded percentage verified; native bitmap rendering and explicit reduced-motion animation policy tests pass. Full system-preference/VoiceOver sweep remains Stage 6.  
    Swift: `DeepWork/Features/Focus/FocusView.swift`, `DeepWork/Core/TimerEngine.swift`

### Session controls

**Progress:** 7 / 7 accepted.

- [x] **F-016 — Pause current phase** ([behavior and acceptance](DEEP_WORK_SPECIFICATION.md#f-016))

    Status: **DONE** · Stage: **2** · Owner: Codex  
    Evidence / commit: `./scripts/test.sh` — 99 native tests; [Stage 2 native evidence](docs/VERIFICATION.md#stage-2--focus-october-18-2026).  
    Blocker / notes: Pause reconciles first, seals focus, freezes remainder/progress and does not restart after a stale final-break click.  
    Swift: `DeepWork/Core/TimerEngine.swift`, `DeepWork/Core/SessionRecord.swift`, `DeepWork/Features/Focus/FocusView.swift`

- [x] **F-017 — Resume paused phase** ([behavior and acceptance](DEEP_WORK_SPECIFICATION.md#f-017))

    Status: **DONE** · Stage: **2** · Owner: Codex  
    Evidence / commit: `./scripts/test.sh` — 99 native tests; [Stage 2 native evidence](docs/VERIFICATION.md#stage-2--focus-october-18-2026).  
    Blocker / notes: Resume retains UUID/remainder, excludes pause/downtime and clears recovery; real Quit/relaunch/resume produced exactly 60 seconds in two segments.  
    Swift: `DeepWork/Core/TimerEngine.swift`, `DeepWork/Core/SessionRecord.swift`, `DeepWork/Features/Focus/FocusView.swift`

- [x] **F-018 — Start again after completion** ([behavior and acceptance](DEEP_WORK_SPECIFICATION.md#f-018))

    Status: **DONE** · Stage: **2** · Owner: Codex  
    Evidence / commit: `./scripts/test.sh` — 99 native tests; [Stage 2 native evidence](docs/VERIFICATION.md#stage-2--focus-october-18-2026).  
    Blocker / notes: Start again uses snapshotted durations/current Repeat and a fresh UUID without altering history; native UI exercised.  
    Swift: `DeepWork/Core/TimerEngine.swift`, `DeepWork/Core/SessionRecord.swift`, `DeepWork/Features/Focus/FocusView.swift`

- [x] **F-019 — Take break before focus finishes** ([behavior and acceptance](DEEP_WORK_SPECIFICATION.md#f-019))

    Status: **DONE** · Stage: **2** · Owner: Codex  
    Evidence / commit: `./scripts/test.sh` — 99 native tests; [Stage 2 native evidence](docs/VERIFICATION.md#stage-2--focus-october-18-2026).  
    Blocker / notes: 17-second partial and zero discard covered; paused Take break starts running; native recovered paused focus transition verified.  
    Swift: `DeepWork/Core/TimerEngine.swift`, `DeepWork/Core/SessionRecord.swift`, `DeepWork/Features/Focus/FocusView.swift`

- [x] **F-020 — Skip break when Repeat is enabled** ([behavior and acceptance](DEEP_WORK_SPECIFICATION.md#f-020))

    Status: **DONE** · Stage: **2** · Owner: Codex  
    Evidence / commit: `./scripts/test.sh` — 99 native tests; [Stage 2 native evidence](docs/VERIFICATION.md#stage-2--focus-october-18-2026).  
    Blocker / notes: Skip break creates a fresh running focus, including from pause, without adding break time or completion.  
    Swift: `DeepWork/Core/TimerEngine.swift`, `DeepWork/Core/SessionRecord.swift`, `DeepWork/Features/Focus/FocusView.swift`

- [x] **F-021 — Finish break when Repeat is disabled** ([behavior and acceptance](DEEP_WORK_SPECIFICATION.md#f-021))

    Status: **DONE** · Stage: **2** · Owner: Codex  
    Evidence / commit: `./scripts/test.sh` — 99 native tests; [Stage 2 native evidence](docs/VERIFICATION.md#stage-2--focus-october-18-2026).  
    Blocker / notes: Finish break completes from running/paused final break without changing prior focus outcomes; controls/menu projection verified.  
    Swift: `DeepWork/Core/TimerEngine.swift`, `DeepWork/Core/SessionRecord.swift`, `DeepWork/Features/Focus/FocusView.swift`

- [x] **F-022 — End session and return to setup** ([behavior and acceptance](DEEP_WORK_SPECIFICATION.md#f-022))

    Status: **DONE** · Stage: **2** · Owner: Codex  
    Evidence / commit: `./scripts/test.sh` — 99 native tests; [Stage 2 native evidence](docs/VERIFICATION.md#stage-2--focus-october-18-2026).  
    Blocker / notes: End preserves positive partial time, discards zero, clears checkpoint and returns to retained setup; SQLite integration passes.  
    Swift: `DeepWork/Core/TimerEngine.swift`, `DeepWork/Core/SessionRecord.swift`, `DeepWork/Features/Focus/FocusView.swift`

### Automatic phase transitions

**Progress:** 2 / 2 accepted.

- [x] **F-023 — Focus deadline: record completion and start break** ([behavior and acceptance](DEEP_WORK_SPECIFICATION.md#f-023))

    Status: **DONE** · Stage: **2** · Owner: Codex  
    Evidence / commit: `./scripts/test.sh` — 99 native tests; [Stage 2 native evidence](docs/VERIFICATION.md#stage-2--focus-october-18-2026).  
    Blocker / notes: Exact focus deadline finalizes once and starts break. Real native 60-second cycle persisted exactly once; repeated callbacks do not duplicate.  
    Swift: `DeepWork/Core/TimerEngine.swift`, `DeepWork/Core/SessionRecord.swift`, `DeepWork/Features/Focus/FocusView.swift`

- [x] **F-024 — Break deadline, repeat progression and delayed callbacks** ([behavior and acceptance](DEEP_WORK_SPECIFICATION.md#f-024))

    Status: **DONE** · Stage: **2** · Owner: Codex  
    Evidence / commit: `./scripts/test.sh` — 99 native tests; [Stage 2 native evidence](docs/VERIFICATION.md#stage-2--focus-october-18-2026).  
    Blocker / notes: Multi-boundary catch-up and old-Repeat reconciliation pass. ContinuousClock includes sleep; wall-clock jumps do not change accounting. Real hidden-window boundary observed; physical sleep remains unverified.  
    Swift: `DeepWork/Core/TimerEngine.swift`, `DeepWork/Core/SessionRecord.swift`, `DeepWork/Features/Focus/FocusView.swift`

### Recovery and ownership

**Progress:** 2 / 2 accepted.

- [x] **F-025 — Recovered-session notice** ([behavior and acceptance](DEEP_WORK_SPECIFICATION.md#f-025))

    Status: **DONE** · Stage: **2** · Owner: Codex  
    Evidence / commit: `./scripts/test.sh` — 109 native Swift tests; [current lifecycle evidence](docs/VERIFICATION.md#close-and-quit-clarification--october-18-2026).  
    Blocker / notes: Five-second/action/visibility checkpoints and Quit drain tested. Real Quit and SIGKILL relaunch restore exact paused remainder/UUID/segments; no process downtime credited.  
    Swift: `DeepWork/Core/TimerEngine.swift`, `DeepWork/Data/JournalStore.swift`, `DeepWork/App/AppModel.swift`

- [x] **F-026 — Other-window timer ownership notice and disabled controls** ([behavior and acceptance](DEEP_WORK_SPECIFICATION.md#f-026))

    Status: **DONE** · Stage: **2** · Owner: Codex  
    Evidence / commit: `./scripts/test.sh` — 99 native tests; [Stage 2 native evidence](docs/VERIFICATION.md#stage-2--focus-october-18-2026).  
    Blocker / notes: One app owner plus canonical per-store process lock. Actual second native process denied ownership; same-record recovery and duplicate prevention verified.  
    Swift: `DeepWork/Core/TimerEngine.swift`, `DeepWork/Data/JournalStore.swift`, `DeepWork/App/AppModel.swift`

### Slack status preview

**Progress:** 0 / 3 accepted.

- [ ] **F-027 — Slack status heading, icon and Preview label** ([behavior and acceptance](DEEP_WORK_SPECIFICATION.md#f-027))

    Status: **TODO** · Stage: **5** · Owner: _unassigned_  
    Evidence / commit: _none_  
    Blocker / notes: _none_  
    Swift: `DeepWork/Features/Focus/FocusView.swift`, `DeepWork/Services/SlackStatusService.swift`

- [ ] **F-028 — Focus status text and restored-status placeholder** ([behavior and acceptance](DEEP_WORK_SPECIFICATION.md#f-028))

    Status: **TODO** · Stage: **5** · Owner: _unassigned_  
    Evidence / commit: _none_  
    Blocker / notes: _none_  
    Swift: `DeepWork/Features/Focus/FocusView.swift`, `DeepWork/Services/SlackStatusService.swift`

- [ ] **F-029 — Slack helper copy by session state** ([behavior and acceptance](DEEP_WORK_SPECIFICATION.md#f-029))

    Status: **TODO** · Stage: **5** · Owner: _unassigned_  
    Evidence / commit: _none_  
    Blocker / notes: _none_  
    Swift: `DeepWork/Features/Focus/FocusView.swift`, `DeepWork/Services/SlackStatusService.swift`

## Journal

### Navigation

**Progress:** 0 / 1 accepted.

- [ ] **J-001 — Journal tab and initial view** ([behavior and acceptance](DEEP_WORK_SPECIFICATION.md#j-001))

    Status: **IN PROGRESS** · Stage: **1** · Owner: Codex  
    Evidence / commit: [Native verification, October 18, 2026](docs/VERIFICATION.md); `./scripts/test.sh`, compiled native app and macOS acceptance.  
    Blocker / notes: Journal initial landing/Week selection, keyboard selection and in-memory report/draft ownership verified. Active timer, reporting-day cutoff behavior and actual report-selection UI remain.  
    Swift: `DeepWork/Features/Journal/JournalView.swift`, `DeepWork/App/AppModel.swift`

### Layout

**Progress:** 0 / 1 accepted.

- [ ] **J-002 — Journal window and section structure** ([behavior and acceptance](DEEP_WORK_SPECIFICATION.md#j-002))

    Status: **IN PROGRESS** · Stage: **1** · Owner: Codex  
    Evidence / commit: [Native verification, October 18, 2026](docs/VERIFICATION.md); `./scripts/test.sh`, compiled native app and macOS acceptance.  
    Blocker / notes: Reference section order and restrained native shell are present; metrics/report/example controls are explicitly unavailable. Full report layout, light/dark and narrow-window acceptance remain.  
    Swift: `DeepWork/Features/Journal/JournalView.swift`, `DeepWork/App/AppModel.swift`

### Report context

**Progress:** 0 / 2 accepted.

- [ ] **J-003 — Focus journal heading and saved-schedule summary** ([behavior and acceptance](DEEP_WORK_SPECIFICATION.md#j-003))

    Status: **TODO** · Stage: **3** · Owner: _unassigned_  
    Evidence / commit: _none_  
    Blocker / notes: _none_  
    Swift: `DeepWork/Features/Journal/JournalView.swift`, `DeepWork/Reports/ReportEngine.swift`, `DeepWork/Reports/WorkSchedule.swift`

- [ ] **J-015 — Selected period title** ([behavior and acceptance](DEEP_WORK_SPECIFICATION.md#j-015))

    Status: **TODO** · Stage: **3** · Owner: _unassigned_  
    Evidence / commit: _none_  
    Blocker / notes: _none_  
    Swift: `DeepWork/Features/Journal/JournalView.swift`, `DeepWork/Reports/ReportEngine.swift`, `DeepWork/Reports/WorkSchedule.swift`

### Work schedule access

**Progress:** 0 / 1 accepted.

- [ ] **J-004 — Schedule button** ([behavior and acceptance](DEEP_WORK_SPECIFICATION.md#j-004))

    Status: **TODO** · Stage: **3** · Owner: _unassigned_  
    Evidence / commit: _none_  
    Blocker / notes: _none_  
    Swift: `DeepWork/Features/Journal/JournalView.swift`, `DeepWork/Features/Journal/WorkScheduleView.swift`

### Period selection

**Progress:** 0 / 3 accepted.

- [ ] **J-005 — Day segment** ([behavior and acceptance](DEEP_WORK_SPECIFICATION.md#j-005))

    Status: **TODO** · Stage: **3** · Owner: _unassigned_  
    Evidence / commit: _none_  
    Blocker / notes: _none_  
    Swift: `DeepWork/Features/Journal/JournalView.swift`, `DeepWork/Reports/ReportEngine.swift`, `DeepWork/Reports/WorkSchedule.swift`

- [ ] **J-006 — Week segment** ([behavior and acceptance](DEEP_WORK_SPECIFICATION.md#j-006))

    Status: **TODO** · Stage: **3** · Owner: _unassigned_  
    Evidence / commit: _none_  
    Blocker / notes: _none_  
    Swift: `DeepWork/Features/Journal/JournalView.swift`, `DeepWork/Reports/ReportEngine.swift`, `DeepWork/Reports/WorkSchedule.swift`

- [ ] **J-007 — Range segment** ([behavior and acceptance](DEEP_WORK_SPECIFICATION.md#j-007))

    Status: **TODO** · Stage: **3** · Owner: _unassigned_  
    Evidence / commit: _none_  
    Blocker / notes: _none_  
    Swift: `DeepWork/Features/Journal/JournalView.swift`, `DeepWork/Reports/ReportEngine.swift`, `DeepWork/Reports/WorkSchedule.swift`

### Date navigation

**Progress:** 0 / 4 accepted.

- [ ] **J-008 — Report date picker** ([behavior and acceptance](DEEP_WORK_SPECIFICATION.md#j-008))

    Status: **TODO** · Stage: **3** · Owner: _unassigned_  
    Evidence / commit: _none_  
    Blocker / notes: _none_  
    Swift: `DeepWork/Features/Journal/JournalView.swift`, `DeepWork/Reports/ReportEngine.swift`, `DeepWork/Reports/WorkSchedule.swift`

- [ ] **J-009 — Previous period button** ([behavior and acceptance](DEEP_WORK_SPECIFICATION.md#j-009))

    Status: **TODO** · Stage: **3** · Owner: _unassigned_  
    Evidence / commit: _none_  
    Blocker / notes: _none_  
    Swift: `DeepWork/Features/Journal/JournalView.swift`, `DeepWork/Reports/ReportEngine.swift`, `DeepWork/Reports/WorkSchedule.swift`

- [ ] **J-010 — Next period button** ([behavior and acceptance](DEEP_WORK_SPECIFICATION.md#j-010))

    Status: **TODO** · Stage: **3** · Owner: _unassigned_  
    Evidence / commit: _none_  
    Blocker / notes: _none_  
    Swift: `DeepWork/Features/Journal/JournalView.swift`, `DeepWork/Reports/ReportEngine.swift`, `DeepWork/Reports/WorkSchedule.swift`

- [ ] **J-016 — Today button** ([behavior and acceptance](DEEP_WORK_SPECIFICATION.md#j-016))

    Status: **TODO** · Stage: **3** · Owner: _unassigned_  
    Evidence / commit: _none_  
    Blocker / notes: _none_  
    Swift: `DeepWork/Features/Journal/JournalView.swift`, `DeepWork/Reports/ReportEngine.swift`, `DeepWork/Reports/WorkSchedule.swift`

### Custom range

**Progress:** 0 / 4 accepted.

- [ ] **J-011 — From endpoint** ([behavior and acceptance](DEEP_WORK_SPECIFICATION.md#j-011))

    Status: **TODO** · Stage: **3** · Owner: _unassigned_  
    Evidence / commit: _none_  
    Blocker / notes: _none_  
    Swift: `DeepWork/Features/Journal/JournalView.swift`, `DeepWork/Reports/ReportEngine.swift`, `DeepWork/Reports/WorkSchedule.swift`

- [ ] **J-012 — Until endpoint** ([behavior and acceptance](DEEP_WORK_SPECIFICATION.md#j-012))

    Status: **TODO** · Stage: **3** · Owner: _unassigned_  
    Evidence / commit: _none_  
    Blocker / notes: _none_  
    Swift: `DeepWork/Features/Journal/JournalView.swift`, `DeepWork/Reports/ReportEngine.swift`, `DeepWork/Reports/WorkSchedule.swift`

- [ ] **J-013 — Range explanation** ([behavior and acceptance](DEEP_WORK_SPECIFICATION.md#j-013))

    Status: **TODO** · Stage: **3** · Owner: _unassigned_  
    Evidence / commit: _none_  
    Blocker / notes: _none_  
    Swift: `DeepWork/Features/Journal/JournalView.swift`, `DeepWork/Reports/ReportEngine.swift`, `DeepWork/Reports/WorkSchedule.swift`

- [ ] **J-014 — Range validation and error state** ([behavior and acceptance](DEEP_WORK_SPECIFICATION.md#j-014))

    Status: **TODO** · Stage: **3** · Owner: _unassigned_  
    Evidence / commit: _none_  
    Blocker / notes: _none_  
    Swift: `DeepWork/Features/Journal/JournalView.swift`, `DeepWork/Reports/ReportEngine.swift`, `DeepWork/Reports/WorkSchedule.swift`

### Example data

**Progress:** 0 / 4 accepted.

- [ ] **J-017 — Example banner** ([behavior and acceptance](DEEP_WORK_SPECIFICATION.md#j-017))

    Status: **TODO** · Stage: **3** · Owner: _unassigned_  
    Evidence / commit: _none_  
    Blocker / notes: _none_  
    Swift: `DeepWork/Reports/ExampleData.swift`, `DeepWork/Features/Journal/JournalView.swift`

- [ ] **J-018 — Footer View example / Show my journal button** ([behavior and acceptance](DEEP_WORK_SPECIFICATION.md#j-018))

    Status: **TODO** · Stage: **3** · Owner: _unassigned_  
    Evidence / commit: _none_  
    Blocker / notes: _none_  
    Swift: `DeepWork/Reports/ExampleData.swift`, `DeepWork/Features/Journal/JournalView.swift`

- [ ] **J-019 — Banner Show my journal button** ([behavior and acceptance](DEEP_WORK_SPECIFICATION.md#j-019))

    Status: **TODO** · Stage: **3** · Owner: _unassigned_  
    Evidence / commit: _none_  
    Blocker / notes: _none_  
    Swift: `DeepWork/Reports/ExampleData.swift`, `DeepWork/Features/Journal/JournalView.swift`

- [ ] **J-020 — Generated example scope and initial mode** ([behavior and acceptance](DEEP_WORK_SPECIFICATION.md#j-020))

    Status: **TODO** · Stage: **3** · Owner: _unassigned_  
    Evidence / commit: _none_  
    Blocker / notes: _none_  
    Swift: `DeepWork/Reports/ExampleData.swift`, `DeepWork/Features/Journal/JournalView.swift`

### Report totals

**Progress:** 0 / 4 accepted.

- [ ] **J-021 — Three-metric summary layout** ([behavior and acceptance](DEEP_WORK_SPECIFICATION.md#j-021))

    Status: **TODO** · Stage: **3** · Owner: _unassigned_  
    Evidence / commit: _none_  
    Blocker / notes: _none_  
    Swift: `DeepWork/Features/Journal/JournalView.swift`, `DeepWork/Reports/ReportEngine.swift`, `DeepWork/Reports/WorkSchedule.swift`

- [ ] **J-022 — Focus time metric** ([behavior and acceptance](DEEP_WORK_SPECIFICATION.md#j-022))

    Status: **TODO** · Stage: **3** · Owner: _unassigned_  
    Evidence / commit: _none_  
    Blocker / notes: _none_  
    Swift: `DeepWork/Features/Journal/JournalView.swift`, `DeepWork/Reports/ReportEngine.swift`, `DeepWork/Reports/WorkSchedule.swift`

- [ ] **J-023 — Completed cycles metric and partial-session helper** ([behavior and acceptance](DEEP_WORK_SPECIFICATION.md#j-023))

    Status: **TODO** · Stage: **3** · Owner: _unassigned_  
    Evidence / commit: _none_  
    Blocker / notes: _none_  
    Swift: `DeepWork/Features/Journal/JournalView.swift`, `DeepWork/Reports/ReportEngine.swift`, `DeepWork/Reports/WorkSchedule.swift`

- [ ] **J-024 — Days with focus and scheduled-days helper** ([behavior and acceptance](DEEP_WORK_SPECIFICATION.md#j-024))

    Status: **TODO** · Stage: **3** · Owner: _unassigned_  
    Evidence / commit: _none_  
    Blocker / notes: _none_  
    Swift: `DeepWork/Features/Journal/JournalView.swift`, `DeepWork/Reports/ReportEngine.swift`, `DeepWork/Reports/WorkSchedule.swift`

### Accounting

**Progress:** 0 / 2 accepted.

- [ ] **J-025 — Range clipping and date-bucket rules** ([behavior and acceptance](DEEP_WORK_SPECIFICATION.md#j-025))

    Status: **TODO** · Stage: **3** · Owner: _unassigned_  
    Evidence / commit: _none_  
    Blocker / notes: _none_  
    Swift: `DeepWork/Features/Journal/JournalView.swift`, `DeepWork/Reports/ReportEngine.swift`, `DeepWork/Reports/WorkSchedule.swift`

- [ ] **J-042 — Session accounting explanation** ([behavior and acceptance](DEEP_WORK_SPECIFICATION.md#j-042))

    Status: **TODO** · Stage: **3** · Owner: _unassigned_  
    Evidence / commit: _none_  
    Blocker / notes: _none_  
    Swift: `DeepWork/Features/Journal/SessionListView.swift`, `DeepWork/Features/Journal/JournalView.swift`

### Activity

**Progress:** 0 / 5 accepted.

- [ ] **J-026 — Daily focus / Weekly focus heading** ([behavior and acceptance](DEEP_WORK_SPECIFICATION.md#j-026))

    Status: **TODO** · Stage: **3** · Owner: _unassigned_  
    Evidence / commit: _none_  
    Blocker / notes: _none_  
    Swift: `DeepWork/Features/Journal/ActivityChartView.swift`, `DeepWork/Reports/ReportEngine.swift`

- [ ] **J-027 — By day / By week grouping selector** ([behavior and acceptance](DEEP_WORK_SPECIFICATION.md#j-027))

    Status: **TODO** · Stage: **3** · Owner: _unassigned_  
    Evidence / commit: _none_  
    Blocker / notes: _none_  
    Swift: `DeepWork/Features/Journal/ActivityChartView.swift`, `DeepWork/Reports/ReportEngine.swift`

- [ ] **J-028 — Automatic weekly grouping for long ranges** ([behavior and acceptance](DEEP_WORK_SPECIFICATION.md#j-028))

    Status: **TODO** · Stage: **3** · Owner: _unassigned_  
    Evidence / commit: _none_  
    Blocker / notes: _none_  
    Swift: `DeepWork/Features/Journal/ActivityChartView.swift`, `DeepWork/Reports/ReportEngine.swift`

- [ ] **J-034 — Chart instruction and off-day inclusion helper** ([behavior and acceptance](DEEP_WORK_SPECIFICATION.md#j-034))

    Status: **TODO** · Stage: **3** · Owner: _unassigned_  
    Evidence / commit: _none_  
    Blocker / notes: _none_  
    Swift: `DeepWork/Features/Journal/ActivityChartView.swift`, `DeepWork/Reports/ReportEngine.swift`

- [ ] **J-035 — Day off legend** ([behavior and acceptance](DEEP_WORK_SPECIFICATION.md#j-035))

    Status: **TODO** · Stage: **3** · Owner: _unassigned_  
    Evidence / commit: _none_  
    Blocker / notes: _none_  
    Swift: `DeepWork/Features/Journal/ActivityChartView.swift`, `DeepWork/Reports/ReportEngine.swift`

### Activity chart

**Progress:** 0 / 5 accepted.

- [ ] **J-029 — Bars, duration values, captions, and relative scale** ([behavior and acceptance](DEEP_WORK_SPECIFICATION.md#j-029))

    Status: **TODO** · Stage: **3** · Owner: _unassigned_  
    Evidence / commit: _none_  
    Blocker / notes: _none_  
    Swift: `DeepWork/Features/Journal/ActivityChartView.swift`, `DeepWork/Reports/ReportEngine.swift`

- [ ] **J-030 — Off-day, zero, and current-day visual states** ([behavior and acceptance](DEEP_WORK_SPECIFICATION.md#j-030))

    Status: **TODO** · Stage: **3** · Owner: _unassigned_  
    Evidence / commit: _none_  
    Blocker / notes: _none_  
    Swift: `DeepWork/Features/Journal/ActivityChartView.swift`, `DeepWork/Reports/ReportEngine.swift`

- [ ] **J-031 — Select a day or week to drill into its report** ([behavior and acceptance](DEEP_WORK_SPECIFICATION.md#j-031))

    Status: **TODO** · Stage: **3** · Owner: _unassigned_  
    Evidence / commit: _none_  
    Blocker / notes: _none_  
    Swift: `DeepWork/Features/Journal/ActivityChartView.swift`, `DeepWork/Reports/ReportEngine.swift`

- [ ] **J-032 — Bar accessibility and detailed tooltip** ([behavior and acceptance](DEEP_WORK_SPECIFICATION.md#j-032))

    Status: **TODO** · Stage: **3** · Owner: _unassigned_  
    Evidence / commit: _none_  
    Blocker / notes: _none_  
    Swift: `DeepWork/Features/Journal/ActivityChartView.swift`, `DeepWork/Reports/ReportEngine.swift`

- [ ] **J-033 — Scrollable chart frame** ([behavior and acceptance](DEEP_WORK_SPECIFICATION.md#j-033))

    Status: **TODO** · Stage: **3** · Owner: _unassigned_  
    Evidence / commit: _none_  
    Blocker / notes: _none_  
    Swift: `DeepWork/Features/Journal/ActivityChartView.swift`, `DeepWork/Reports/ReportEngine.swift`

### Sessions

**Progress:** 0 / 1 accepted.

- [ ] **J-036 — Sessions heading and result count** ([behavior and acceptance](DEEP_WORK_SPECIFICATION.md#j-036))

    Status: **TODO** · Stage: **3** · Owner: _unassigned_  
    Evidence / commit: _none_  
    Blocker / notes: _none_  
    Swift: `DeepWork/Features/Journal/SessionListView.swift`, `DeepWork/Features/Journal/JournalView.swift`

### Sessions table

**Progress:** 0 / 5 accepted.

- [ ] **J-037 — Four-column read-only session table** ([behavior and acceptance](DEEP_WORK_SPECIFICATION.md#j-037))

    Status: **TODO** · Stage: **3** · Owner: _unassigned_  
    Evidence / commit: _none_  
    Blocker / notes: _none_  
    Swift: `DeepWork/Features/Journal/SessionListView.swift`, `DeepWork/Features/Journal/JournalView.swift`

- [ ] **J-038 — Started date/time cell** ([behavior and acceptance](DEEP_WORK_SPECIFICATION.md#j-038))

    Status: **TODO** · Stage: **3** · Owner: _unassigned_  
    Evidence / commit: _none_  
    Blocker / notes: _none_  
    Swift: `DeepWork/Features/Journal/SessionListView.swift`, `DeepWork/Features/Journal/JournalView.swift`

- [ ] **J-039 — Ended date/time and live/paused state cell** ([behavior and acceptance](DEEP_WORK_SPECIFICATION.md#j-039))

    Status: **TODO** · Stage: **3** · Owner: _unassigned_  
    Evidence / commit: _none_  
    Blocker / notes: _none_  
    Swift: `DeepWork/Features/Journal/SessionListView.swift`, `DeepWork/Features/Journal/JournalView.swift`

- [ ] **J-040 — Focus time with planned or total detail** ([behavior and acceptance](DEEP_WORK_SPECIFICATION.md#j-040))

    Status: **TODO** · Stage: **3** · Owner: _unassigned_  
    Evidence / commit: _none_  
    Blocker / notes: _none_  
    Swift: `DeepWork/Features/Journal/SessionListView.swift`, `DeepWork/Features/Journal/JournalView.swift`

- [ ] **J-041 — Cycle status badge and Outside range helper** ([behavior and acceptance](DEEP_WORK_SPECIFICATION.md#j-041))

    Status: **TODO** · Stage: **3** · Owner: _unassigned_  
    Evidence / commit: _none_  
    Blocker / notes: _none_  
    Swift: `DeepWork/Features/Journal/SessionListView.swift`, `DeepWork/Features/Journal/JournalView.swift`

### Sessions pagination

**Progress:** 0 / 3 accepted.

- [ ] **J-043 — Pagination visibility and row-range status** ([behavior and acceptance](DEEP_WORK_SPECIFICATION.md#j-043))

    Status: **TODO** · Stage: **3** · Owner: _unassigned_  
    Evidence / commit: _none_  
    Blocker / notes: _none_  
    Swift: `DeepWork/Features/Journal/SessionListView.swift`, `DeepWork/Features/Journal/JournalView.swift`

- [ ] **J-044 — Previous page button** ([behavior and acceptance](DEEP_WORK_SPECIFICATION.md#j-044))

    Status: **TODO** · Stage: **3** · Owner: _unassigned_  
    Evidence / commit: _none_  
    Blocker / notes: _none_  
    Swift: `DeepWork/Features/Journal/SessionListView.swift`, `DeepWork/Features/Journal/JournalView.swift`

- [ ] **J-045 — Next page button** ([behavior and acceptance](DEEP_WORK_SPECIFICATION.md#j-045))

    Status: **TODO** · Stage: **3** · Owner: _unassigned_  
    Evidence / commit: _none_  
    Blocker / notes: _none_  
    Swift: `DeepWork/Features/Journal/SessionListView.swift`, `DeepWork/Features/Journal/JournalView.swift`

### Empty state

**Progress:** 0 / 2 accepted.

- [ ] **J-046 — No sessions illustration and message** ([behavior and acceptance](DEEP_WORK_SPECIFICATION.md#j-046))

    Status: **TODO** · Stage: **3** · Owner: _unassigned_  
    Evidence / commit: _none_  
    Blocker / notes: _none_  
    Swift: `DeepWork/Features/Journal/SessionListView.swift`, `DeepWork/Features/Journal/JournalView.swift`

- [ ] **J-047 — Start a focus cycle button** ([behavior and acceptance](DEEP_WORK_SPECIFICATION.md#j-047))

    Status: **TODO** · Stage: **3** · Owner: _unassigned_  
    Evidence / commit: _none_  
    Blocker / notes: _none_  
    Swift: `DeepWork/Features/Journal/SessionListView.swift`, `DeepWork/Features/Journal/JournalView.swift`

### Export

**Progress:** 0 / 4 accepted.

- [ ] **J-048 — Journal Export CSV button** ([behavior and acceptance](DEEP_WORK_SPECIFICATION.md#j-048))

    Status: **TODO** · Stage: **4** · Owner: _unassigned_  
    Evidence / commit: _none_  
    Blocker / notes: _none_  
    Swift: `DeepWork/Reports/ReportCSVExporter.swift`, `DeepWork/Features/Journal/JournalView.swift`, `DeepWork/Features/Settings/SettingsView.swift`

- [ ] **J-049 — CSV column contract and values** ([behavior and acceptance](DEEP_WORK_SPECIFICATION.md#j-049))

    Status: **TODO** · Stage: **4** · Owner: _unassigned_  
    Evidence / commit: _none_  
    Blocker / notes: _none_  
    Swift: `DeepWork/Reports/ReportCSVExporter.swift`, `DeepWork/Features/Journal/JournalView.swift`, `DeepWork/Features/Settings/SettingsView.swift`

- [ ] **J-050 — CSV filenames and export confirmation** ([behavior and acceptance](DEEP_WORK_SPECIFICATION.md#j-050))

    Status: **TODO** · Stage: **4** · Owner: _unassigned_  
    Evidence / commit: _none_  
    Blocker / notes: _none_  
    Swift: `DeepWork/Reports/ReportCSVExporter.swift`, `DeepWork/Features/Journal/JournalView.swift`, `DeepWork/Features/Settings/SettingsView.swift`

- [ ] **J-051 — Shared current-report and full-history scope rules** ([behavior and acceptance](DEEP_WORK_SPECIFICATION.md#j-051))

    Status: **TODO** · Stage: **4** · Owner: _unassigned_  
    Evidence / commit: _none_  
    Blocker / notes: _none_  
    Swift: `DeepWork/Reports/ReportCSVExporter.swift`, `DeepWork/Features/Journal/JournalView.swift`, `DeepWork/Features/Settings/SettingsView.swift`

### Storage

**Progress:** 0 / 1 accepted.

- [ ] **J-052 — Saved-on-device footer and failure message** ([behavior and acceptance](DEEP_WORK_SPECIFICATION.md#j-052))

    Status: **IN PROGRESS** · Stage: **1** · Owner: Codex  
    Evidence / commit: `./scripts/test.sh` — 99 native tests; [Stage 2 native evidence](docs/VERIFICATION.md#stage-2--focus-october-18-2026).  
    Blocker / notes: SQLite records/checkpoints and usable in-memory timing on failure pass native tests. CSV-on-failure remains Stage 4, so this cross-stage item is incomplete.  
    Swift: `DeepWork/Data/JournalStore.swift`, `DeepWork/Features/Journal/JournalView.swift`

### Live journal

**Progress:** 0 / 1 accepted.

- [ ] **J-053 — Actual history, active observations, and automatic refresh** ([behavior and acceptance](DEEP_WORK_SPECIFICATION.md#j-053))

    Status: **IN PROGRESS** · Stage: **3** · Owner: Codex  
    Evidence / commit: `./scripts/test.sh` — 99 native tests; [Stage 2 native evidence](docs/VERIFICATION.md#stage-2--focus-october-18-2026).  
    Blocker / notes: Engine exposes one live observation with current segments and stable identity; boundary/tab reconciliation is tested. Native journal metrics/table updates remain Stage 3.  
    Swift: `DeepWork/Core/TimerEngine.swift`, `DeepWork/Data/JournalStore.swift`, `DeepWork/Reports/ReportEngine.swift`

### Accessibility

**Progress:** 0 / 1 accepted.

- [ ] **J-054 — Journal controls, regions, focus, and statuses** ([behavior and acceptance](DEEP_WORK_SPECIFICATION.md#j-054))

    Status: **TODO** · Stage: **6** · Owner: _unassigned_  
    Evidence / commit: _none_  
    Blocker / notes: _none_  
    Swift: `DeepWork/Features/Journal/JournalView.swift`, `DeepWork/Accessibility/Announcements.swift`

## Journal work schedule

### Layout

**Progress:** 0 / 1 accepted.

- [ ] **W-001 — Nested work-schedule view** ([behavior and acceptance](DEEP_WORK_SPECIFICATION.md#w-001))

    Status: **TODO** · Stage: **3** · Owner: _unassigned_  
    Evidence / commit: _none_  
    Blocker / notes: _none_  
    Swift: `DeepWork/Features/Journal/WorkScheduleView.swift`, `DeepWork/Reports/WorkSchedule.swift`, `DeepWork/Reports/ReportEngine.swift`, `DeepWork/Data/JournalStore.swift`

### Draft editing

**Progress:** 0 / 1 accepted.

- [ ] **W-002 — Draft creation and mode-specific fields** ([behavior and acceptance](DEEP_WORK_SPECIFICATION.md#w-002))

    Status: **TODO** · Stage: **3** · Owner: _unassigned_  
    Evidence / commit: _none_  
    Blocker / notes: _none_  
    Swift: `DeepWork/Features/Journal/WorkScheduleView.swift`, `DeepWork/Reports/WorkSchedule.swift`, `DeepWork/Reports/ReportEngine.swift`, `DeepWork/Data/JournalStore.swift`

### Reporting days

**Progress:** 0 / 1 accepted.

- [ ] **W-003 — Reporting days selector** ([behavior and acceptance](DEEP_WORK_SPECIFICATION.md#w-003))

    Status: **TODO** · Stage: **3** · Owner: _unassigned_  
    Evidence / commit: _none_  
    Blocker / notes: _none_  
    Swift: `DeepWork/Features/Journal/WorkScheduleView.swift`, `DeepWork/Reports/WorkSchedule.swift`, `DeepWork/Reports/ReportEngine.swift`, `DeepWork/Data/JournalStore.swift`

### Chosen weekdays

**Progress:** 0 / 1 accepted.

- [ ] **W-004 — Seven independent weekday checkboxes** ([behavior and acceptance](DEEP_WORK_SPECIFICATION.md#w-004))

    Status: **TODO** · Stage: **3** · Owner: _unassigned_  
    Evidence / commit: _none_  
    Blocker / notes: _none_  
    Swift: `DeepWork/Features/Journal/WorkScheduleView.swift`, `DeepWork/Reports/WorkSchedule.swift`, `DeepWork/Reports/ReportEngine.swift`, `DeepWork/Data/JournalStore.swift`

### Any day

**Progress:** 0 / 1 accepted.

- [ ] **W-005 — Any-day explanation and semantics** ([behavior and acceptance](DEEP_WORK_SPECIFICATION.md#w-005))

    Status: **TODO** · Stage: **3** · Owner: _unassigned_  
    Evidence / commit: _none_  
    Blocker / notes: _none_  
    Swift: `DeepWork/Features/Journal/WorkScheduleView.swift`, `DeepWork/Reports/WorkSchedule.swift`, `DeepWork/Reports/ReportEngine.swift`, `DeepWork/Data/JournalStore.swift`

### Rotating shifts

**Progress:** 0 / 4 accepted.

- [ ] **W-006 — Work-day count** ([behavior and acceptance](DEEP_WORK_SPECIFICATION.md#w-006))

    Status: **TODO** · Stage: **3** · Owner: _unassigned_  
    Evidence / commit: _none_  
    Blocker / notes: _none_  
    Swift: `DeepWork/Features/Journal/WorkScheduleView.swift`, `DeepWork/Reports/WorkSchedule.swift`, `DeepWork/Reports/ReportEngine.swift`, `DeepWork/Data/JournalStore.swift`

- [ ] **W-007 — Rest-day count** ([behavior and acceptance](DEEP_WORK_SPECIFICATION.md#w-007))

    Status: **TODO** · Stage: **3** · Owner: _unassigned_  
    Evidence / commit: _none_  
    Blocker / notes: _none_  
    Swift: `DeepWork/Features/Journal/WorkScheduleView.swift`, `DeepWork/Reports/WorkSchedule.swift`, `DeepWork/Reports/ReportEngine.swift`, `DeepWork/Data/JournalStore.swift`

- [ ] **W-008 — First work day anchor** ([behavior and acceptance](DEEP_WORK_SPECIFICATION.md#w-008))

    Status: **TODO** · Stage: **3** · Owner: _unassigned_  
    Evidence / commit: _none_  
    Blocker / notes: _none_  
    Swift: `DeepWork/Features/Journal/WorkScheduleView.swift`, `DeepWork/Reports/WorkSchedule.swift`, `DeepWork/Reports/ReportEngine.swift`, `DeepWork/Data/JournalStore.swift`

- [ ] **W-009 — Pattern helper and calendar rotation** ([behavior and acceptance](DEEP_WORK_SPECIFICATION.md#w-009))

    Status: **TODO** · Stage: **3** · Owner: _unassigned_  
    Evidence / commit: _none_  
    Blocker / notes: _none_  
    Swift: `DeepWork/Features/Journal/WorkScheduleView.swift`, `DeepWork/Reports/WorkSchedule.swift`, `DeepWork/Reports/ReportEngine.swift`, `DeepWork/Data/JournalStore.swift`

### Week boundaries

**Progress:** 0 / 1 accepted.

- [ ] **W-010 — Week starts on selector** ([behavior and acceptance](DEEP_WORK_SPECIFICATION.md#w-010))

    Status: **TODO** · Stage: **3** · Owner: _unassigned_  
    Evidence / commit: _none_  
    Blocker / notes: _none_  
    Swift: `DeepWork/Features/Journal/WorkScheduleView.swift`, `DeepWork/Reports/WorkSchedule.swift`, `DeepWork/Reports/ReportEngine.swift`, `DeepWork/Data/JournalStore.swift`

### Reporting-day boundary

**Progress:** 0 / 1 accepted.

- [ ] **W-011 — Reporting day starts at field** ([behavior and acceptance](DEEP_WORK_SPECIFICATION.md#w-011))

    Status: **TODO** · Stage: **3** · Owner: _unassigned_  
    Evidence / commit: _none_  
    Blocker / notes: _none_  
    Swift: `DeepWork/Features/Journal/WorkScheduleView.swift`, `DeepWork/Reports/WorkSchedule.swift`, `DeepWork/Reports/ReportEngine.swift`, `DeepWork/Data/JournalStore.swift`

### Calendar and DST

**Progress:** 0 / 1 accepted.

- [ ] **W-012 — Local calendar grouping rules** ([behavior and acceptance](DEEP_WORK_SPECIFICATION.md#w-012))

    Status: **TODO** · Stage: **3** · Owner: _unassigned_  
    Evidence / commit: _none_  
    Blocker / notes: _none_  
    Swift: `DeepWork/Features/Journal/WorkScheduleView.swift`, `DeepWork/Reports/WorkSchedule.swift`, `DeepWork/Reports/ReportEngine.swift`, `DeepWork/Data/JournalStore.swift`

### Preview

**Progress:** 0 / 2 accepted.

- [ ] **W-013 — Next 14 days heading, legend, and preview layout** ([behavior and acceptance](DEEP_WORK_SPECIFICATION.md#w-013))

    Status: **TODO** · Stage: **3** · Owner: _unassigned_  
    Evidence / commit: _none_  
    Blocker / notes: _none_  
    Swift: `DeepWork/Features/Journal/WorkScheduleView.swift`, `DeepWork/Reports/WorkSchedule.swift`, `DeepWork/Reports/ReportEngine.swift`, `DeepWork/Data/JournalStore.swift`

- [ ] **W-014 — Fourteen draft-schedule date cells** ([behavior and acceptance](DEEP_WORK_SPECIFICATION.md#w-014))

    Status: **TODO** · Stage: **3** · Owner: _unassigned_  
    Evidence / commit: _none_  
    Blocker / notes: _none_  
    Swift: `DeepWork/Features/Journal/WorkScheduleView.swift`, `DeepWork/Reports/WorkSchedule.swift`, `DeepWork/Reports/ReportEngine.swift`, `DeepWork/Data/JournalStore.swift`

### Validation

**Progress:** 0 / 1 accepted.

- [ ] **W-015 — Draft validation error and save availability** ([behavior and acceptance](DEEP_WORK_SPECIFICATION.md#w-015))

    Status: **TODO** · Stage: **3** · Owner: _unassigned_  
    Evidence / commit: _none_  
    Blocker / notes: _none_  
    Swift: `DeepWork/Features/Journal/WorkScheduleView.swift`, `DeepWork/Reports/WorkSchedule.swift`, `DeepWork/Reports/ReportEngine.swift`, `DeepWork/Data/JournalStore.swift`

### Explanation

**Progress:** 0 / 1 accepted.

- [ ] **W-016 — Reporting-only and history-preservation footnote** ([behavior and acceptance](DEEP_WORK_SPECIFICATION.md#w-016))

    Status: **TODO** · Stage: **3** · Owner: _unassigned_  
    Evidence / commit: _none_  
    Blocker / notes: _none_  
    Swift: `DeepWork/Features/Journal/WorkScheduleView.swift`, `DeepWork/Reports/WorkSchedule.swift`, `DeepWork/Reports/ReportEngine.swift`, `DeepWork/Data/JournalStore.swift`

### Actions

**Progress:** 0 / 2 accepted.

- [ ] **W-017 — Cancel button** ([behavior and acceptance](DEEP_WORK_SPECIFICATION.md#w-017))

    Status: **TODO** · Stage: **3** · Owner: _unassigned_  
    Evidence / commit: _none_  
    Blocker / notes: _none_  
    Swift: `DeepWork/Features/Journal/WorkScheduleView.swift`, `DeepWork/Reports/WorkSchedule.swift`, `DeepWork/Reports/ReportEngine.swift`, `DeepWork/Data/JournalStore.swift`

- [ ] **W-018 — Save schedule button** ([behavior and acceptance](DEEP_WORK_SPECIFICATION.md#w-018))

    Status: **TODO** · Stage: **3** · Owner: _unassigned_  
    Evidence / commit: _none_  
    Blocker / notes: _none_  
    Swift: `DeepWork/Features/Journal/WorkScheduleView.swift`, `DeepWork/Reports/WorkSchedule.swift`, `DeepWork/Reports/ReportEngine.swift`, `DeepWork/Data/JournalStore.swift`

### Persistence

**Progress:** 0 / 1 accepted.

- [ ] **W-019 — Saved schedule and historical recalculation** ([behavior and acceptance](DEEP_WORK_SPECIFICATION.md#w-019))

    Status: **TODO** · Stage: **3** · Owner: _unassigned_  
    Evidence / commit: _none_  
    Blocker / notes: _none_  
    Swift: `DeepWork/Features/Journal/WorkScheduleView.swift`, `DeepWork/Reports/WorkSchedule.swift`, `DeepWork/Reports/ReportEngine.swift`, `DeepWork/Data/JournalStore.swift`

## Settings

### View structure

**Progress:** 0 / 1 accepted.

- [ ] **S-001 — Settings** ([behavior and acceptance](DEEP_WORK_SPECIFICATION.md#s-001))

    Status: **TODO** · Stage: **4** · Owner: _unassigned_  
    Evidence / commit: _none_  
    Blocker / notes: _none_  
    Swift: `DeepWork/Features/Settings/SettingsView.swift`

### General

**Progress:** 0 / 1 accepted.

- [ ] **S-002 — General** ([behavior and acceptance](DEEP_WORK_SPECIFICATION.md#s-002))

    Status: **TODO** · Stage: **4** · Owner: _unassigned_  
    Evidence / commit: _none_  
    Blocker / notes: _none_  
    Swift: `DeepWork/Features/Settings/SettingsView.swift`

### Launch at Login

**Progress:** 0 / 3 accepted.

- [ ] **S-003 — Launch at Login** ([behavior and acceptance](DEEP_WORK_SPECIFICATION.md#s-003))

    Status: **TODO** · Stage: **5** · Owner: _unassigned_  
    Evidence / commit: _none_  
    Blocker / notes: _none_  
    Swift: `DeepWork/Features/Settings/SettingsView.swift`, `DeepWork/Services/LoginItemService.swift`

- [ ] **S-004 — Open Deep Work automatically when you log in to your Mac.** ([behavior and acceptance](DEEP_WORK_SPECIFICATION.md#s-004))

    Status: **TODO** · Stage: **5** · Owner: _unassigned_  
    Evidence / commit: _none_  
    Blocker / notes: _none_  
    Swift: `DeepWork/Features/Settings/SettingsView.swift`, `DeepWork/Services/LoginItemService.swift`

- [ ] **S-005 — Preview — Your preference is saved here. Automatic launch will work in the Mac app.** ([behavior and acceptance](DEEP_WORK_SPECIFICATION.md#s-005))

    Status: **TODO** · Stage: **5** · Owner: _unassigned_  
    Evidence / commit: _none_  
    Blocker / notes: _none_  
    Swift: `DeepWork/Features/Settings/SettingsView.swift`, `DeepWork/Services/LoginItemService.swift`

### CSV export

**Progress:** 0 / 6 accepted.

- [ ] **S-006 — Export** ([behavior and acceptance](DEEP_WORK_SPECIFICATION.md#s-006))

    Status: **TODO** · Stage: **4** · Owner: _unassigned_  
    Evidence / commit: _none_  
    Blocker / notes: _none_  
    Swift: `DeepWork/Features/Settings/SettingsView.swift`, `DeepWork/Reports/ReportCSVExporter.swift`

- [ ] **S-007 — Include — All Sessions / Current Journal Report** ([behavior and acceptance](DEEP_WORK_SPECIFICATION.md#s-007))

    Status: **TODO** · Stage: **4** · Owner: _unassigned_  
    Evidence / commit: _none_  
    Blocker / notes: _none_  
    Swift: `DeepWork/Features/Settings/SettingsView.swift`, `DeepWork/Reports/ReportCSVExporter.swift`

- [ ] **S-008 — Export scope and availability summary** ([behavior and acceptance](DEEP_WORK_SPECIFICATION.md#s-008))

    Status: **TODO** · Stage: **4** · Owner: _unassigned_  
    Evidence / commit: _none_  
    Blocker / notes: _none_  
    Swift: `DeepWork/Features/Settings/SettingsView.swift`, `DeepWork/Reports/ReportCSVExporter.swift`

- [ ] **S-009 — Export to CSV…** ([behavior and acceptance](DEEP_WORK_SPECIFICATION.md#s-009))

    Status: **TODO** · Stage: **4** · Owner: _unassigned_  
    Evidence / commit: _none_  
    Blocker / notes: _none_  
    Swift: `DeepWork/Features/Settings/SettingsView.swift`, `DeepWork/Reports/ReportCSVExporter.swift`

- [ ] **S-010 — Shared CSV data contract** ([behavior and acceptance](DEEP_WORK_SPECIFICATION.md#s-010))

    Status: **TODO** · Stage: **4** · Owner: _unassigned_  
    Evidence / commit: _none_  
    Blocker / notes: _none_  
    Swift: `DeepWork/Features/Settings/SettingsView.swift`, `DeepWork/Reports/ReportCSVExporter.swift`

- [ ] **S-011 — Export result status** ([behavior and acceptance](DEEP_WORK_SPECIFICATION.md#s-011))

    Status: **TODO** · Stage: **4** · Owner: _unassigned_  
    Evidence / commit: _none_  
    Blocker / notes: _none_  
    Swift: `DeepWork/Features/Settings/SettingsView.swift`, `DeepWork/Reports/ReportCSVExporter.swift`

### Feedback

**Progress:** 0 / 9 accepted.

- [ ] **S-012 — Feedback** ([behavior and acceptance](DEEP_WORK_SPECIFICATION.md#s-012))

    Status: **TODO** · Stage: **4** · Owner: _unassigned_  
    Evidence / commit: _none_  
    Blocker / notes: _none_  
    Swift: `DeepWork/Features/Settings/SettingsView.swift`, `DeepWork/Data/SettingsStore.swift`, `DeepWork/Services/FeedbackClipboard.swift`

- [ ] **S-013 — This preview can save a draft or copy your feedback to share.** ([behavior and acceptance](DEEP_WORK_SPECIFICATION.md#s-013))

    Status: **TODO** · Stage: **4** · Owner: _unassigned_  
    Evidence / commit: _none_  
    Blocker / notes: _none_  
    Swift: `DeepWork/Features/Settings/SettingsView.swift`, `DeepWork/Data/SettingsStore.swift`, `DeepWork/Services/FeedbackClipboard.swift`

- [ ] **S-014 — Feedback type — Idea / Problem / General feedback** ([behavior and acceptance](DEEP_WORK_SPECIFICATION.md#s-014))

    Status: **TODO** · Stage: **4** · Owner: _unassigned_  
    Evidence / commit: _none_  
    Blocker / notes: _none_  
    Swift: `DeepWork/Features/Settings/SettingsView.swift`, `DeepWork/Data/SettingsStore.swift`, `DeepWork/Services/FeedbackClipboard.swift`

- [ ] **S-015 — Email (optional)** ([behavior and acceptance](DEEP_WORK_SPECIFICATION.md#s-015))

    Status: **TODO** · Stage: **4** · Owner: _unassigned_  
    Evidence / commit: _none_  
    Blocker / notes: _none_  
    Swift: `DeepWork/Features/Settings/SettingsView.swift`, `DeepWork/Data/SettingsStore.swift`, `DeepWork/Services/FeedbackClipboard.swift`

- [ ] **S-016 — Your feedback** ([behavior and acceptance](DEEP_WORK_SPECIFICATION.md#s-016))

    Status: **TODO** · Stage: **4** · Owner: _unassigned_  
    Evidence / commit: _none_  
    Blocker / notes: _none_  
    Swift: `DeepWork/Features/Settings/SettingsView.swift`, `DeepWork/Data/SettingsStore.swift`, `DeepWork/Services/FeedbackClipboard.swift`

- [ ] **S-017 — Feedback validation error** ([behavior and acceptance](DEEP_WORK_SPECIFICATION.md#s-017))

    Status: **TODO** · Stage: **4** · Owner: _unassigned_  
    Evidence / commit: _none_  
    Blocker / notes: _none_  
    Swift: `DeepWork/Features/Settings/SettingsView.swift`, `DeepWork/Data/SettingsStore.swift`, `DeepWork/Services/FeedbackClipboard.swift`

- [ ] **S-018 — Save Draft** ([behavior and acceptance](DEEP_WORK_SPECIFICATION.md#s-018))

    Status: **TODO** · Stage: **4** · Owner: _unassigned_  
    Evidence / commit: _none_  
    Blocker / notes: _none_  
    Swift: `DeepWork/Features/Settings/SettingsView.swift`, `DeepWork/Data/SettingsStore.swift`, `DeepWork/Services/FeedbackClipboard.swift`

- [ ] **S-019 — Copy Feedback** ([behavior and acceptance](DEEP_WORK_SPECIFICATION.md#s-019))

    Status: **TODO** · Stage: **4** · Owner: _unassigned_  
    Evidence / commit: _none_  
    Blocker / notes: _none_  
    Swift: `DeepWork/Features/Settings/SettingsView.swift`, `DeepWork/Data/SettingsStore.swift`, `DeepWork/Services/FeedbackClipboard.swift`

- [ ] **S-020 — Feedback result and saved-draft status** ([behavior and acceptance](DEEP_WORK_SPECIFICATION.md#s-020))

    Status: **TODO** · Stage: **4** · Owner: _unassigned_  
    Evidence / commit: _none_  
    Blocker / notes: _none_  
    Swift: `DeepWork/Features/Settings/SettingsView.swift`, `DeepWork/Data/SettingsStore.swift`, `DeepWork/Services/FeedbackClipboard.swift`

### Local settings persistence

**Progress:** 0 / 1 accepted.

- [ ] **S-021 — Settings saved on this device** ([behavior and acceptance](DEEP_WORK_SPECIFICATION.md#s-021))

    Status: **IN PROGRESS** · Stage: **1** · Owner: Codex  
    Evidence / commit: [Native verification, October 18, 2026](docs/VERIFICATION.md); `./scripts/test.sh`, compiled native app and macOS acceptance.  
    Blocker / notes: SQLite settings/defaults, explicit draft save/relaunch, corruption/failure warnings and journal independence implemented. Launch registration and clipboard/CSV behavior during failure remain in later stages.  
    Swift: `DeepWork/Data/SettingsStore.swift`, `DeepWork/Features/Settings/SettingsView.swift`

## Native release review

Before declaring the port complete, run AC-01 through AC-29 from the specification and record the results for the affected IDs above. Verify macOS integrations on an actual Mac. Keep unresolved implementation details visible rather than marking their preview state DONE.
