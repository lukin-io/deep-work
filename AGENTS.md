# Deep Work project instructions

## Sources and scope

- Read `README.md`, then the overview and implementation stages in `DEEP_WORK_SPECIFICATION.md`; read element details for the affected milestone before editing.
- The specification defines behavior and stable IDs. `IMPLEMENTATION_CHECKLIST.md` is the only progress tracker. `implementation-tracker.json` is an unchanged initial export.
- `reference/` is approved, read-only visual and behavior evidence. Do not modify it or replace requirements with new designs.
- Keep Focus, Journal, Settings; Work schedule belongs inside Journal. Record native choices and unresolved product decisions in `docs/NATIVE_DECISIONS.md`.

## Implementation conventions

- Swift/SwiftUI with AppKit for native window and keyboard behavior; macOS 13 minimum.
- One app-owned `AppModel`, independent of view/window lifetime. Keep value models and local stores lightweight and injectable. Never persist example records as actual history.
- Follow the October 18 native product clarification: red close/Command-W only hide the main window; running timers and menu-bar updates continue, and paused timers stay paused. Menu-bar click brings the existing Focus window to the front. Only Command-Q pauses, saves, drains and exits; relaunch stays paused. Protect recoverable edits on failed Quit saves and retain explicit Save Draft semantics. The approved application icon lives only in `DeepWork/Resources/Assets.xcassets/AppIcon.appiconset`; generate ICNS into build output and keep delivery archives out of build/test inputs.
- Persist journal records, configuration, schedule, settings, and explicitly saved feedback drafts in SQLite under the user-domain Application Support directory, using the app bundle ID (`app.deepwork.mac`) as its subdirectory. Resolve the directory through Foundation; do not hard-code a user's home path. Keep the original explicit Save Draft semantics.
- Preserve raw timestamps/segments. Validate versioned data at the storage boundary; serialize writes with SQLite transactions; expose failures without losing in-memory edits or overwriting unreadable data. Test migrations and preserve legacy source data until migration commits successfully.
- Keep future-stage integrations visibly unavailable; do not simulate success or count scaffolding as accepted behavior.
- Tests belong in `DeepWorkTests`; use stable element IDs in relevant test names/evidence. Do not change unrelated files.
- This testing policy applies automatically to every new task, new feature, edit to an existing feature, refactor, and bug fix. Include test planning, implementation, and verification in the work without waiting for a separate request or reminder.
- Every feature change must include relevant unit tests and integration/acceptance tests. Follow Swift, Apple, and software engineering testing practices: use Swift Testing or XCTest for native behavior, deterministic injected clocks/services, isolated fixtures, and assertions about observable behavior rather than implementation details. Exercise real SQLite and native platform boundaries in integration tests where applicable.
- Cover true and false branches, successful and failed operations, and nil/null or missing optional values wherever the contract permits them. Also cover empty, invalid, and boundary inputs, state transitions, and affected persistence/recovery or concurrency cases. Select meaningful cases for the changed behavior; do not invent null states for nonoptional Swift types or add assertions solely to inflate coverage.
- Every bug fix must include regression coverage with the fix: reproduce the failing scenario, then verify the corrected behavior and relevant unaffected cases. Prefer an automated regression test; use explicit reproducible native acceptance cases for behavior that cannot reasonably be automated, recording that limitation. Do not defer coverage to a later milestone.
- If tooling prevents a required test, record its exact blocker and leave the affected acceptance unverified in the checklist.

## Swift and software engineering practices

- Apply these practices to new features, existing features, refactors, and bug fixes. Prefer the smallest clear design that satisfies the specification; avoid speculative layers and unrelated cleanup.
- Follow Apple's current recommendations, API documentation, Human Interface Guidelines, and platform guidelines for Swift, SwiftUI, AppKit, accessibility, concurrency, application lifecycle, security, and data storage. Prefer supported native APIs; verify relevant official guidance when choosing or changing platform behavior. Record any intentional departure and its reason while preserving the approved product contract.
- Use typed value models and enums for domain states, explicit access control, small cohesive types, and descriptive Swift API names. Avoid force unwraps/casts in fallible production paths; handle missing or invalid input deliberately.
- Keep UI mutation on `@MainActor`; isolate mutable shared state and serialize persistence. Respect Swift concurrency/Sendable boundaries and cancellation; avoid long blocking work on the UI thread. Do not drive accounting from UI refresh ticks.
- Keep business rules outside views; inject storage, clocks, and platform services where needed for deterministic tests. Views render shared state and dispatch intentions rather than owning duplicate domain state.
- Preserve invariants at decoding and mutation boundaries. Surface actionable failures, preserve recoverable data, and never claim success before the underlying operation succeeds.
- Use native accessibility, keyboard, lifecycle, and adaptive layout conventions; verify these behaviors on macOS. Record intentional departures from the reference before accepting them.
- Before changing code, understand its callers, data contracts, and failure modes. Add the relevant regression coverage with the change, run focused tests and compilation, and broaden checks when affected behavior warrants it.
- Keep dependencies minimal, retain compatibility intentionally, and document schema/API/rollout decisions. Never log secrets or private feedback content.

## Build and verification

- Verified locally: `./scripts/test.sh` runs 109 native Swift tests plus 12 native icon packaging checks; `./scripts/build-app.sh` compiles and packages `.build/Deep Work.app`; `open ".build/Deep Work.app"` launches it. Current results and environment limits are in `docs/VERIFICATION.md`.
- `plutil -lint DeepWork/Resources/Info.plist DeepWork.xcodeproj/project.pbxproj` validates project/plist syntax. Regenerate explicit Xcode references with `python3 scripts/generate-xcode-project.py` after adding/removing app or core test sources.
- Stages 1–2 were compiled with Swift 6.4 and the Command Line Tools macOS SDK. Full Xcode is not installed; never claim `xcodebuild` verification until it succeeds. Xcode 16+ instructions are in `README.md`.
- `swift build -Xswiftc -strict-concurrency=complete` verifies production concurrency checking. Require complete Swift Testing summaries; the test script rejects premature hostless exits even when SwiftPM returns success.
- Nest AppKit integration suites under serialized `NativeApplicationTests`. For hostless status-button and window-close integration, dispatch the real native button target/action with `sendAction`; synthetic `performClick`/`performClose` can stop SwiftPM’s main run loop. Test foreground activation, real red close, Command-W, and Quit failure choices through the compiled app; record adapter boundaries explicitly.
- Run native model/store tests, compile the native app, and exercise changed window/navigation behavior. JavaScript reference tests are not native completion evidence.

## Progress updates

- Update existing IDs in `IMPLEMENTATION_CHECKLIST.md`, with actual commands/results and remaining acceptance checks. Mark DONE only when the entire item's native acceptance passes; keep cross-stage items IN PROGRESS.
- Record milestone evidence in `docs/VERIFICATION.md`; update checklist rollups consistently. Do not maintain a second progress tracker.
- Always keep `README.md` current with required setup, dependencies, build/test/run commands, migration steps, and known tooling limits whenever implementation changes them.
- Report local compile, native tests, UI observations, and unverified tooling separately.

## Commit and pull request writing

- Use `/Users/sesharim/.codex/skills/caveman-commit/SKILL.md` for commit messages; use the same concise intent-first style for PR titles/descriptions.
- Use Conventional Commits. Explain non-obvious reasons, behavior changes, migration/rollout requirements, and unresolved limitations without shortening away meaningful context.
- PR descriptions must explain the problem and before/after behavior, actual validation, exact target branch, and remaining dependencies without relying on the conversation. Never describe partial implementation or unverified deployment as complete.
