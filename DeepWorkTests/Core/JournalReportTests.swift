import Foundation
import Testing
@testable import DeepWorkCore

struct JournalReportTests {
    private var calendar: ReportingCalendar { ReportingCalendar(timeZone: TimeZone(identifier: "Europe/Kyiv") ?? .gmt) }
    private var anyDay: WorkSchedule { WorkSchedule(mode: .anyDay, firstWorkDay: CivilDate(year: 2026, month: 3, day: 28)) }

    @Test func J022_J023_clippingExcludesPausesAndPartialAddsTimeWithoutCycle() throws {
        let start = try at("2026-10-17", 8)
        let end = try at("2026-10-17", 10)
        let complete = SessionRecord(startedAt: start, endedAt: end, plannedFocusMinutes: 90, outcome: .complete,
            segments: [ActiveSegment(startedAt: start, endedAt: try at("2026-10-17", 8, 45)),
                       ActiveSegment(startedAt: try at("2026-10-17", 9, 15), endedAt: end)])
        let partial = try record("2026-10-17", hour: 10, minutes: 15, outcome: .partial)
        let report = try build([complete, partial], "2026-10-17T08:30", "2026-10-17T11:00")
        #expect(report.error == nil)
        #expect(report.focusedSeconds == 75 * 60)
        #expect(report.completedCycles == 1)
        #expect(report.partialSessions == 1)
        #expect(report.daysWithFocus == 1)
        #expect(report.rows.map(\.id) == [partial.id, complete.id])
        let row = try #require(report.rows.last)
        #expect(row.focusedSeconds == 60 * 60)
        #expect(row.totalFocusedSeconds == 90 * 60)
        #expect(row.record.startedAt == start)
        #expect(row.record.endedAt == end)
        #expect(report.rows.first?.completedInRange == false)
        try complete.validate()
    }

    @Test func J023_J041_completionAtUntilMovesToFollowingReportWithoutMovingFocus() throws {
        let complete = try record("2026-10-16", hour: 23)
        let first = try build([complete], "2026-10-16T00:00", "2026-10-17T00:00")
        let next = try build([complete], "2026-10-17T00:00", "2026-10-18T00:00")
        #expect(first.focusedSeconds == 3_600)
        #expect(first.completedCycles == 0)
        #expect(first.rows.first?.completedInRange == false)
        #expect(next.focusedSeconds == 0)
        #expect(next.completedCycles == 1)
        #expect(next.rows.count == 1)
        #expect(next.rows.first?.completedInRange == true)
        #expect(next.daysWithFocus == 0)
    }

    @Test func J022_W011_focusSplitsAtNonMidnightCutoff() throws {
        var schedule = anyDay
        schedule.reportingDayStartMinutes = 240
        let start = try at("2026-10-17", 3, 30)
        let complete = session(start, seconds: 3_600)
        let report = try build([complete], "2026-10-17T00:00", "2026-10-18T00:00", schedule: schedule)
        #expect(report.days.map(\.id) == ["2026-10-16", "2026-10-17"])
        #expect(report.days.map(\.focusedSeconds) == [1_800, 1_800])
        #expect(report.days.map(\.completedCycles) == [0, 1])
        #expect(report.daysWithFocus == 2)
        #expect(try calendar.day(containing: at("2026-10-17", 3, 59), cutoffMinutes: 240).iso8601Date == "2026-10-16")
        #expect(try calendar.day(containing: at("2026-10-17", 4), cutoffMinutes: 240).iso8601Date == "2026-10-17")
    }

    @Test func W012_springAndAutumnDaysHave23And25Hours() throws {
        #expect(try at("2026-03-30").timeIntervalSince(at("2026-03-29")) == 23 * 3_600)
        #expect(try at("2026-10-26").timeIntervalSince(at("2026-10-25")) == 25 * 3_600)
        #expect(try calendar.addingDays(2, to: civil("2026-03-28")).iso8601Date == "2026-03-30")
        #expect(try calendar.addingDays(-2, to: civil("2026-10-26")).iso8601Date == "2026-10-24")
        // Three valid native records cover the whole short day; no >480-minute
        // record or under-filled Complete fixture weakens storage invariants.
        let start = try at("2026-03-29")
        let records = [session(start, seconds: 8 * 3_600),
                       session(start.addingTimeInterval(8 * 3_600), seconds: 8 * 3_600),
                       session(start.addingTimeInterval(16 * 3_600), seconds: 7 * 3_600)]
        let report = try build(records, "2026-03-28T00:00", "2026-03-31T00:00")
        #expect(report.error == nil)
        #expect(report.focusedSeconds == 23 * 3_600)
        let expectedSeconds: [TimeInterval] = [0, 23 * 3_600, 0]
        #expect(report.days.map(\.focusedSeconds) == expectedSeconds)
        #expect(report.days.map(\.completedCycles) == [0, 2, 1])
        let autumn = try build([], "2026-10-24T00:00", "2026-10-27T00:00")
        #expect(autumn.days.map { $0.end.timeIntervalSince($0.start) } == [86_400, 90_000, 86_400])
    }

    @Test func J027_weeklyGroupingPreservesRowsMetricsAndEmptyBuckets() throws {
        let records = try [record("2026-10-12", hour: 9), record("2026-10-18", hour: 9), record("2026-10-19", hour: 9)]
        let weekdays = WorkSchedule()
        let daily = try build(records, "2026-10-12T00:00", "2026-11-02T00:00", schedule: weekdays)
        let weekly = try build(records, "2026-10-12T00:00", "2026-11-02T00:00", schedule: weekdays, grouping: .week)
        #expect(weekly.rows == daily.rows)
        #expect(weekly.focusedSeconds == daily.focusedSeconds)
        #expect(weekly.completedCycles == daily.completedCycles)
        #expect(weekly.scheduledDays == 15)
        #expect(weekly.workedScheduledDays == 2)
        #expect(weekly.daysWithFocus == 3)
        #expect(weekly.days.count == 21)
        #expect(weekly.buckets.map(\.id) == ["2026-10-12", "2026-10-19", "2026-10-26"])
        #expect(weekly.buckets.map(\.focusedSeconds) == [7_200, 3_600, 0])
        #expect(weekly.buckets.map(\.completedCycles) == [2, 1, 0])
        #expect(weekly.buckets.map(\.scheduledDays) == [5, 5, 5])
        #expect(daily.buckets.reduce(0) { $0 + $1.focusedSeconds } == daily.focusedSeconds)
    }

    @Test(arguments: Weekday.allCases) func W010_allSevenWeekStartsAreInclusive(_ weekday: Weekday) throws {
        let sunday = try civil("2026-10-18")
        let start = try calendar.week(containing: sunday, startsOn: weekday)
        #expect(try calendar.weekday(of: start) == weekday)
        #expect(try calendar.week(containing: start, startsOn: weekday) == start)
        let expected = weekday == .sunday ? "2026-10-18" : String(format: "2026-10-%02d", 11 + weekday.rawValue)
        #expect(start.iso8601Date == expected)
        var schedule = anyDay; schedule.weekStartsOn = weekday; schedule.reportingDayStartMinutes = 240
        let bounds = try calendar.weekBounds(for: sunday, schedule: schedule)
        #expect(try bounds.from == calendar.date(at: start, cutoffMinutes: 240))
        #expect(try bounds.until == calendar.date(at: calendar.addingDays(7, to: start), cutoffMinutes: 240))
    }

    @Test func J024_J025_W005_arbitraryAndZeroWeekdaysNeverDiscardOffDayWork() throws {
        var schedule = WorkSchedule(weekdays: [.sunday, .tuesday, .thursday])
        let saturday = try record("2026-10-17", hour: 9)
        let report = try build([saturday], "2026-10-12T00:00", "2026-10-19T00:00", schedule: schedule)
        #expect(try calendar.isScheduled(civil("2026-10-18"), schedule: schedule))
        #expect(try !calendar.isScheduled(civil("2026-10-17"), schedule: schedule))
        #expect(report.focusedSeconds == 3_600)
        #expect(report.scheduledDays == 3)
        #expect(report.workedScheduledDays == 0)
        #expect(report.daysWithFocus == 1)
        #expect(report.days.count == 7)
        #expect(report.buckets[5].scheduledDays == 0)
        schedule.weekdays = []
        let emptySchedule = try build([saturday], "2026-10-12T00:00", "2026-10-19T00:00", schedule: schedule)
        #expect(emptySchedule.scheduledDays == 0)
        #expect(emptySchedule.focusedSeconds == report.focusedSeconds)
        schedule.mode = .anyDay
        let everyDay = try build([saturday], "2026-10-12T00:00", "2026-10-19T00:00", schedule: schedule)
        #expect(everyDay.scheduledDays == 7)
        #expect(everyDay.rows == report.rows)
    }

    @Test func W009_W012_shiftsUsePositiveCivilModuloBeforeAnchorThroughDST() throws {
        let schedule = WorkSchedule(mode: .rotatingShifts, workDays: 2, restDays: 2,
                                    firstWorkDay: try civil("2026-03-28"))
        let values = try (0..<12).map { try calendar.isScheduled(calendar.addingDays($0, to: civil("2026-03-24")), schedule: schedule) }
        #expect(values == [true, true, false, false, true, true, false, false, true, true, false, false])
        var invalid = schedule; invalid.restDays = 0
        #expect(throws: ModelValidationError.self) { try calendar.isScheduled(self.civil("2026-03-30"), schedule: invalid) }
        let autumn = WorkSchedule(mode: .rotatingShifts, workDays: 1, restDays: 1,
                                  firstWorkDay: try civil("2026-10-24"))
        #expect(try !calendar.isScheduled(civil("2026-10-25"), schedule: autumn))
        #expect(try calendar.isScheduled(civil("2026-10-26"), schedule: autumn))
    }

    @Test func J024_J031_partialRangeCountsOverlappingDatesWithFullBucketBounds() throws {
        let report = try build([], "2026-10-16T22:00", "2026-10-19T00:00", schedule: WorkSchedule(), grouping: .week)
        #expect(report.days.count == 3)
        #expect(report.scheduledDays == 1)
        #expect(report.buckets.count == 1)
        #expect(report.buckets.first?.scheduledDays == 1)
        #expect(try report.buckets.first?.start == at("2026-10-12"))
        #expect(try report.buckets.first?.end == at("2026-10-19"))
    }

    @Test func J042_liveTimeIsNotPartialOrCompleteAndProjectionDoesNotMutateInputs() throws {
        let live = try record("2026-10-17", hour: 10, minutes: 5, outcome: .live)
        let original = live
        let report = try build([live], "2026-10-17T00:00", "2026-10-18T00:00")
        #expect(report.focusedSeconds == 300)
        #expect(report.completedCycles == 0)
        #expect(report.partialSessions == 0)
        #expect(report.rows.first?.record.outcome == .live)
        #expect(live == original)
        let zero = SessionRecord(startedAt: live.startedAt, endedAt: live.startedAt,
                                 plannedFocusMinutes: 60, outcome: .live, segments: [])
        let empty = try build([zero], "2026-10-17T00:00", "2026-10-18T00:00")
        #expect(empty.rows.isEmpty)
        #expect(empty.error == nil)
    }

    @Test func J015_missingNonfiniteReversedEqualAndOverLimitBoundsFailEmpty() throws {
        let now = try at("2026-10-17")
        let inputs: [(Date?, Date?)] = [(nil, now), (now, nil), (nil, nil), (now, now),
            (now, now.addingTimeInterval(-1)), (Date(timeIntervalSince1970: .nan), now),
            (now, Date(timeIntervalSince1970: .infinity)), (now, now.addingTimeInterval(JournalReport.maximumDuration + 0.001))]
        for (from, until) in inputs {
            let report = JournalReport.build(records: [], from: from, until: until, schedule: anyDay, calendar: calendar)
            #expect(report.error == JournalReport.rangeError)
            #expect(report.bounds == nil)
            #expect(report.rows.isEmpty && report.days.isEmpty && report.buckets.isEmpty)
            #expect(report.focusedSeconds == 0 && report.completedCycles == 0 && report.daysWithFocus == 0)
            #expect(report.partialSessions == 0 && report.scheduledDays == 0 && report.workedScheduledDays == 0)
        }
    }

    @Test func J015_J028_maximumRangeAndStrictWeeklyThresholdUseElapsedDuration() throws {
        let utc = ReportingCalendar(timeZone: .gmt)
        let start = try #require(utc.parseLocalDateTime("2020-01-01T00:00"))
        let exactly93 = JournalReport.build(records: [], from: start, until: start.addingTimeInterval(93 * 86_400),
                                           schedule: anyDay, calendar: utc)
        #expect(exactly93.grouping == .day)
        #expect(exactly93.days.count == 93)
        let above93 = JournalReport.build(records: [], from: start, until: start.addingTimeInterval(93 * 86_400 + 0.001),
                                         schedule: anyDay, calendar: utc)
        #expect(above93.grouping == .week)
        #expect(above93.days.count == 94)
        let limit = JournalReport.build(records: [], from: start, until: start.addingTimeInterval(JournalReport.maximumDuration),
                                       schedule: anyDay, calendar: utc)
        #expect(limit.error == nil)
        #expect(limit.days.count == 3_660)
        #expect(limit.grouping == .week)
        // The owner retains the effective grouping; the engine never silently
        // restores day grouping merely because the interval gets shorter.
        let shortened = JournalReport.build(records: [], from: start, until: start.addingTimeInterval(86_400),
                                           schedule: anyDay, grouping: above93.grouping, calendar: utc)
        #expect(shortened.grouping == .week)
    }

    @Test func W012_missingCutoffsMoveForwardButMissingExplicitRangeTimesAreRejected() throws {
        let cutoff = try calendar.date(at: civil("2026-03-29"), cutoffMinutes: 3 * 60 + 30)
        #expect(calendar.localDateTime(cutoff) == "2026-03-29T04:30")
        #expect(calendar.parseLocalDateTime("2026-03-29T03:30") == nil)
        #expect(calendar.parseLocalDateTime("2026-03-29T04:30") == cutoff)
        let folded = try #require(calendar.parseLocalDateTime("2026-10-25T03:30"))
        #expect(calendar.timeZone.secondsFromGMT(for: folded) == 10_800)
        #expect(calendar.timeZone.secondsFromGMT(for: folded.addingTimeInterval(3_600)) == 7_200)
        #expect(calendar.localDateTime(folded.addingTimeInterval(3_600)) == "2026-10-25T03:30")
        #expect(try calendar.date(at: civil("2026-10-25"), cutoffMinutes: 210) == folded)
        #expect(calendar.parseLocalDateTime("2026-10-25T03:30") == folded)
    }

    @Test func J013_J014_rawInputRequiresExactValidCivilDateAndMinute() throws {
        for raw in ["", "2026-02-30T10:00", "2026-2-03T10:00", "2026-02-03T24:00", "2026-02-03T23:60",
                    "2026-02-03 10:00", "2026-02-03T10:00:00", "2026-02-03T10:00Z", "0000-01-01T00:00",
                    "10000-01-01T00:00", "２０２６-01-01T00:00", "2026-01-01T 1:00"] {
            #expect(calendar.parseLocalDateTime(raw) == nil, "\(raw) must be invalid")
        }
        #expect(calendar.parseLocalDateTime("2024-02-29T00:00") != nil)
        #expect(calendar.parseLocalDateTime("2026-10-17T23:59") != nil)
        #expect(calendar.parseCivilDate("2026-02-29") == nil)
        #expect(try calendar.addingDays(1, to: civil("2024-02-28")).iso8601Date == "2024-02-29")
        #expect(try calendar.addingDays(1, to: civil("2026-12-31")).iso8601Date == "2027-01-01")
        #expect(try calendar.addingDays(-1, to: civil("2026-01-01")).iso8601Date == "2025-12-31")
    }

    @Test func W012_unsupportedCalendarAndCutoffsFailExplicitly() throws {
        for cutoff in [-1, 1_440] {
            #expect(throws: ModelValidationError.self) { try calendar.date(at: civil("2026-10-17"), cutoffMinutes: cutoff) }
        }
        #expect(throws: ModelValidationError.self) { try calendar.addingDays(-1, to: civil("0001-01-01")) }
        #expect(throws: ModelValidationError.self) { try calendar.addingDays(1, to: civil("9999-12-31")) }
        #expect(throws: ModelValidationError.self) { try calendar.day(containing: Date(timeIntervalSince1970: .nan)) }
        let apia = ReportingCalendar(timeZone: try #require(TimeZone(identifier: "Pacific/Apia")))
        #expect(throws: ModelValidationError.self) { try apia.date(at: civil("2011-12-30")) }
    }

    @Test func J022_invalidNativeRecordsAndDuplicateIDsProduceVisibleErrors() throws {
        let original = try record("2026-10-17", hour: 9)
        var malformed = original
        malformed.segments[0].endedAt = malformed.startedAt.addingTimeInterval(-1)
        let invalid = try build([malformed], "2026-10-17T00:00", "2026-10-18T00:00")
        #expect(invalid.error != nil)
        #expect(invalid.rows.isEmpty)
        let duplicate = try build([original, original], "2026-10-17T00:00", "2026-10-18T00:00")
        #expect(duplicate.error == "The report contains a duplicate session identifier.")
        var schedule = anyDay; schedule.reportingDayStartMinutes = -1
        let invalidSchedule = try build([], "2026-10-17T00:00", "2026-10-18T00:00", schedule: schedule)
        #expect(invalidSchedule.error != nil)
        #expect(invalidSchedule.rows.isEmpty)
    }

    @Test func J036_J040_reportProjectionKeepsAll25RowsAndSubsecondPrecision() throws {
        let start = try at("2026-10-17", 9)
        let records = (0..<25).map { session(start.addingTimeInterval(Double($0) * 120), seconds: 60) }
        let report = try build(records, "2026-10-17T00:00", "2026-10-18T00:00")
        #expect(report.rows.count == 25)
        #expect(report.rows.map(\.id) == records.reversed().map(\.id))
        #expect(report.focusedSeconds == 1_500)
        #expect(report.completedCycles == 25)
        let record = session(start, seconds: 60)
        let precise = JournalReport.build(records: [record], from: start.addingTimeInterval(0.125),
            until: start.addingTimeInterval(59.875), schedule: anyDay, calendar: calendar)
        #expect(precise.focusedSeconds == 59.75)
        #expect(precise.rows.first?.totalFocusedSeconds == 60)
        #expect(precise.completedCycles == 0)
    }

    @Test func J024_validEmptyReportPreservesFutureAndZeroFocusDates() throws {
        let report = try build([], "2090-01-01T00:00", "2090-01-08T00:00")
        #expect(report.error == nil)
        #expect(report.days.count == 7)
        #expect(report.daysWithFocus == 0)
        #expect(report.buckets.count == 7)
        #expect(report.buckets.allSatisfy { $0.focusedSeconds == 0 && $0.completedCycles == 0 })
        #expect(report.rows.isEmpty)
    }

    @Test func J022_displayRoundsDownOnlyAtFormattingBoundary() {
        let cases: [(Double, String, String)] = [(0, "0m", "0s"), (0.9, "0m", "0s"), (59.9, "59s", "59s"),
            (60, "1m", "1m"), (119.9, "1m", "1m 59s"), (3_600, "1h", "1h 0m"),
            (3_601.5, "1h", "1h 0m 1s"), (3_660, "1h 1m", "1h 1m")]
        for (seconds, compact, precise) in cases {
            #expect(JournalDuration.format(seconds: seconds) == compact)
            #expect(JournalDuration.format(seconds: seconds, precise: true) == precise)
        }
        for seconds in [-1.0, .nan, .infinity] {
            #expect(JournalDuration.format(seconds: seconds) == "0m")
        }
    }

    @Test func W012_zoneChangesReinterpretAbsoluteHistoryWithoutChangingRecords() throws {
        let start = try at("2026-10-17", 0, 30)
        let record = session(start, seconds: 3_600)
        let utc = ReportingCalendar(timeZone: .gmt)
        #expect(try calendar.day(containing: record.startedAt).iso8601Date == "2026-10-17")
        #expect(try utc.day(containing: record.startedAt).iso8601Date == "2026-10-16")
        let original = record
        let bounds = try utc.dayBounds(for: civil("2026-10-16"), schedule: anyDay)
        let report = JournalReport.build(records: [record], from: bounds.from, until: bounds.until,
                                         schedule: anyDay, calendar: utc)
        #expect(report.focusedSeconds == 3_600)
        #expect(report.rows.first?.record == original)
    }

    @Test func J020_examplesCover35CivilDatesWithSpecifiedCountsDurationsPausesAndGaps() throws {
        let now = try at("2026-10-18", 23, 59)
        let records = try ExampleSessions.generate(now: now, calendar: calendar)
        #expect(records.count == 75)
        #expect(try records == ExampleSessions.generate(now: now, calendar: calendar))
        #expect(Set(records.map(\.id)).count == records.count)
        let grouped = try Dictionary(grouping: records) { try calendar.day(containing: $0.startedAt) }
        #expect(grouped.count == 30) // Five Sundays intentionally have no rows.
        for offset in -34...0 {
            let date = try calendar.addingDays(offset, to: civil("2026-10-18"))
            let weekday = try calendar.weekday(of: date)
            let expected = [3, 2, 4, 3, 2, 1, 0][weekday.rawValue - 1]
            let dayRecords = grouped[date] ?? []
            #expect(dayRecords.count == expected)
            if let first = dayRecords.first {
                #expect(try first.startedAt == calendar.date(at: date, cutoffMinutes: 550))
            }
            for (index, record) in dayRecords.enumerated() {
                try record.validate()
                #expect(record.endedAt <= now)
                #expect(record.plannedFocusMinutes == (index % 2 == 0 ? 60 : 90))
                let isPartial = weekday == .saturday || (weekday == .tuesday && index == 1)
                #expect(record.outcome == (isPartial ? .partial : .complete))
                if isPartial { #expect(record.focusedSeconds == (weekday == .saturday ? 35 : 25) * 60) }
                #expect(record.segments.count == (index == 1 ? 2 : 1))
                if index == 1 { #expect(record.segments[1].startedAt.timeIntervalSince(record.segments[0].endedAt) == 600) }
                if index > 0 { #expect(record.startedAt.timeIntervalSince(dayRecords[index - 1].endedAt) == 1_200) }
            }
        }
        #expect(try records.first?.startedAt == at("2026-09-14", 9, 10))
        let earliest = try at("2026-09-14")
        #expect(records.allSatisfy { $0.startedAt >= earliest })
    }

    @Test func J020_examplesExcludeFutureEndsAndIncludeExactEnd() throws {
        let before = try at("2026-10-19", 10, 9)
        let firstEnd = try at("2026-10-19", 10, 10)
        let earlier = try ExampleSessions.generate(now: before, calendar: calendar)
        let exact = try ExampleSessions.generate(now: firstEnd, calendar: calendar)
        #expect(earlier.allSatisfy { $0.endedAt <= before })
        #expect(exact.count == earlier.count + 1)
        #expect(exact.last?.endedAt == firstEnd)
        #expect(exact.last?.outcome == .complete)
    }

    private func civil(_ raw: String) throws -> CivilDate { try #require(calendar.parseCivilDate(raw)) }
    private func at(_ raw: String, _ hour: Int = 0, _ minute: Int = 0) throws -> Date {
        try calendar.date(at: civil(raw), cutoffMinutes: hour * 60 + minute)
    }
    private func build(_ records: [SessionRecord], _ from: String, _ until: String,
                       schedule: WorkSchedule? = nil, grouping: JournalGrouping = .day) throws -> JournalReport {
        let from = try #require(calendar.parseLocalDateTime(from))
        let until = try #require(calendar.parseLocalDateTime(until))
        return JournalReport.build(records: records, from: from, until: until, schedule: schedule ?? anyDay,
                                   grouping: grouping, calendar: calendar)
    }
    private func record(_ date: String, hour: Int, minutes: Int = 60, outcome: SessionOutcome = .complete) throws -> SessionRecord {
        session(try at(date, hour), seconds: Double(minutes) * 60, outcome: outcome)
    }
    private func session(_ start: Date, seconds: Double, outcome: SessionOutcome = .complete) -> SessionRecord {
        let end = start.addingTimeInterval(seconds)
        return SessionRecord(startedAt: start, endedAt: end,
            plannedFocusMinutes: outcome == .complete ? Int(seconds / 60) : 60, outcome: outcome,
            segments: [ActiveSegment(startedAt: start, endedAt: end)])
    }
}
