# Changelog

One consolidated entry per PR or stage, newest first. Follow-up commits update the same entry. Detailed acceptance and test evidence stay in [the checklist](IMPLEMENTATION_CHECKLIST.md) and [verification](docs/VERIFICATION.md).

## Stage 3 — Journal and work schedule ([PR #2](https://github.com/lukin-io/deep-work/pull/2))

**Unreleased.** Available from source on `feature/journal-stage-3`.

- Add Day, Week and custom Range reports with focus time, completed cycles, days with focus, activity drilldown and paginated session history.
- Show live/paused sessions and separate example data without saving examples as real history.
- Add weekday, Any day and rotating work schedules, with week start, reporting-day cutoff and a 14-day preview. SQLite saves preserve drafts on failure and retain timer updates during slow writes or Quit.
- Preserve existing history without a database migration. CSV export remains Stage 4; remaining keyboard, VoiceOver and visual acceptance checks are recorded in the checklist.

## Stages 1–2 — Native app and focus timer ([PR #1](https://github.com/lukin-io/deep-work/pull/1))

- Add the native SwiftUI/AppKit app with Focus, Journal and Settings, shared application state, the approved icon and durable SQLite storage.
- Add focus/break controls, Repeat, exact focus accounting and checkpoint recovery. Closing the window keeps timers running; the menu-bar timer reopens Focus. Quit pauses and saves, and relaunch stays paused until Resume.
- Support Apple Silicon and macOS 15+. Add native CI, Xcode Release builds and downloadable previews with checksums and source metadata.
- Publish the Stage 1/2 app baseline as [v0.1.0-preview.1](https://github.com/lukin-io/deep-work/releases/tag/v0.1.0-preview.1). It is ad hoc signed and unnotarized; later CI and release-policy updates in this PR do not change that published build. See [installation, compatibility and limitations](docs/releases/v0.1.0-preview.1.md).
