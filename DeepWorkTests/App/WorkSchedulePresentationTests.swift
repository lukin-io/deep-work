import AppKit
import SwiftUI
import Testing
import DeepWorkCore
@testable import DeepWorkApp

extension NativeApplicationTests {
@Suite(.serialized)
@MainActor
struct WorkSchedulePresentationTests {
    @Test(arguments: [244, 620], [false, true])
    func testW004_W013_AC29WeekdayButtonsWrapAtNarrowWidthWithoutCompressingLabels(_ width: Int, _ dark: Bool) async throws {
        prepareNativeTestApplication()
        // These are the available widths inside the production Surface at
        // 320-point and 696-point root widths (24 + 14 padding on each side).
        let grid = ScheduleWeekdayButtons(weekdays: [.monday, .friday], setWeekday: { _, _ in })
            .font(.system(size: 12)).frame(width: CGFloat(width))
        let host = NSHostingView(rootView: grid)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: CGFloat(width), height: 160),
                              styleMask: [.titled], backing: .buffered, defer: false)
        let appearance: NSAppearance.Name = dark ? .darkAqua : .aqua
        window.appearance = NSAppearance(named: appearance)
        window.contentView = host
        window.orderFront(nil)
        defer { window.orderOut(nil) }
        try await waitUntil(in: host) { host.fittingSize.height > 0 }
        #expect(abs(host.fittingSize.width - CGFloat(width)) < 1)
        #expect(host.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == appearance)
        if width == 244 {
            #expect(host.fittingSize.height >= 48,
                    "The narrow schedule must wrap the seven native button labels into multiple rows")
        } else {
            #expect(host.fittingSize.height <= 32,
                    "The ordinary-width schedule must preserve the seven buttons on one row")
        }
        // Fitting height proves the row change, not pixel legibility. The
        // compiled-app regression checks all seven untruncated labels and AX IDs.
    }

    @Test(arguments: [320, 696])
    func testW006_W007_W008_AC29RotatingFieldsFitAndAnchorMovesBelowCountsWhenNarrow(_ width: Int) async throws {
        prepareNativeTestApplication()
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("DeepWorkNarrowShifts-\(UUID())")
        defer { try? FileManager.default.removeItem(at: directory) }
        let model = AppModel(journalStore: JournalStore(directory: directory), settingsStore: SettingsStore(directory: directory),
                             clock: TestTimerClock(), automaticRefresh: false, reportingTimeZone: .gmt)
        model.openSchedule()
        model.updateScheduleDraft {
            $0.mode = .rotatingShifts; $0.workDaysText = "3"; $0.restDaysText = "4"
            $0.firstWorkDayText = "2026-10-19"
        }
        let host = NSHostingView(rootView: RootView(model: model))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: CGFloat(width), height: 740),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = host
        window.orderFront(nil)
        defer { window.orderOut(nil) }
        let work = try await textField(in: host, value: "3")
        let rest = try await textField(in: host, value: "4")
        let anchor = try await textField(in: host, value: "2026-10-19")
        let workRect = work.convert(work.bounds, to: host)
        let restRect = rest.convert(rest.bounds, to: host)
        let anchorRect = anchor.convert(anchor.bounds, to: host)
        for rect in [workRect, restRect, anchorRect] {
            #expect(rect.width >= 40 && rect.minX >= 0 && rect.maxX <= host.bounds.width)
        }
        #expect(abs(workRect.midY - restRect.midY) < 1)
        #expect(workRect.maxX < restRect.minX)
        if width == 320 {
            #expect(abs(anchorRect.midY - workRect.midY) > workRect.height,
                    "The first-work-day field must move to a separate row without compressing Work/Rest")
        } else {
            #expect(abs(anchorRect.maxY - workRect.maxY) < 2,
                    "The ordinary-width editor keeps the counts and anchor together")
        }
        await model.flushPersistence()
        #expect(model.journal.schedule.mode == .chosenWeekdays, "Layout never commits the transient schedule draft")
    }

    @Test func testW002_G012ScheduleFocusHonorsKeyboardNavigationAndTabReturnDoesNotStealFocus() async throws {
        prepareNativeTestApplication()
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("DeepWorkScheduleFocus-\(UUID())")
        defer { try? FileManager.default.removeItem(at: directory) }
        let app = AppModel(journalStore: JournalStore(directory: directory), settingsStore: SettingsStore(directory: directory),
                           clock: TestTimerClock(), automaticRefresh: false, reportingTimeZone: .gmt)
        let controller = WindowController(model: app)
        let window = try #require(controller.window)
        controller.showWindow(nil)
        defer { window.orderOut(nil) }
        let content = try #require(window.contentView)
        try await waitUntil(in: content) { nativeViews(TabSegmentedControl.self, in: content).count == 1 }
        let tabs = try #require(nativeViews(TabSegmentedControl.self, in: content).first)
        try #require(window.makeFirstResponder(tabs))
        app.openSchedule()
        // The editable cutoff proves that the production editor is inserted.
        // SwiftUI does not promise an NSPopUpButton implementation for Picker;
        // use its public accessibility representation when the host exposes it.
        _ = try await textField(in: content, value: "00:00")
        let mode = await scheduleModeAccessibilityElement(in: content)
        if let mode {
            #expect(mode.accessibilityRole() == .popUpButton)
            #expect(mode.accessibilityLabel() == "Reporting days")
            if NSApplication.shared.isFullKeyboardAccessEnabled {
                try await waitUntil(in: content) { mode.isAccessibilityFocused() }
                #expect(mode.isAccessibilityFocused())
            } else {
                print("W-002: macOS Keyboard navigation is disabled; mode-picker focus is unverified on this runner. The test does not change the user's preference.")
            }
        } else {
            #expect((content.accessibilityChildren() ?? []).isEmpty,
                    "A populated accessibility tree must contain the schedule-mode control")
            print("W-002: hostless SwiftUI accessibility tree is unavailable. Native editor insertion passed; mode-picker accessibility/focus remains unverified here and requires compiled-app acceptance.")
        }

        try #require(window.makeFirstResponder(tabs))
        try press(119, in: window) // End selects Settings.
        try await Task.sleep(for: .milliseconds(100))
        #expect(app.selectedTab == .settings && window.firstResponder === tabs)
        try press(123, in: window) // Left returns to Journal with the same draft.
        _ = try await textField(in: content, value: "00:00")
        try await Task.sleep(for: .milliseconds(100))
        #expect(app.selectedTab == .journal && app.scheduleDraft != nil)
        #expect(window.firstResponder === tabs)
        await app.flushPersistence()
    }

    @Test func testW002_W006_W011NativeTextFieldsKeepInvalidDraftEditsWithoutChangingSavedSchedule() async throws {
        prepareNativeTestApplication()
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("DeepWorkScheduleUI-\(UUID())")
        defer { try? FileManager.default.removeItem(at: directory) }
        let saved = WorkSchedule(mode: .rotatingShifts, workDays: 3, restDays: 4,
                                 firstWorkDay: CivilDate(year: 2026, month: 10, day: 19), reportingDayStartMinutes: 240)
        #expect(JournalStore(directory: directory).save(JournalDocument(schedule: saved)) == nil)
        let app = AppModel(journalStore: JournalStore(directory: directory), settingsStore: SettingsStore(directory: directory),
                           clock: TestTimerClock(), automaticRefresh: false, reportingTimeZone: .gmt)
        await app.flushPersistence()
        app.openSchedule()
        let host = NSHostingView(rootView: WorkScheduleView(model: app).padding(24))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 696, height: 740),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = host
        window.orderFront(nil)
        defer { window.orderOut(nil) }

        let workField = try await textField(in: host, value: "3")
        let restField = try await textField(in: host, value: "4")
        let anchorField = try await textField(in: host, value: "2026-10-19")
        let cutoffField = try await textField(in: host, value: "04:00")
        #expect(workField.isEditable && restField.isEditable && anchorField.isEditable && cutoffField.isEditable)
        #expect(workField.isEnabled && cutoffField.isEnabled)

        // Exercise the native text-editing delegate boundary used by SwiftUI;
        // physical typing and complete VoiceOver traversal are recorded separately.
        workField.stringValue = "1.5"
        workField.delegate?.controlTextDidChange?(Notification(name: NSControl.textDidChangeNotification, object: workField))
        try await waitUntil(in: host) { app.scheduleDraft?.workDaysText == "1.5" }
        #expect(app.scheduleDraft?.validationError == "Choose 1–31 work days and 1–31 rest days.")
        #expect(app.journal.schedule == saved)

        app.updateScheduleDraft { $0.workDaysText = ""; $0.reportingDayStartText = "24:00" }
        try await waitUntil(in: host) { workField.stringValue.isEmpty && cutoffField.stringValue == "24:00" }
        #expect(app.journal.schedule == saved)
        app.updateScheduleDraft { $0.workDaysText = "31"; $0.reportingDayStartText = "23:59" }
        try await waitUntil(in: host) { workField.stringValue == "31" && cutoffField.stringValue == "23:59" }
        #expect(app.scheduleDraft?.validationError == nil)
        #expect(app.journal.schedule == saved)
        await app.flushPersistence()
        #expect(JournalStore(directory: directory).load().value.schedule == saved)
    }

    private func textField(in host: NSView, value: String) async throws -> NSTextField {
        try await waitUntil(in: host) { nativeTextFields(in: host).contains { $0.isEditable && $0.stringValue == value } }
        return try #require(nativeTextFields(in: host).first { $0.isEditable && $0.stringValue == value },
                            "Expected the production schedule editor to create a native text field")
    }

    private func nativeTextFields(in view: NSView) -> [NSTextField] {
        nativeViews(NSTextField.self, in: view)
    }

    private func nativeViews<ViewType: NSView>(_ type: ViewType.Type, in view: NSView) -> [ViewType] {
        let current = (view as? ViewType).map { [$0] } ?? []
        return current + view.subviews.flatMap { nativeViews(type, in: $0) }
    }

    private func scheduleModeAccessibilityElement(in content: NSView) async -> (any NSAccessibilityProtocol)? {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: .seconds(3))
        while clock.now < deadline {
            content.layoutSubtreeIfNeeded()
            if let mode = accessibleElements(content).first(where: { $0.accessibilityIdentifier() == "dw-schedule-mode" }) {
                return mode
            }
            do { try await Task.sleep(for: .milliseconds(10)) } catch { return nil }
        }
        return nil
    }

    private func accessibleElements(_ item: Any, depth: Int = 0) -> [any NSAccessibilityProtocol] {
        guard depth < 30, let element = item as? any NSAccessibilityProtocol else { return [] }
        return [element] + (element.accessibilityChildren() ?? []).flatMap { accessibleElements($0, depth: depth + 1) }
    }

    private func press(_ code: UInt16, in window: NSWindow) throws {
        let event = try #require(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
                                                windowNumber: window.windowNumber, context: nil, characters: "",
                                                charactersIgnoringModifiers: "", isARepeat: false, keyCode: code))
        let responder = try #require(window.firstResponder)
        responder.keyDown(with: event)
    }

    private func waitUntil(in host: NSView, condition: () -> Bool) async throws {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: .seconds(3))
        while clock.now < deadline {
            host.layoutSubtreeIfNeeded()
            if condition() { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        try #require(condition(), "Native schedule controls did not reflect the expected state before the deadline")
    }
}
}
