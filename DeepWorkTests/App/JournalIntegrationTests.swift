import AppKit
import Foundation
import Combine
import SQLite3
import Testing
import DeepWorkCore
@testable import DeepWorkApp

extension NativeApplicationTests {
@Suite(.serialized)
@MainActor
struct JournalIntegrationTests {
    private let calendar = ReportingCalendar(timeZone: .gmt)
    private func directory() -> URL { FileManager.default.temporaryDirectory.appendingPathComponent("DeepWorkJournal-\(UUID())") }
    private func makeClock() throws -> TestTimerClock {
        let clock = TestTimerClock()
        clock.date = try #require(calendar.parseLocalDateTime("2026-10-19T12:00"))
        return clock
    }
    private func model(_ directory: URL, clock: TestTimerClock) -> AppModel {
        AppModel(journalStore: JournalStore(directory: directory), settingsStore: SettingsStore(directory: directory),
                 clock: clock, automaticRefresh: false, reportingTimeZone: .gmt)
    }
    private func configure(_ app: AppModel) {
        app.focusSelection.wrappedValue = .custom; app.breakSelection.wrappedValue = .custom
        app.customFocusText = "1"; app.customBreakText = "1"
    }
    private func records(count: Int, now: Date) -> [SessionRecord] {
        (0..<count).map { index in
            let start = now - Double((index + 1) * 120)
            return SessionRecord(startedAt: start, endedAt: start + 60, plannedFocusMinutes: 1, outcome: .complete,
                                 segments: [ActiveSegment(startedAt: start, endedAt: start + 60)])
        }
    }

    @Test func testJ001_J007_J017_J020_AC01ExamplesStaySeparateAndSelectionsAreTransient() async throws {
        let directory = directory(); defer { try? FileManager.default.removeItem(at: directory) }
        let clock = try makeClock(); let app = model(directory, clock: clock)
        #expect(app.selectedTab == .journal && app.reportPeriod == .week && app.showingExamples)
        #expect(app.rangeFromText == "2026-10-19T00:00" && app.rangeUntilText == "2026-10-26T00:00")
        #expect(!app.reportSnapshot.rows.isEmpty && app.journal.records.isEmpty)
        let exampleIDs = Set(app.reportSnapshot.rows.map(\.id))
        app.reportPeriod = .range; app.chartGrouping = .week
        app.toggleExamples(); #expect(app.reportSnapshot.rows.isEmpty)
        app.toggleExamples(); #expect(Set(app.reportSnapshot.rows.map(\.id)) == exampleIDs)
        #expect(app.reportPeriod == .range && app.chartGrouping == .week)
        await app.flushPersistence()
        #expect(JournalStore(directory: directory).load().value.records.isEmpty)
        configure(app); app.startFocus()
        #expect(!app.showingExamples)
        clock.advance(17); app.pauseTimer()
        #expect(app.reportSnapshot.rows.count == 1 && app.reportSnapshot.focusedSeconds == 17)
        #expect(app.reportSnapshot.rows.allSatisfy { !exampleIDs.contains($0.id) })
        #expect(await app.prepareForTermination())
        let restored = model(directory, clock: clock)
        #expect(!restored.showingExamples && restored.reportPeriod == .week && restored.timer.isPaused)
        #expect(restored.reportSnapshot.focusedSeconds == 17)
        await restored.flushPersistence()
    }

    @Test func testJ022_J023_J053_AC06LivePauseFinalizeAndBreakUseOneRecord() async throws {
        let directory = directory(); defer { try? FileManager.default.removeItem(at: directory) }
        let clock = try makeClock(); let app = model(directory, clock: clock)
        configure(app); app.startFocus()
        let id = try #require(app.timer.liveRecord?.id)
        clock.advance(10); app.refreshTimer()
        #expect(app.reportSnapshot.focusedSeconds == 10 && app.reportSnapshot.completedCycles == 0)
        clock.advance(0.25); app.refreshTimer()
        #expect(app.reportSnapshot.focusedSeconds == 10) // At most one report refresh per second.
        app.pauseTimer(); let paused = app.reportSnapshot.focusedSeconds
        clock.advance(600); app.refreshTimer()
        #expect(app.reportSnapshot.focusedSeconds == paused && app.reportSnapshot.partialSessions == 0)
        app.resumeTimer(); clock.advance(49.75); app.refreshTimer()
        #expect(app.reportSnapshot.rows.count == 1 && app.reportSnapshot.rows.first?.id == id)
        #expect(app.reportSnapshot.focusedSeconds == 60 && app.reportSnapshot.completedCycles == 1)
        clock.advance(17); app.refreshTimer()
        #expect(app.reportSnapshot.focusedSeconds == 60 && app.timer.state == .break)
        await app.flushPersistence()
        #expect(JournalStore(directory: directory).load().value.records.count == 1)
    }

    @Test func testJ053SelectingReportReconcilesDelayedDeadlineOnce() async throws {
        let directory = directory(); defer { try? FileManager.default.removeItem(at: directory) }
        let clock = try makeClock(); let app = model(directory, clock: clock)
        configure(app); app.startFocus()
        clock.advance(60) // No UI timer callback before the user's report action.
        app.reportPeriod = .day
        #expect(app.timer.state == .break)
        #expect(app.reportSnapshot.completedCycles == 1 && app.reportSnapshot.focusedSeconds == 60)
        app.chartGrouping = .week; app.refreshReport()
        #expect(app.journal.records.count == 1 && app.reportSnapshot.rows.count == 1)
        app.pauseTimer(); clock.advance(600); app.toggleExamples(); app.showActualJournal()
        #expect(app.reportSnapshot.focusedSeconds == 60 && app.timer.isPaused)
        await app.flushPersistence()
    }

    @Test func testW002_W015_W018InvalidDraftDoesNotSaveOrAnnounceAndFocusRequestIsConsumed() async throws {
        let directory = directory(); defer { try? FileManager.default.removeItem(at: directory) }
        let clock = try makeClock(); let app = model(directory, clock: clock)
        let saved = app.journal.schedule
        #expect(!app.consumeScheduleReturnFocusRequest())
        app.openSchedule()
        #expect(app.consumeScheduleControlRequest())
        #expect(!app.consumeScheduleControlRequest())
        app.updateScheduleDraft { $0.mode = .rotatingShifts; $0.workDaysText = "" }
        await app.saveSchedule(); await app.flushPersistence()
        #expect(app.scheduleDraft != nil && !app.isSavingSchedule && app.scheduleSaveStatus == nil)
        #expect(app.journal.schedule == saved && JournalStore(directory: directory).load().value.schedule == saved)
        app.selectedTab = .settings; app.selectedTab = .journal
        #expect(!app.consumeScheduleControlRequest())
        app.updateScheduleDraft { $0.workDaysText = "3"; $0.restDaysText = "2" }
        await app.saveSchedule(); await app.flushPersistence()
        #expect(app.scheduleSaveStatus == "Work schedule saved. Reports updated.")
        #expect(app.scheduleSummary.hasPrefix("3 on / 2 off"))
        #expect(app.consumeScheduleReturnFocusRequest())
        #expect(!app.consumeScheduleReturnFocusRequest())
        app.selectedTab = .settings; app.selectedTab = .journal
        #expect(!app.consumeScheduleReturnFocusRequest())
        app.openSchedule(); app.cancelSchedule()
        #expect(app.consumeScheduleReturnFocusRequest())
        #expect(!app.consumeScheduleReturnFocusRequest())
        #expect(app.scheduleSaveStatus == nil)
    }

    @Test(arguments: [0, 1, 12, 13, 25])
    func testJ027_J043_J045_AC19PaginationDoesNotChangeTotalsAndResetsWithSource(count: Int) async throws {
        let directory = directory(); defer { try? FileManager.default.removeItem(at: directory) }
        let clock = try makeClock()
        #expect(JournalStore(directory: directory).save(JournalDocument(records: records(count: count, now: clock.date))) == nil)
        let app = model(directory, clock: clock); app.showActualJournal()
        let total = app.reportSnapshot.focusedSeconds
        #expect(total == Double(count * 60))
        #expect(app.visibleSessionRows.count == min(count, 12))
        #expect(!app.canPreviousPage && app.canNextPage == (count > 12))
        app.previousSessionPage(); #expect(app.sessionPage == 0)
        if count > 12 {
            app.nextSessionPage(); let pageIDs = app.visibleSessionRows.map(\.id)
            app.chartGrouping = .week
            #expect(app.sessionPage == 1 && app.visibleSessionRows.map(\.id) == pageIDs)
            #expect(app.reportSnapshot.focusedSeconds == total && app.reportSnapshot.rows.count == count)
            while app.canNextPage { app.nextSessionPage() }
            let lastPage = app.sessionPage; app.nextSessionPage(); #expect(app.sessionPage == lastPage)
        }
        app.toggleExamples(); #expect(app.sessionPage == 0)
        app.showActualJournal(); #expect(app.reportSnapshot.rows.count == count)
        app.nextSessionPage(); app.nextReport(); #expect(app.sessionPage == 0)
        #expect(app.reportSnapshot.rows.isEmpty)
        app.previousReport(); #expect(app.reportSnapshot.focusedSeconds == total)
        await app.flushPersistence()
    }

    @Test func testJ011_J016_J028_J033_AC20InvalidRangeForcingRetentionAndFullBucketDrilldown() async throws {
        let directory = directory(); defer { try? FileManager.default.removeItem(at: directory) }
        let clock = try makeClock(); let app = model(directory, clock: clock)
        app.reportPeriod = .range; app.rangeFromText = "2026-01-01T12:00"; app.rangeUntilText = "2026-04-04T12:00"
        app.chartGrouping = .day
        #expect(app.chartGrouping == .day)
        app.rangeUntilText = "2026-04-04T12:01"; #expect(app.chartGrouping == .week)
        app.chartGrouping = .day; #expect(app.chartGrouping == .week)
        app.rangeUntilText = "2026-01-02T12:00"; #expect(app.chartGrouping == .week)
        let bucket = try #require(app.reportSnapshot.buckets.first)
        app.openReportBucket(bucket)
        #expect(app.reportPeriod == .week && app.chartGrouping == .day && app.showingExamples)
        #expect(app.reportSnapshot.bounds?.from == bucket.start && app.reportSnapshot.bounds?.until == bucket.end)
        #expect(app.rangeFromText == "2026-01-01T12:00" && app.rangeUntilText == "2026-01-02T12:00")
        app.reportPeriod = .range
        for invalid in ["", "invalid", "2026-01-01T12:00", "2025-01-01T12:00", "2037-01-01T12:00"] {
            app.rangeUntilText = invalid
            #expect(app.rangeError == JournalReport.rangeError)
            #expect(app.reportTitle == "Choose a valid range" && app.reportSnapshot.rows.isEmpty)
            #expect(app.reportSnapshot.focusedSeconds == 0 && app.reportSnapshot.days.isEmpty)
        }
        app.showToday()
        #expect(app.reportPeriod == .day && app.reportTitle.hasPrefix("Today"))
        #expect(app.rangeUntilText == "2037-01-01T12:00")
        await app.flushPersistence()
    }

    @Test func testJ008_J015_W011_W012CalendarNavigationAndTimeZoneChangePreserveRawRecords() async throws {
        let directory = directory(); defer { try? FileManager.default.removeItem(at: directory) }
        let clock = try makeClock(); let app = model(directory, clock: clock)
        app.openSchedule(); app.updateScheduleDraft { $0.reportingDayStartText = "04:00" }
        await app.saveSchedule()
        #expect(app.reportTitle == "This week · Oct 19 – Oct 25, 2026")
        app.reportPeriod = .day
        app.reportDate = try #require(calendar.parseLocalDateTime("2026-03-28T12:00"))
        let zone = try #require(TimeZone(identifier: "Europe/Kyiv"))
        app.updateReportingTimeZone(zone)
        app.nextReport()
        #expect(CivilDate(app.reportDate, timeZone: zone) == CivilDate(year: 2026, month: 3, day: 29))
        app.previousReport()
        #expect(CivilDate(app.reportDate, timeZone: zone) == CivilDate(year: 2026, month: 3, day: 28))
        app.rangeFromText = "2026-10-19T00:00"; app.rangeUntilText = "2026-10-20T00:00"
        app.reportPeriod = .range
        configure(app); app.startFocus(); clock.advance(17); app.pauseTimer()
        let checkpoint = app.timer.activeCheckpoint
        let oldBounds = app.reportSnapshot.bounds
        app.updateReportingTimeZone(.gmt)
        #expect(app.rangeFromText == "2026-10-19T00:00" && app.reportSnapshot.bounds != oldBounds)
        #expect(app.timer.activeCheckpoint == checkpoint && app.reportSnapshot.focusedSeconds == 17)
        app.resumeTimer(); clock.advance(1); app.refreshTimer()
        app.updateReportingTimeZone(zone)
        #expect(!app.timer.isPaused && app.reportSnapshot.focusedSeconds == 18)
        await app.flushPersistence()
    }

    @Test func testW002_W017_W019_AC18DraftCancelTabSwitchSaveAndRelaunch() async throws {
        let directory = directory(); defer { try? FileManager.default.removeItem(at: directory) }
        let clock = try makeClock(); let app = model(directory, clock: clock)
        let original = app.journal.schedule
        let ranges = [app.rangeFromText, app.rangeUntilText]
        app.openSchedule(); app.updateScheduleDraft { $0.mode = .anyDay; $0.reportingDayStartText = "04:00" }
        app.selectedTab = .focus; app.selectedTab = .journal
        #expect(app.scheduleDraft?.mode == .anyDay && app.journal.schedule == original)
        await app.flushPersistence()
        #expect(JournalStore(directory: directory).load().value.schedule == original)
        app.cancelSchedule(); app.openSchedule()
        #expect(app.scheduleDraft?.mode == original.mode)
        app.updateScheduleDraft { $0.mode = .chosenWeekdays; $0.weekdays = []; $0.weekStartsOn = .sunday; $0.reportingDayStartText = "04:00" }
        await app.saveSchedule(); await app.flushPersistence()
        #expect(app.scheduleDraft == nil && app.scheduleSaveError == nil)
        #expect(app.scheduleSummary == "No fixed workdays · Week starts Sunday · Day starts 04:00")
        #expect(app.reportSnapshot.scheduledDays == 0)
        #expect([app.rangeFromText, app.rangeUntilText] == ranges)
        let restored = model(directory, clock: clock)
        #expect(restored.journal.schedule == app.journal.schedule && restored.scheduleDraft == nil)
        await restored.flushPersistence()
    }

    @Test func testW016_W018_W019ScheduleSaveReinterpretsHistoryWithoutRewritingRows() async throws {
        let directory = directory(); defer { try? FileManager.default.removeItem(at: directory) }
        let clock = try makeClock(); let history = records(count: 25, now: clock.date)
        #expect(JournalStore(directory: directory).save(JournalDocument(records: history)) == nil)
        let app = model(directory, clock: clock)
        app.reportPeriod = .range; app.rangeFromText = "2026-10-19T00:00"; app.rangeUntilText = "2026-10-20T00:00"
        let date = app.reportDate; let total = app.reportSnapshot.focusedSeconds
        app.nextSessionPage(); #expect(app.sessionPage == 1)
        app.openSchedule(); app.updateScheduleDraft { $0.weekdays = [] }
        await app.saveSchedule(); await app.flushPersistence()
        #expect(app.sessionPage == 0 && app.reportSnapshot.scheduledDays == 0)
        #expect(app.reportSnapshot.focusedSeconds == total && app.reportSnapshot.completedCycles == 25)
        #expect(app.reportSnapshot.buckets.allSatisfy { $0.scheduledDays == 0 })
        #expect(app.reportDate == date && app.rangeFromText == "2026-10-19T00:00" && app.rangeUntilText == "2026-10-20T00:00")
        let stored = JournalStore(directory: directory).load().value
        #expect(stored.records == history && stored.schedule.weekdays.isEmpty)
        let restored = model(directory, clock: clock)
        #expect(restored.journal.records == history && restored.journal.schedule == app.journal.schedule)
        await restored.flushPersistence()
    }

    @Test(arguments: [false, true])
    func testJ015_W014IdleCalendarBoundaryRefreshesWithoutTimerTicks(afterFailedQuit: Bool) async throws {
        let directory = directory(); defer { try? FileManager.default.removeItem(at: directory) }
        let clock = try makeClock()
        clock.date = try #require(calendar.parseLocalDateTime("2026-10-19T03:59")) + 59
        var schedule = WorkSchedule.defaults(now: clock.date, timeZone: .gmt)
        schedule.reportingDayStartMinutes = 240
        #expect(JournalStore(directory: directory).save(JournalDocument(schedule: schedule)) == nil)
        let app = AppModel(journalStore: JournalStore(directory: directory), settingsStore: SettingsStore(directory: directory),
                           clock: clock, automaticRefresh: true, reportingTimeZone: .gmt)
        #expect(app.currentReportingDay == CivilDate(year: 2026, month: 10, day: 18))
        app.openSchedule(); app.updateScheduleDraft { $0.reportingDayStartText = "05:00" }
        #expect(app.nextReportCalendarRefresh == clock.date + 1)
        var db: OpaquePointer?
        defer { sqlite3_close(db) }
        if afterFailedQuit {
            await app.flushPersistence()
            try #require(sqlite3_open(directory.appendingPathComponent(JournalStore.filename).path, &db) == SQLITE_OK)
            try #require(sqlite3_exec(db, "CREATE TRIGGER reject_idle_quit BEFORE UPDATE ON journal_state BEGIN SELECT RAISE(ABORT, 'fixture quit rejected'); END", nil, nil, nil) == SQLITE_OK)
            #expect(!(await app.prepareForTermination()) && !app.isTerminating)
        }
        var refreshes = 0
        let observation = app.$reportSnapshot.dropFirst().sink { _ in refreshes += 1 }
        defer { observation.cancel() }
        clock.advance(1)
        let deadline = ContinuousClock.now.advanced(by: .seconds(4))
        while refreshes == 0 && ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(10)) }
        #expect(refreshes > 0)
        #expect(app.timer.state == .setup && app.journal.records.isEmpty)
        #expect(app.currentReportingDay == CivilDate(year: 2026, month: 10, day: 19))
        #expect(app.nextReportCalendarRefresh == clock.date + 3600)
        #expect(try app.scheduleDraft?.preview(now: app.reportNow, timeZone: .gmt).first?.date == CivilDate(year: 2026, month: 10, day: 18))
        #expect(await app.prepareForTermination() == !afterFailedQuit)
    }

    @Test func testW017_W019_J052_AC27RealSQLiteFailureRetainsDraftAndCommittedSchedule() async throws {
        let directory = directory(); defer { try? FileManager.default.removeItem(at: directory) }
        let clock = try makeClock(); let app = model(directory, clock: clock)
        configure(app); app.startFocus(); clock.advance(17); app.pauseTimer()
        await app.flushPersistence()
        let original = app.journal.schedule
        var db: OpaquePointer?
        try #require(sqlite3_open(directory.appendingPathComponent(JournalStore.filename).path, &db) == SQLITE_OK)
        defer { sqlite3_close(db) }
        try #require(sqlite3_exec(db, "CREATE TRIGGER reject_schedule BEFORE UPDATE ON journal_state BEGIN SELECT RAISE(ABORT, 'fixture write rejected'); END", nil, nil, nil) == SQLITE_OK)
        app.openSchedule(); app.updateScheduleDraft { $0.mode = .anyDay }
        await app.saveSchedule(); await app.flushPersistence()
        #expect(app.scheduleDraft?.mode == .anyDay && app.journal.schedule == original)
        #expect(app.scheduleSaveError != nil && !app.isSavingSchedule && app.journalFailure != nil)
        #expect(JournalStore(directory: directory).load().value.schedule == original)
        #expect(app.reportSnapshot.focusedSeconds == 17)
        app.resumeTimer(); clock.advance(43); app.refreshTimer()
        #expect(app.journal.records.count == 1 && app.timer.state == .break)
        app.cancelSchedule(); app.refreshReport()
        #expect(app.reportSnapshot.focusedSeconds == 60 && app.reportSnapshot.completedCycles == 1)
        await app.flushPersistence()
        #expect(app.journalStorageMessage.contains("Saving unavailable"))
    }

    @Test(arguments: [false, true])
    func testW017_W019_F025SlowScheduleSaveMergesLatestTimerAndQuitState(quitDuringSave: Bool) async throws {
        let directory = directory(); defer { try? FileManager.default.removeItem(at: directory) }
        let clock = try makeClock(); let gate = ScheduleGateStore(directory: directory)
        let app = AppModel(journalStore: gate, settingsStore: SettingsStore(directory: directory), clock: clock,
                           automaticRefresh: false, reportingTimeZone: .gmt)
        configure(app); app.startFocus(); await app.flushPersistence()
        app.openSchedule(); app.updateScheduleDraft { $0.mode = .anyDay }
        gate.blockNextSave(); defer { gate.releaseSave() }
        let saving = Task { await app.saveSchedule() }
        while !app.isSavingSchedule { await Task.yield() }
        clock.advance(75); app.refreshTimer()
        app.repeats.wrappedValue = false
        app.updateScheduleDraft { $0.mode = .rotatingShifts }
        app.cancelSchedule()
        #expect(app.scheduleDraft?.mode == .anyDay && app.journal.schedule.mode == .chosenWeekdays)
        #expect(app.journal.records.count == 1 && app.timer.state == .break && !app.timer.isPaused)
        let quitting: Task<Bool, Never>? = quitDuringSave ? Task { await app.prepareForTermination() } : nil
        if quitDuringSave { while !app.isTerminating { await Task.yield() } }
        gate.releaseSave(); await saving.value
        if let quitting { #expect(await quitting.value) }
        await app.flushPersistence()
        let saved = JournalStore(directory: directory).load().value
        #expect(saved.schedule.mode == .anyDay && saved.records == app.journal.records)
        #expect(!saved.configuration.repeats && saved.activeCheckpoint?.remainingSeconds == 45)
        #expect(app.scheduleDraft == nil && app.timer.isPaused == quitDuringSave)
        try saved.validate()
    }
}
}

/// Gates a real SQLite write; no simulated storage success enters acceptance.
private final class ScheduleGateStore: JournalPersisting, @unchecked Sendable {
    private let store: JournalStore
    private let lock = NSLock()
    private var blocked = false
    private let release = DispatchSemaphore(value: 0)
    init(directory: URL) { store = JournalStore(directory: directory) }
    func load() -> StoreLoad<JournalDocument> { store.load() }
    func blockNextSave() { lock.lock(); blocked = true; lock.unlock() }
    func releaseSave() { release.signal() }
    func save(_ journal: JournalDocument) -> StoreFailure? {
        lock.lock(); let block = blocked; blocked = false; lock.unlock()
        if block { release.wait() }
        return store.save(journal)
    }
}
