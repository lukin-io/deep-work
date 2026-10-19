import AppKit
import SwiftUI
import Testing
import DeepWorkCore
@testable import DeepWorkApp

struct JournalFormattingTests {
    private var utc: TimeZone { TimeZone(secondsFromGMT: 0)! }
    private var start: Date { Date(timeIntervalSince1970: 1_792_396_800) }

    @Test func testJ038J040ClippedRowsKeepOriginalTimestampsAndFullFocusDetail() {
        let record = session(outcome: .complete)
        let row = JournalReportRow(record: record, focusedSeconds: 60.9, totalFocusedSeconds: 3_600, completedInRange: false)
        let value = JournalRowPresentation(row: row, paused: false, timeZone: utc)
        #expect(value.startedDate == JournalPresentation.date(record.startedAt, pattern: "MMM d", timeZone: utc))
        #expect(value.startedHelp.contains("2026"))
        #expect(value.startedHelp.contains(":00"))
        #expect(value.endedHelp == JournalPresentation.fullTimestamp(record.endedAt, timeZone: utc))
        #expect(value.focus == "1m")
        #expect(value.focusDetail == "1h 0m total")
        #expect(value.cycle == "Complete")
        #expect(value.cycleDetail == "Outside range")
    }

    @Test func testJ040J041CompletionOnlyAndPartialRowsRetainCorrectLabels() {
        let complete = JournalRowPresentation(row: JournalReportRow(record: session(outcome: .complete), focusedSeconds: 0,
            totalFocusedSeconds: 3_600, completedInRange: true), paused: false, timeZone: utc)
        #expect(complete.focus == "0s")
        #expect(complete.cycle == "Complete")
        #expect(complete.cycleDetail.isEmpty)
        let partial = JournalRowPresentation(row: JournalReportRow(record: session(outcome: .partial), focusedSeconds: 59.9,
            totalFocusedSeconds: 59.9, completedInRange: false), paused: true, timeZone: utc)
        #expect(partial.focus == "59s")
        #expect(partial.focusDetail == "1h planned")
        #expect(partial.cycle == "Partial")
        #expect(!partial.isLive)
    }

    @Test func testJ040PlannedDurationUsesCompactHoursAndMinutes() {
        var record = session(outcome: .partial)
        record.plannedFocusMinutes = 90
        let value = JournalRowPresentation(row: JournalReportRow(record: record, focusedSeconds: 3_600,
            totalFocusedSeconds: 3_600, completedInRange: false), paused: false, timeZone: utc)
        #expect(value.focusDetail == "1h 30m planned")
        #expect(value.isPartial)
    }

    @Test(arguments: [false, true])
    func testJ039J041LiveAndPausedTextCarryMeaningWithoutColor(_ paused: Bool) {
        let value = JournalRowPresentation(row: JournalReportRow(record: session(outcome: .live), focusedSeconds: 23,
            totalFocusedSeconds: 23, completedInRange: false), paused: paused, timeZone: utc)
        #expect(value.endedDate == (paused ? "Paused" : "In progress"))
        #expect(value.endedTime == "Current session")
        #expect(value.endedHelp.hasPrefix("Observed "))
        #expect(value.cycle == (paused ? "Paused" : "Live"))
        #expect(value.cycleDetail.isEmpty)
        #expect(value.isLive)
    }

    @Test func testJ032BucketDescriptionIncludesDurationCyclesOffDayAndDrilldown() {
        let bucket = JournalBucket(key: CivilDate(start, timeZone: utc), start: start, end: start.addingTimeInterval(86_400),
                                   focusedSeconds: 60.9, completedCycles: 1, scheduledDays: 0)
        let day = JournalPresentation.bucketDescription(bucket, grouping: .day, timeZone: utc)
        #expect(day.contains("2026"))
        #expect(day.contains("1m, 1 completed cycle, day off"))
        #expect(day.hasSuffix("Open day report."))
        let week = JournalPresentation.bucketDescription(bucket, grouping: .week, timeZone: utc)
        #expect(week.hasPrefix("Week of "))
        #expect(!week.contains("day off"))
        #expect(week.hasSuffix("Open week report."))
    }

    @Test func testJ029ZeroAndInvalidValuesKeepVisibleBaselineAndRelativeScale() {
        for seconds in [0, -1, .nan, .infinity] {
            #expect(JournalPresentation.barHeight(seconds: seconds, maximum: 600) == 3)
        }
        #expect(JournalPresentation.barHeight(seconds: 300, maximum: 600) == 52.5)
        #expect(JournalPresentation.barHeight(seconds: 600, maximum: 600) == 105)
        #expect(JournalPresentation.barHeight(seconds: 900, maximum: 600) == 105)
        #expect(JournalPresentation.barHeight(seconds: 0.1, maximum: 600) == 3)
        #expect(JournalPresentation.barHeight(seconds: 30, maximum: 0) == 3)
    }

    @Test @MainActor func testJ029J033ColumnMinimumAdaptsToNativeTextWithoutShrinkingExistingBaseline() {
        let bucket = JournalBucket(key: CivilDate(start, timeZone: utc), start: start,
                                   end: start + 86_400, focusedSeconds: 0, completedCycles: 0, scheduledDays: 0)
        #expect(JournalPresentation.minimumChartColumnWidth(buckets: [], grouping: .day,
            shortWeekdayLabels: true, timeZone: utc) == 35)
        #expect(JournalPresentation.minimumChartColumnWidth(buckets: [bucket], grouping: .day,
            shortWeekdayLabels: true, timeZone: utc) == 35)
        #expect(JournalPresentation.minimumChartColumnWidth(buckets: Array(repeating: bucket, count: 15), grouping: .day,
            shortWeekdayLabels: true, timeZone: utc) == 44)
        #expect(JournalPresentation.bucketCaption(bucket, grouping: .week, shortWeekdayLabels: true, timeZone: utc)
            == JournalPresentation.date(start, pattern: "MMM d", timeZone: utc))
    }

    private func session(outcome: SessionOutcome) -> SessionRecord {
        SessionRecord(startedAt: start, endedAt: start.addingTimeInterval(3_600), plannedFocusMinutes: 60,
                      outcome: outcome, segments: [ActiveSegment(startedAt: start, endedAt: start.addingTimeInterval(3_600))])
    }
}

extension NativeApplicationTests {
@Suite(.serialized)
@MainActor
struct JournalPresentationTests {
    @Test(arguments: [JournalGrouping.day, .week])
    func testJ029_J033NarrowChartKeepsFullDurationAndDateLabelsInsideScrollableColumns(_ grouping: JournalGrouping) async throws {
        prepareNativeTestApplication()
        let start = Date(timeIntervalSince1970: 1_792_396_800)
        let seconds: TimeInterval = grouping == .day ? 3.5 * 3_600 : 167 * 3_600 + 59 * 60
        let dayStep: TimeInterval = grouping == .day ? 86_400 : 7 * 86_400
        let buckets = (0..<7).map { index in
            let date = start + Double(index) * dayStep
            return JournalBucket(key: CivilDate(date, timeZone: .gmt), start: date, end: date + dayStep,
                                 focusedSeconds: seconds, completedCycles: 3, scheduledDays: 1)
        }
        let host = NSHostingView(rootView: JournalActivityChart(buckets: buckets, grouping: grouping,
            shortWeekdayLabels: grouping == .day, today: buckets[0].key, timeZone: .gmt, open: { _ in })
            .padding(24).frame(width: 320, height: 217))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 320, height: 217),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = host
        window.orderFront(nil)
        defer { window.orderOut(nil) }
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: .seconds(3))
        while findScrollView(in: host) == nil && clock.now < deadline {
            host.layoutSubtreeIfNeeded()
            try await Task.sleep(for: .milliseconds(10))
        }
        host.layoutSubtreeIfNeeded()
        let scroll = try #require(findScrollView(in: host))
        let document = try #require(scroll.documentView)
        let duration = JournalDuration.format(seconds: seconds, precise: false)
        #expect(duration == (grouping == .day ? "3h 30m" : "167h 59m"))
        let durationWidth = (duration as NSString).size(withAttributes: [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 10, weight: .regular)
        ]).width
        let dateWidth = buckets.map {
            (JournalPresentation.date($0.start, pattern: grouping == .day ? "EEE" : "MMM d", timeZone: .gmt) as NSString)
                .size(withAttributes: [.font: NSFont.systemFont(ofSize: 10, weight: .semibold)]).width
        }.max() ?? 0
        let requiredColumnWidth = ceil(max(durationWidth, dateWidth))
        let requiredDocumentWidth = requiredColumnWidth * 7 + 9 * 6
        #expect(document.bounds.width >= requiredDocumentWidth,
                "Full duration/date text must fit each chart column, including at 320 pt; scroll instead of truncating")
        #expect(scroll.contentView.bounds.width <= 272)
        #expect(document.bounds.width > scroll.contentView.bounds.width)
        // The real scroll extent is mandatory. Pixel/readability and keyboard
        // focus retention are separately checked in the compiled application.
    }

    @Test(arguments: [320, 696], [false, true])
    func testJ002NativeJournalRetainsRangeControlsAndScrollableDataAtBothWidthsAndAppearances(_ width: Int, _ dark: Bool) async throws {
        prepareNativeTestApplication()
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("DeepWorkJournalLayout-\(UUID())")
        defer { try? FileManager.default.removeItem(at: directory) }
        let clock = TestTimerClock()
        clock.date = Date(timeIntervalSince1970: 1_792_396_800)
        let model = AppModel(journalStore: JournalStore(directory: directory), settingsStore: SettingsStore(directory: directory),
                             clock: clock, automaticRefresh: false, reportingTimeZone: .gmt)
        await model.flushPersistence()
        model.reportPeriod = .range
        model.rangeFromText = "2026-09-14T00:00"
        model.rangeUntilText = "2026-10-20T00:00"
        let host = NSHostingView(rootView: RootView(model: model))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: CGFloat(width), height: 740),
                              styleMask: [.titled, .resizable], backing: .buffered, defer: false)
        let appearance: NSAppearance.Name = dark ? .darkAqua : .aqua
        window.appearance = try #require(NSAppearance(named: appearance))
        window.contentView = host
        window.orderFront(nil)
        defer { window.orderOut(nil) }
        let table = try await nativeTable(in: host, rows: model.visibleSessionRows.count)
        let waitClock = ContinuousClock()
        let deadline = waitClock.now.advanced(by: .seconds(3))
        while waitClock.now < deadline && editableTextFields(in: host).count < 2 {
            host.layoutSubtreeIfNeeded()
            try await Task.sleep(for: .milliseconds(10))
        }
        host.layoutSubtreeIfNeeded()
        #expect(abs(host.bounds.width - CGFloat(width)) < 1)
        #expect(host.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == appearance)
        #expect(table.numberOfRows == 12)
        #expect(table.enclosingScrollView?.hasHorizontalScroller == true)
        #expect(table.enclosingScrollView?.hasVerticalScroller == true)
        for value in [model.rangeFromText, model.rangeUntilText] {
            let field = try #require(editableTextFields(in: host).first { $0.stringValue == value })
            let rect = field.convert(field.bounds, to: host)
            #expect(field.isEnabled && !field.isHiddenOrHasHiddenAncestor)
            #expect(rect.width > 0 && rect.minX >= -1 && rect.maxX <= host.bounds.width + 1)
        }
        let scrolls = nativeScrollViews(in: host)
        #expect(scrolls.count >= 3, "The outer report, chart and table must retain independent native scroll containers")
        let chart = try #require(scrolls.first { scroll in
            scroll !== table.enclosingScrollView && (scroll.documentView?.bounds.width ?? 0) > scroll.contentView.bounds.width + 1
        }, "The long chart must remain horizontally scrollable at both widths")
        #expect(chart.bounds.width > 0 && chart.bounds.width <= host.bounds.width)
        // Geometry and native appearance propagation are observable here. The
        // hostless layer renderer produced only a uniform background, so this
        // test deliberately makes no screenshot/readability acceptance claim.
        model.openSchedule()
        model.updateScheduleDraft { $0.mode = .rotatingShifts }
        let scheduleDeadline = waitClock.now.advanced(by: .seconds(3))
        while waitClock.now < scheduleDeadline && editableTextFields(in: host).count < 4 {
            host.layoutSubtreeIfNeeded()
            try await Task.sleep(for: .milliseconds(10))
        }
        host.layoutSubtreeIfNeeded()
        let scheduleFields = editableTextFields(in: host)
        #expect(scheduleFields.count >= 4, "The narrow schedule must retain work/rest counts, anchor and cutoff inputs")
        for field in scheduleFields {
            let rect = field.convert(field.bounds, to: host)
            #expect(field.isEnabled && !field.isHiddenOrHasHiddenAncestor)
            #expect(rect.width > 0 && rect.minX >= -1 && rect.maxX <= host.bounds.width + 1)
        }
        #expect(host.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == appearance)
        print("J-002/W-001: native report and schedule input geometry passed at \(width)px, \(dark ? "dark" : "light"). Hostless layer capture provides only a uniform background; chart/preview pixels, visual readability and VoiceOver require separate acceptance.")
        await model.flushPersistence()
    }

    @Test func testJ037NativeTableHasFourReadOnlyColumnsIndependentScrollingAndUpdates() async throws {
        prepareNativeTestApplication()
        let first = presentation()
        let second = presentation(paused: true)
        let host = NSHostingView(rootView: JournalSessionTable(rows: [first, second]).frame(width: 560, height: 180))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 560, height: 180),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = host
        window.orderFront(nil)
        defer { window.orderOut(nil) }
        let table = try await nativeTable(in: host, rows: 2)
        #expect(table.tableColumns.map(\.title) == ["Started", "Ended", "Focus time", "Cycle"])
        #expect(table.tableColumns.allSatisfy { !$0.isEditable && $0.minWidth > 0 })
        #expect(table.tableColumns[2].headerCell.alignment == .right)
        #expect(table.tableColumns[3].headerCell.alignment == .right)
        #expect(table.usesAlternatingRowBackgroundColors)
        #expect(table.headerView != nil)
        #expect(table.enclosingScrollView?.hasHorizontalScroller == true)
        #expect(table.enclosingScrollView?.hasVerticalScroller == true)
        #expect(table.delegate?.tableView?(table, shouldSelectRow: 0) == false)
        let cell = try #require(table.view(atColumn: 3, row: 1, makeIfNecessary: true))
        #expect(cell.accessibilityLabel() == "Paused")
        #expect(cell.toolTip == "Paused")
        host.rootView = JournalSessionTable(rows: [first]).frame(width: 560, height: 180)
        let updated = try await nativeTable(in: host, rows: 1)
        #expect(updated === table)
    }

    @Test func testJ033NativeChartScrollContainerAndAvailableAccessibilityAdapter() async throws {
        prepareNativeTestApplication()
        let zone = try #require(TimeZone(secondsFromGMT: 0))
        let start = Date(timeIntervalSince1970: 1_792_396_800)
        let bucket = JournalBucket(key: CivilDate(start, timeZone: zone), start: start, end: start.addingTimeInterval(86_400),
                                   focusedSeconds: 31, completedCycles: 0, scheduledDays: 0)
        var opened: CivilDate?
        let host = NSHostingView(rootView: JournalActivityChart(buckets: [bucket], grouping: .day,
            shortWeekdayLabels: false, today: bucket.key, timeZone: zone, open: { opened = $0.key })
            .padding(10).frame(width: 350, height: 190))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 350, height: 190),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = host
        window.orderFront(nil)
        defer { window.orderOut(nil) }
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: .seconds(3))
        var button: (any NSAccessibilityProtocol)?
        while clock.now < deadline {
            host.layoutSubtreeIfNeeded()
            button = accessibleElements(host).first { $0.accessibilityIdentifier() == "dw-bucket-\(bucket.key.iso8601Date)" }
            if button != nil { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        let scroll = try #require(findScrollView(in: host), "Expected the production chart's native horizontal scroll container")
        #expect(scroll.bounds.width > 0)
        #expect(scroll.documentView != nil)
        #expect(scroll.window?.isVisible == true)
        guard let native = button else {
            // SwiftUI's virtual accessibility elements are unavailable in some
            // hostless runners. The native scroll adapter is mandatory evidence;
            // actual chart keyboard/action/VoiceOver acceptance is recorded from
            // the compiled application, never inferred from this conditional.
            #expect(host.accessibilityChildren()?.isEmpty == true)
            print("J-032: hostless SwiftUI accessibility tree is empty. Native chart scroll adapter passed; chart accessibility/action is unverified here and requires compiled-app acceptance.")
            return
        }
        #expect(native.accessibilityRole() == .button)
        #expect(native.accessibilityLabel()?.contains("31s, 0 completed cycles, day off") == true)
        #expect(native.accessibilityPerformPress())
        #expect(opened == bucket.key)
    }

    private func editableTextFields(in view: NSView) -> [NSTextField] {
        let current = (view as? NSTextField).flatMap { $0.isEditable ? $0 : nil }.map { [$0] } ?? []
        return current + view.subviews.flatMap { editableTextFields(in: $0) }
    }
    private func nativeScrollViews(in view: NSView) -> [NSScrollView] {
        let current = (view as? NSScrollView).map { [$0] } ?? []
        return current + view.subviews.flatMap { nativeScrollViews(in: $0) }
    }
    private func findScrollView(in view: NSView) -> NSScrollView? {
        if let scroll = view as? NSScrollView { return scroll }
        return view.subviews.lazy.compactMap { findScrollView(in: $0) }.first
    }
    private func accessibleElements(_ item: Any, depth: Int = 0) -> [any NSAccessibilityProtocol] {
        guard depth < 30, let element = item as? any NSAccessibilityProtocol else { return [] }
        return [element] + (element.accessibilityChildren() ?? []).flatMap { accessibleElements($0, depth: depth + 1) }
    }
    private func nativeTable(in view: NSView, rows: Int) async throws -> NSTableView {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: .seconds(3))
        while clock.now < deadline {
            view.layoutSubtreeIfNeeded()
            if let table = findTable(in: view), table.numberOfRows == rows { return table }
            try await Task.sleep(for: .milliseconds(10))
        }
        let table = try #require(findTable(in: view))
        try #require(table.numberOfRows == rows)
        return table
    }
    private func findTable(in view: NSView) -> NSTableView? {
        if let table = view as? NSTableView { return table }
        return view.subviews.lazy.compactMap { findTable(in: $0) }.first
    }
    private func presentation(paused: Bool = false) -> JournalRowPresentation {
        let start = Date(timeIntervalSince1970: 1_792_396_800)
        let record = SessionRecord(startedAt: start, endedAt: start.addingTimeInterval(60), plannedFocusMinutes: 60,
                                   outcome: .live, segments: [ActiveSegment(startedAt: start, endedAt: start.addingTimeInterval(60))])
        return JournalRowPresentation(row: JournalReportRow(record: record, focusedSeconds: 60, totalFocusedSeconds: 60,
            completedInRange: false), paused: paused, timeZone: TimeZone(secondsFromGMT: 0)!)
    }
}
}
