import Foundation
import Testing
@testable import DeepWorkCore

final class ModelTests {
    let start = Date(timeIntervalSince1970: 1_792_300_000.125)

    @Test func testConfigurationDefaultsAndPresetChoices() throws {
        let initial = FocusConfiguration()
        #expect(initial.focusSelection == .unselected)
        #expect(initial.breakSelection == .unselected)
        #expect(initial.customFocusMinutes == 75)
        #expect(initial.customBreakMinutes == 15)
        #expect(initial.repeats)
        #expect(!(initial.canStart))
        try initial.validate()
        for focus in [60, 90] {
            for rest in [10, 20] {
                let config = FocusConfiguration(focusSelection: .preset(focus), breakSelection: .preset(rest))
                try config.validate()
                #expect(config.resolvedFocusMinutes == focus)
                #expect(config.resolvedBreakMinutes == rest)
                #expect(config.canStart)
            }
        }
    }

    @Test func testCustomDurationBoundsAndRetainedHiddenValues() throws {
        for minutes in [1, 480] {
            var config = FocusConfiguration(focusSelection: .custom, breakSelection: .custom,
                                            customFocusMinutes: minutes, customBreakMinutes: minutes)
            try config.validate()
            #expect(config.canStart)
            config.focusSelection = .preset(60)
            config.breakSelection = .preset(10)
            #expect(config.customFocusMinutes == minutes)
            #expect(config.customBreakMinutes == minutes)
        }
        for minutes in [0, -1, 481] {
            let config = FocusConfiguration(focusSelection: .custom, customFocusMinutes: minutes)
            #expect(throws: (any Error).self) { try config.validate() }
            #expect(config.resolvedFocusMinutes == nil)
        }
        #expect(throws: (any Error).self) { try FocusConfiguration(focusSelection: .preset(10)).validate() }
        #expect(throws: (any Error).self) { try FocusConfiguration(breakSelection: .preset(60)).validate() }
    }

    @Test func testRawSegmentsExcludePausesAndAllowTouchingBoundaries() throws {
        let record = SessionRecord(startedAt: start, endedAt: start.addingTimeInterval(4200),
                                   plannedFocusMinutes: 60, outcome: .complete, segments: [
            ActiveSegment(startedAt: start, endedAt: start.addingTimeInterval(1200)),
            ActiveSegment(startedAt: start.addingTimeInterval(1800), endedAt: start.addingTimeInterval(3000)),
            ActiveSegment(startedAt: start.addingTimeInterval(3000), endedAt: start.addingTimeInterval(4200))
        ])
        try record.validate()
        #expect(record.focusedSeconds == 3600)
        #expect(record.endedAt.timeIntervalSince(record.startedAt) == 4200)
        #expect(record.segments.count == 3)
    }

    @Test func testInvalidSegmentBoundsOrderingAndOverlapAreRejectedWithoutSorting() {
        let cases: [[ActiveSegment]] = [
            [segment(-1, 10)], [segment(0, 61)], [segment(10, 10)], [segment(10, 9)],
            [segment(20, 30), segment(0, 10)], [segment(0, 20), segment(10, 30)]
        ]
        for segments in cases {
            let record = SessionRecord(startedAt: start, endedAt: start.addingTimeInterval(60),
                                       plannedFocusMinutes: 1, outcome: .partial, segments: segments)
            #expect(throws: (any Error).self) { try record.validate() }
        }
    }

    @Test func testRecordAccountingRequiresPositiveFinalizedFocusAndFullCompletion() throws {
        var record = SessionRecord(startedAt: start, endedAt: start.addingTimeInterval(60),
                                   plannedFocusMinutes: 1, outcome: .partial, segments: [])
        #expect(throws: (any Error).self) { try record.validate() }
        record.outcome = .live
        #expect(throws: (any Error).self) { try record.validate() }
        try record.validate(allowLive: true)
        record.segments = [segment(0, 20)]
        record.outcome = .complete
        #expect(throws: (any Error).self) { try record.validate() }
        record.outcome = .partial
        try record.validate()
        record.segments = [segment(0, 60)]
        record.outcome = .complete
        try record.validate()
        record.endedAt = start.addingTimeInterval(61)
        record.segments = [segment(0, 61)]
        #expect(throws: (any Error).self) { try record.validate() }
    }

    @Test func testInvalidDatesAndPlannedMinutesAreRejected() {
        var record = partial()
        record.startedAt = Date(timeIntervalSince1970: .infinity)
        #expect(throws: (any Error).self) { try record.validate() }
        record = partial(); record.endedAt = Date(timeIntervalSince1970: .nan)
        #expect(throws: (any Error).self) { try record.validate() }
        record = partial(); record.startedAt = Date(timeIntervalSince1970: 8_640_000_000_001)
        #expect(throws: (any Error).self) { try record.validate() }
        for minutes in [0, 481] {
            record = partial(); record.plannedFocusMinutes = minutes
            #expect(throws: (any Error).self) { try record.validate() }
        }
    }

    @Test func testDuplicateFinalizedAndLiveIdentifiersAreRejected() throws {
        let record = partial()
        #expect(throws: (any Error).self) { try JournalDocument(records: [record, record]).validate() }
        var live = record
        live.outcome = .live
        let checkpoint = ActiveCheckpoint(phase: .focus, focusMinutes: 1, breakMinutes: 10,
                                          remainingSeconds: 40, savedAt: live.endedAt, focusRecord: live)
        try checkpoint.validate()
        #expect(throws: (any Error).self) { try JournalDocument(records: [record], activeCheckpoint: checkpoint).validate() }
    }

    @Test func testFocusCheckpointSealsElapsedTimeAndRequiresMatchingRemainder() throws {
        var live = partial(); live.outcome = .live
        var checkpoint = ActiveCheckpoint(phase: .focus, focusMinutes: 1, breakMinutes: 10,
                                          remainingSeconds: 40, savedAt: live.endedAt, focusRecord: live)
        try checkpoint.validate()
        checkpoint.remainingSeconds = 41
        #expect(throws: (any Error).self) { try checkpoint.validate() }
        checkpoint.remainingSeconds = 40
        checkpoint.savedAt = checkpoint.savedAt.addingTimeInterval(1)
        #expect(throws: (any Error).self) { try checkpoint.validate() }
        checkpoint.savedAt = live.endedAt; checkpoint.focusRecord = nil
        #expect(throws: (any Error).self) { try checkpoint.validate() }
    }

    @Test func testBreakCheckpointHasNoFocusAndRemainderIsBounded() throws {
        var checkpoint = ActiveCheckpoint(phase: .break, focusMinutes: 60, breakMinutes: 10,
                                          remainingSeconds: 600, savedAt: start)
        try checkpoint.validate()
        for remainder in [0, -1, 601, Double.infinity, Double.nan] {
            checkpoint.remainingSeconds = remainder
            #expect(throws: (any Error).self) { try checkpoint.validate() }
        }
        checkpoint.remainingSeconds = 100
        checkpoint.focusRecord = partial()
        #expect(throws: (any Error).self) { try checkpoint.validate() }
    }

    @Test func testScheduleDefaultsEmptyWeekdaysAndAllModes() throws {
        let schedule = WorkSchedule.defaults(now: start, timeZone: TimeZone(secondsFromGMT: 0)!)
        #expect(schedule.mode == .chosenWeekdays)
        #expect(schedule.weekdays == [.monday, .tuesday, .wednesday, .thursday, .friday])
        #expect(schedule.weekStartsOn == .monday)
        #expect(schedule.reportingDayStartMinutes == 0)
        #expect(schedule.workDays == 2)
        #expect(schedule.restDays == 2)
        for mode in [ScheduleMode.chosenWeekdays, .anyDay, .rotatingShifts] {
            var variant = schedule
            variant.mode = mode; variant.weekdays = []
            try variant.validate()
            #expect(variant.weekdays == [])
        }
    }

    @Test func testScheduleRejectsInvalidDateShiftCutoffAndDuplicateWeekdays() throws {
        try CivilDate(year: 2024, month: 2, day: 29).validate()
        for date in [CivilDate(year: 2026, month: 2, day: 29), CivilDate(year: 2026, month: 4, day: 31),
                     CivilDate(year: 0, month: 1, day: 1), CivilDate(year: 2026, month: 13, day: 1)] {
            #expect(throws: (any Error).self) { try date.validate() }
        }
        for invalid in [0, 32] {
            #expect(throws: (any Error).self) { try WorkSchedule(workDays: invalid).validate() }
            #expect(throws: (any Error).self) { try WorkSchedule(restDays: invalid).validate() }
        }
        for valid in [1, 31] { try WorkSchedule(workDays: valid, restDays: valid).validate() }
        for invalid in [-1, 1440] {
            #expect(throws: (any Error).self) { try WorkSchedule(reportingDayStartMinutes: invalid).validate() }
        }
        try WorkSchedule(reportingDayStartMinutes: 1439).validate()
        #expect(throws: (any Error).self) { try WorkSchedule(weekdays: [.monday, .monday]).validate() }
    }

    @Test func testSchemaVersionsAreExplicit() {
        for version in [0, 2] {
            #expect(throws: (any Error).self) { try JournalDocument(version: version).validate() }
            #expect(throws: (any Error).self) { try SettingsDocument(version: version).validate() }
        }
    }

    private func segment(_ from: TimeInterval, _ until: TimeInterval) -> ActiveSegment {
        ActiveSegment(startedAt: start.addingTimeInterval(from), endedAt: start.addingTimeInterval(until))
    }
    private func partial() -> SessionRecord {
        SessionRecord(startedAt: start, endedAt: start.addingTimeInterval(20), plannedFocusMinutes: 1,
                      outcome: .partial, segments: [segment(0, 20)])
    }
}
