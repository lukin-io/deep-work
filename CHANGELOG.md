# Changelog

One consolidated entry per PR or stage, newest first. Follow-up commits update the same entry. Detailed acceptance and test evidence stay in [the checklist](IMPLEMENTATION_CHECKLIST.md) and [verification](docs/VERIFICATION.md).

## Stage 5 — Native services

**Unreleased.** Source branch: `codex/native-services-stage-5`.

- Add native Settings and Redo commands; keep menu actions on the retained app window and shared timer.
- Register Launch at Login through macOS, showing actual approval, revocation and failure states without saving unfinished feedback edits.
- Add Slack PKCE sign-in, Keychain token rotation, focus-status ownership and conditional restoration on break/end/Quit/disconnect. Preserve manual changes and pending recovery after failures; notifications are unchanged.
- Migrate SQLite schema 1 → 2 without rewriting existing records; older app versions cannot reopen the migrated store. Include setup instructions and native tests; real logout/login and configured live Slack verification remain pending.

## Stage 4 — CSV export and feedback ([PR #3](https://github.com/lukin-io/deep-work/pull/3))

**Unreleased.** Merged into `main` through PR #3.

- Save Journal reports and Settings All Sessions/Current Journal Report through a native CSV Save panel, including every matching row across pagination and precise live-session accounting.
- Share one CSV format and snapshot across both paths; preserve actual/example separation, truthful cancellation and failures, and wait for accepted writes before Quit.
- Validate, explicitly save and restore feedback drafts in SQLite; copy current feedback without saving or sending it. Support native multiline editing, Undo/Redo and validation focus.
- Preserve existing data without a schema migration. Add native unit, SQLite/AppKit integration and compiled-app acceptance checks; remaining keyboard/VoiceOver checks stay in the checklist. Launch at Login and Slack remain Stage 5.

## Stage 3 — Journal and work schedule ([PR #2](https://github.com/lukin-io/deep-work/pull/2))

**Unreleased.** Merged into `main` through PR #2.

- Add Day, Week and custom Range reports with focus time, completed cycles, days with focus, activity drilldown and paginated session history.
- Show live/paused sessions and separate example data without saving examples as real history.
- Add weekday, Any day and rotating work schedules, with week start, reporting-day cutoff and a 14-day preview. SQLite saves preserve drafts on failure and retain timer updates during slow writes or Quit.
- Preserve existing history without a database migration. CSV export remains Stage 4; remaining keyboard, VoiceOver and visual acceptance checks are recorded in the checklist.

## Stages 1–2 — Native app and focus timer ([PR #1](https://github.com/lukin-io/deep-work/pull/1))

- Add the native SwiftUI/AppKit app with Focus, Journal and Settings, shared application state, the approved icon and durable SQLite storage.
- Add focus/break controls, Repeat, exact focus accounting and checkpoint recovery. Closing the window keeps timers running; the menu-bar timer reopens Focus. Quit pauses and saves, and relaunch stays paused until Resume.
- Support Apple Silicon and macOS 15+. Add native CI, Xcode Release builds and downloadable previews with checksums and source metadata.
- Publish the Stage 1/2 app baseline as [v0.1.0-preview.1](https://github.com/lukin-io/deep-work/releases/tag/v0.1.0-preview.1). It is ad hoc signed and unnotarized; later CI and release-policy updates in this PR do not change that published build. See [installation, compatibility and limitations](docs/releases/v0.1.0-preview.1.md).
