import Foundation
import Testing
@testable import DeepWorkCore

struct ReportCSVExporterTests {
    private let schedule = WorkSchedule(mode: .anyDay, firstWorkDay: CivilDate(year: 2026, month: 10, day: 19))
    private let summary = "Any day · Week starts Monday"
    private let start = Date(timeIntervalSince1970: 1_792_368_000) // 2026-10-19T00:00:00Z

    @Test func J049_S010_exactHeaderUTF8BOMCRLFAndQuotedColumns() throws {
        let record = partial(start, seconds: 12.125)
        let snapshot = try all([record])
        let bytes = try ReportCSVExporter.data(for: snapshot)
        #expect(Array(bytes.prefix(3)) == [0xEF, 0xBB, 0xBF])
        let text = try #require(String(data: bytes, encoding: .utf8))
        let header = "\"Data\",\"Report from\",\"Report until (exclusive)\",\"Reporting day starts\",\"Schedule\",\"Session ID\",\"Started\",\"Ended / observed at\",\"Outcome\",\"Planned minutes\",\"Focus seconds in range\",\"Total focus seconds\",\"Completed cycle in range\""
        let row = "\"Journal\",\"\",\"\",\"00:00\",\"Any day · Week starts Monday\",\"\(record.id.uuidString)\",\"2026-10-19T00:00:00+00:00\",\"2026-10-19T00:00:12+00:00\",\"partial\",\"480\",\"12.125\",\"12.125\",\"0\""
        #expect(bytes == Data(("\u{FEFF}" + header + "\r\n" + row).utf8))
        #expect(!text.hasSuffix("\r\n"))
    }

    @Test func J049_AC22_quotesCommasNewlinesAndUnicodeRemainOneQuotedCell() throws {
        let quoted = "Any \"day\", Київ\r\nSecond line\nThird line"
        let snapshot = try ReportExportSnapshot.allSessions(actualRecords: [partial(start)], schedule: schedule,
            scheduleSummary: quoted, timeZone: .gmt)
        let text = try string(snapshot)
        #expect(text.contains("\"Any \"\"day\"\", Київ\r\nSecond line\nThird line\""))
        #expect(text.contains("\"00:00\",\"Any \"\"day\"\", Київ"))
        #expect(text.contains("Third line\",\"\(snapshot.rows[0].id.uuidString)\""))
    }

    @Test func J049_J051_AC22_clippedSegmentsRetainOriginalEndpointsAndFullTotal() throws {
        let record = SessionRecord(startedAt: start, endedAt: start.addingTimeInterval(1_800),
            plannedFocusMinutes: 60, outcome: .partial,
            segments: [ActiveSegment(startedAt: start, endedAt: start.addingTimeInterval(600)),
                       ActiveSegment(startedAt: start.addingTimeInterval(1_200), endedAt: start.addingTimeInterval(1_800))])
        let snapshot = try current([record], from: start.addingTimeInterval(300.125),
                                   until: start.addingTimeInterval(1_500.125))
        let cells = try dataRows(snapshot)[0]
        #expect(cells[1] == "2026-10-19T00:05:00+00:00")
        #expect(cells[2] == "2026-10-19T00:25:00+00:00")
        #expect(cells[6] == "2026-10-19T00:00:00+00:00")
        #expect(cells[7] == "2026-10-19T00:30:00+00:00")
        #expect(cells[10] == "600" && cells[11] == "1200" && cells[12] == "0")
        #expect(snapshot.focusedSeconds == 600)
        #expect(snapshot.rows[0].record == record)
    }

    @Test func J049_AC22_completionAtExclusiveUntilBelongsOnlyToNextReport() throws {
        let record = SessionRecord(startedAt: start, endedAt: start.addingTimeInterval(60),
            plannedFocusMinutes: 1, outcome: .complete,
            segments: [ActiveSegment(startedAt: start, endedAt: start.addingTimeInterval(60))])
        let earlier = try current([record], from: start, until: start.addingTimeInterval(60))
        let following = try current([record], from: start.addingTimeInterval(60), until: start.addingTimeInterval(120))
        let before = try dataRows(earlier)[0], after = try dataRows(following)[0]
        #expect(before[10] == "60" && before[12] == "0")
        #expect(after[10] == "0" && after[11] == "60" && after[12] == "1")
        #expect(following.canExport)
        #expect(following.focusedSeconds == 0)
    }

    @Test func J051_S009_allSessionsIncludesPartialAndLiveButExcludesZeroLive() throws {
        let complete = SessionRecord(startedAt: start, endedAt: start.addingTimeInterval(60),
            plannedFocusMinutes: 1, outcome: .complete,
            segments: [ActiveSegment(startedAt: start, endedAt: start.addingTimeInterval(60))])
        let partial = partial(start.addingTimeInterval(100), seconds: 12.5)
        let live = self.partial(start.addingTimeInterval(200), seconds: 9.75, outcome: .live)
        let zero = SessionRecord(startedAt: start.addingTimeInterval(300), endedAt: start.addingTimeInterval(300),
                                 plannedFocusMinutes: 60, outcome: .live, segments: [])
        let snapshot = try all([complete, live, zero, partial])
        #expect(snapshot.rows.map(\.id) == [live.id, partial.id, complete.id])
        #expect(snapshot.bounds == nil && !snapshot.isExample)
        #expect(snapshot.focusedSeconds == 82.25)
        let rows = try dataRows(snapshot)
        #expect(rows.map { $0[8] } == ["live", "partial", "complete"])
        #expect(rows.map { $0[12] } == ["0", "0", "1"])
        #expect(rows.allSatisfy { $0[1].isEmpty && $0[2].isEmpty && $0[10] == $0[11] && $0[0] == "Journal" })
    }

    @Test func J048_S009_emptySnapshotsDisableExportAndDoNotCreateHeaderOnlyFiles() throws {
        let all = try all([])
        let current = try current([], from: start, until: start.addingTimeInterval(86_400))
        for snapshot in [all, current] {
            #expect(!snapshot.canExport && snapshot.rows.isEmpty && snapshot.focusedSeconds == 0)
            #expect(throws: ModelValidationError("There are no focus sessions to export.")) {
                try ReportCSVExporter.data(for: snapshot)
            }
        }
    }

    @Test func J048_J015_invalidOrMissingReportBoundsCannotCreateExportSnapshot() throws {
        let invalid = JournalReport.build(records: [], from: start, until: start, schedule: schedule)
        for report in [invalid, JournalReport.empty(), JournalReport.empty(error: "Test report failure")] {
            #expect(throws: ModelValidationError.self) {
                try ReportExportSnapshot.currentReport(report, isExample: false, schedule: schedule,
                                                       scheduleSummary: summary, timeZone: .gmt)
            }
        }
    }

    @Test func J050_S010_filenamesUseLiteralLocalExclusiveEndAndExampleMarker() throws {
        let zone = try #require(TimeZone(secondsFromGMT: 19_800))
        let from = start.addingTimeInterval(-4 * 3_600)
        let until = start.addingTimeInterval(20 * 3_600)
        for example in [false, true] {
            let snapshot = try current([partial(from)], from: from, until: until, example: example, zone: zone)
            #expect(snapshot.filename == "deep-work-\(example ? "example-" : "")2026-10-19-to-2026-10-20.csv")
            #expect(try dataRows(snapshot)[0][0] == (example ? "Example" : "Journal"))
        }
        #expect(try all([partial(start)]).filename == "deep-work-journal-all-sessions.csv")
    }

    @Test func J049_AC22_eachTimestampUsesItsOwnDSTOffsetWithoutMilliseconds() throws {
        let zone = try #require(TimeZone(identifier: "Europe/Kyiv"))
        let calendar = ReportingCalendar(timeZone: zone)
        let from = try #require(calendar.parseLocalDateTime("2026-03-29T02:59"))
        let until = try #require(calendar.parseLocalDateTime("2026-03-29T04:02"))
        let record = partial(from.addingTimeInterval(0.125), seconds: 179.5)
        let snapshot = try current([record], from: from, until: until, zone: zone)
        let row = try dataRows(snapshot)[0]
        #expect(row[1] == "2026-03-29T02:59:00+02:00")
        #expect(row[2] == "2026-03-29T04:02:00+03:00")
        #expect(row[6] == "2026-03-29T02:59:00+02:00")
        #expect(row[7] == "2026-03-29T04:01:59+03:00")
        #expect(row[10] == "179.5")
    }

    @Test(arguments: [(0, "+00:00"), (20_700, "+05:45"), (-12_600, "-03:30")])
    func J049_offsetsAreNumericIncludingUTCAndFractionalHours(_ seconds: Int, _ suffix: String) throws {
        let zone = try #require(TimeZone(secondsFromGMT: seconds))
        let snapshot = try ReportExportSnapshot.allSessions(actualRecords: [partial(start)], schedule: schedule,
            scheduleSummary: summary, timeZone: zone)
        let row = try dataRows(snapshot)[0]
        #expect(row[6].hasSuffix(suffix) && row[7].hasSuffix(suffix))
        #expect(!row[6].contains("Z"))
    }

    @Test(arguments: [(0.0004, "0"), (0.0006, "0.001"), (0.0625, "0.063"), (1.2344, "1.234"),
                      (1.2346, "1.235"), (1.9996, "2"), (10.12, "10.12"), (60.0, "60")])
    func J049_secondsRoundAtMostThreeFractionalDigitsWithoutGrouping(_ seconds: Double, _ expected: String) throws {
        // Dates near Foundation's reference epoch preserve these tiny fixtures
        // without cancellation from contemporary multi-billion-second values.
        let record = partial(Date(timeIntervalSinceReferenceDate: 0), seconds: seconds)
        let row = try dataRows(all([record]))[0]
        #expect(row[10] == expected && row[11] == expected)
        #expect(!row[10].contains(","))
    }

    @Test func J048_J051_allMatchingRowsAndTotalsSurviveGroupingAndPagination() throws {
        let records = (0..<25).map { partial(start.addingTimeInterval(Double($0) * 120), seconds: 30.25) }
        let report = JournalReport.build(records: records, from: start, until: start.addingTimeInterval(86_400),
                                         schedule: schedule, grouping: .week, calendar: ReportingCalendar(timeZone: .gmt))
        let snapshot = try ReportExportSnapshot.currentReport(report, isExample: false, schedule: schedule,
            scheduleSummary: summary, timeZone: .gmt)
        #expect(snapshot.rows == report.rows)
        let rows = try dataRows(snapshot)
        #expect(rows.count == 25)
        #expect(rows.map { $0[5] } == records.reversed().map { $0.id.uuidString })
        #expect(rows.compactMap { Double($0[10]) }.reduce(0, +) == report.focusedSeconds)
        #expect(rows.compactMap { Int($0[12]) }.reduce(0, +) == report.completedCycles)
    }

    @Test func J051_snapshotKeepsCapturedRecordsScheduleAndZoneWhenInputsChange() throws {
        var record = partial(start)
        var changedSchedule = schedule
        changedSchedule.reportingDayStartMinutes = 245
        let snapshot = try ReportExportSnapshot.allSessions(actualRecords: [record], schedule: changedSchedule,
            scheduleSummary: "Any day · Week starts Monday · Day starts 04:05", timeZone: .gmt)
        let captured = try ReportCSVExporter.data(for: snapshot)
        record.endedAt = start.addingTimeInterval(100)
        record.segments[0].endedAt = record.endedAt
        changedSchedule.reportingDayStartMinutes = 0
        #expect(try ReportCSVExporter.data(for: snapshot) == captured)
        #expect(snapshot.rows[0].record != record)
        #expect(snapshot.schedule.reportingDayStartMinutes == 245)
        #expect(try dataRows(snapshot)[0][3] == "04:05")
        #expect(snapshot.timeZone == .gmt)
    }

    @Test func S009_allHistoryHasNoCurrentReportDateSpanLimitAndOrdersTiesDeterministically() throws {
        var first = partial(start)
        first.id = try #require(UUID(uuidString: "00000000-0000-0000-0000-000000000001"))
        var second = first
        second.id = try #require(UUID(uuidString: "00000000-0000-0000-0000-000000000002"))
        let old = partial(start.addingTimeInterval(-JournalReport.maximumDuration - 86_400))
        let snapshot = try all([second, old, first])
        #expect(snapshot.rows.map(\.id) == [first.id, second.id, old.id])
        #expect(try dataRows(snapshot).count == 3)
    }

    @Test func S010_malformedRecordsDuplicateIDsAndInvalidScheduleFailExplicitly() throws {
        let record = partial(start)
        #expect(throws: ModelValidationError("The export contains a duplicate session identifier.")) {
            try all([record, record])
        }
        var invalid = record
        invalid.segments[0].endedAt = start.addingTimeInterval(-1)
        #expect(throws: ModelValidationError.self) { try all([invalid]) }
        var invalidSchedule = schedule
        invalidSchedule.reportingDayStartMinutes = -1
        #expect(throws: ModelValidationError.self) {
            try ReportExportSnapshot.allSessions(actualRecords: [record], schedule: invalidSchedule,
                scheduleSummary: summary, timeZone: .gmt)
        }
        let report = JournalReport.build(records: [record], from: start, until: start.addingTimeInterval(100),
                                         schedule: schedule, calendar: ReportingCalendar(timeZone: .gmt))
        #expect(throws: ModelValidationError.self) {
            try ReportExportSnapshot.currentReport(report, isExample: false, schedule: invalidSchedule,
                scheduleSummary: summary, timeZone: .gmt)
        }
    }

    @Test func S010_unrepresentableTimestampFailsInsteadOfWritingMisleadingYear() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .gmt
        let date = try #require(calendar.date(from: DateComponents(year: 10_000, month: 1, day: 1)))
        let snapshot = try all([partial(date)])
        #expect(throws: ModelValidationError("An export timestamp is outside the supported Gregorian calendar.")) {
            try ReportCSVExporter.data(for: snapshot)
        }
    }

    private func partial(_ from: Date, seconds: TimeInterval = 10, outcome: SessionOutcome = .partial) -> SessionRecord {
        let until = from.addingTimeInterval(seconds)
        return SessionRecord(startedAt: from, endedAt: until, plannedFocusMinutes: 480, outcome: outcome,
                             segments: [ActiveSegment(startedAt: from, endedAt: until)])
    }

    private func all(_ records: [SessionRecord]) throws -> ReportExportSnapshot {
        try ReportExportSnapshot.allSessions(actualRecords: records, schedule: schedule,
                                              scheduleSummary: summary, timeZone: .gmt)
    }

    private func current(_ records: [SessionRecord], from: Date, until: Date,
                         example: Bool = false, zone: TimeZone = .gmt) throws -> ReportExportSnapshot {
        let report = JournalReport.build(records: records, from: from, until: until, schedule: schedule,
                                         calendar: ReportingCalendar(timeZone: zone))
        return try ReportExportSnapshot.currentReport(report, isExample: example, schedule: schedule,
                                                       scheduleSummary: summary, timeZone: zone)
    }

    private func string(_ snapshot: ReportExportSnapshot) throws -> String {
        try #require(String(data: ReportCSVExporter.data(for: snapshot), encoding: .utf8))
    }

    /// Most fixtures have no embedded delimiters. The independent exact-byte
    /// assertion above covers escaping and embedded multiline cells separately.
    private func dataRows(_ snapshot: ReportExportSnapshot) throws -> [[String]] {
        try string(snapshot).components(separatedBy: "\r\n").dropFirst().map {
            String($0.dropFirst().dropLast()).components(separatedBy: "\",\"")
                .map { $0.replacingOccurrences(of: "\"\"", with: "\"") }
        }
    }
}
