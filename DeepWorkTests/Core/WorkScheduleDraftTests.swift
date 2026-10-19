import Foundation
import Testing
@testable import DeepWorkCore

struct WorkScheduleDraftTests {
    private let anchor = CivilDate(year: 2026, month: 10, day: 19)

    @Test func W002_W019_draftCopiesEverySavedFieldWithoutChangingTheSchedule() throws {
        let saved = WorkSchedule(mode: .rotatingShifts, weekdays: [.monday, .sunday], workDays: 3, restDays: 4,
                                 firstWorkDay: anchor, weekStartsOn: .sunday, reportingDayStartMinutes: 1439)
        var draft = WorkScheduleDraft(schedule: saved)
        #expect(draft.mode == .rotatingShifts)
        #expect(draft.weekdays == [.monday, .sunday])
        #expect(draft.workDaysText == "3")
        #expect(draft.restDaysText == "4")
        #expect(draft.firstWorkDayText == "2026-10-19")
        #expect(draft.weekStartsOn == .sunday)
        #expect(draft.reportingDayStartText == "23:59")
        #expect(try draft.validated() == saved)
        draft.workDaysText = "7"
        draft.reportingDayStartText = "04:00"
        #expect(saved.workDays == 3)
        #expect(saved.reportingDayStartMinutes == 1439)
        #expect(try draft.validated().workDays == 7)
    }

    @Test func W003_W004_allModesAndIndependentWeekdaysPreserveZeroDayMeaning() throws {
        var draft = WorkScheduleDraft(schedule: WorkSchedule(firstWorkDay: anchor))
        #expect(draft.mode == .chosenWeekdays)
        #expect(draft.weekdays == [.monday, .tuesday, .wednesday, .thursday, .friday])
        for weekday in Weekday.allCases { draft.setWeekday(weekday, selected: false) }
        #expect(try draft.validated().weekdays.isEmpty)
        #expect(draft.validationError == nil)
        for weekday in Weekday.allCases.reversed() {
            draft.setWeekday(weekday, selected: true)
            draft.setWeekday(weekday, selected: true)
        }
        #expect(draft.weekdays == Weekday.allCases)
        draft.setWeekday(.wednesday, selected: false)
        #expect(draft.weekdays == [.monday, .tuesday, .thursday, .friday, .saturday, .sunday])
        for mode in [ScheduleMode.chosenWeekdays, .anyDay, .rotatingShifts] {
            draft.mode = mode
            #expect(try draft.validated().mode == mode)
            #expect(draft.weekdays.count == 6)
        }
    }

    @Test func W006_W007_shiftBoundsAcceptOneAndThirtyOne() throws {
        var draft = WorkScheduleDraft(schedule: WorkSchedule(mode: .rotatingShifts, firstWorkDay: anchor))
        for work in [1, 31] {
            for rest in [1, 31] {
                draft.workDaysText = String(work)
                draft.restDaysText = String(rest)
                let saved = try draft.validated()
                #expect(saved.workDays == work)
                #expect(saved.restDays == rest)
                #expect(draft.validationError == nil)
            }
        }
    }

    @Test(arguments: ["", "0", "-1", "32", "2.5", "2.0", "+2", " 2", "2 ", "two", "２", "1e1",
                      "99999999999999999999999999999999999999"])
    func W006_W007_W015_invalidShiftCountsStayRawAndBlockSaving(_ raw: String) throws {
        for field in [\WorkScheduleDraft.workDaysText, \.restDaysText] {
            var draft = WorkScheduleDraft(schedule: WorkSchedule(mode: .rotatingShifts, firstWorkDay: anchor))
            draft[keyPath: field] = raw
            #expect(draft[keyPath: field] == raw)
            #expect(draft.validationError == "Choose 1–31 work days and 1–31 rest days.")
            #expect(draft.validatedSchedule == nil)
            #expect(throws: ModelValidationError.self) { try draft.validated() }
        }
    }

    @Test func W008_anchorRequiresAnExactValidCivilDateWithoutATodayLimit() throws {
        var draft = WorkScheduleDraft(schedule: WorkSchedule(mode: .rotatingShifts, firstWorkDay: anchor))
        for value in ["", "2026-02-29", "2026-04-31", "2026-00-19", "0000-01-01", "2026-1-01",
                      "2026-10-19T00:00", "2026-10-19 ", "not a date"] {
            draft.firstWorkDayText = value
            #expect(draft.validationError == "Choose the first work day of your shift pattern.")
            #expect(draft.validatedSchedule == nil)
        }
        for value in ["2024-02-29", "1900-01-01", "2099-12-31"] {
            draft.firstWorkDayText = value
            #expect(try draft.validated().firstWorkDay.iso8601Date == value)
        }
    }

    @Test func W010_allWeekStartsPreserveTheWorkPattern() throws {
        var draft = WorkScheduleDraft(schedule: WorkSchedule(firstWorkDay: anchor))
        for weekday in Weekday.allCases {
            draft.weekStartsOn = weekday
            let schedule = try draft.validated()
            #expect(schedule.weekStartsOn == weekday)
            #expect(schedule.weekdays == [.monday, .tuesday, .wednesday, .thursday, .friday])
        }
    }

    @Test func W011_cutoffBoundsAndMinutePrecision() throws {
        var draft = WorkScheduleDraft(schedule: WorkSchedule(firstWorkDay: anchor))
        for (raw, expected) in [("00:00", 0), ("04:00", 240), ("09:07", 547), ("23:59", 1439)] {
            draft.reportingDayStartText = raw
            #expect(try draft.validated().reportingDayStartMinutes == expected)
            #expect(draft.validationError == nil)
        }
    }

    @Test func W011_W015_missingOrInvalidCutoffIsInvalidInEveryMode() {
        var draft = WorkScheduleDraft(schedule: WorkSchedule(firstWorkDay: anchor))
        for mode in [ScheduleMode.chosenWeekdays, .anyDay, .rotatingShifts] {
            draft.mode = mode
            for raw in ["", "4:00", "04:0", "24:00", "23:60", "-1:00", "12:30:00", " 04:00", "０４:００", "aa:bb"] {
                draft.reportingDayStartText = raw
                #expect(draft.validatedSchedule == nil)
                #expect(draft.validationError == "Choose a valid reporting-day start time.")
            }
        }
    }

    @Test func W015_validationPriorityMatchesTheActiveShiftFields() {
        var draft = WorkScheduleDraft(schedule: WorkSchedule(mode: .rotatingShifts, firstWorkDay: anchor))
        draft.reportingDayStartText = ""
        draft.workDaysText = "0"
        draft.firstWorkDayText = ""
        #expect(draft.validationError == "Choose the first work day of your shift pattern.")
        draft.firstWorkDayText = "2026-10-19"
        #expect(draft.validationError == "Choose 1–31 work days and 1–31 rest days.")
        draft.workDaysText = "2"
        #expect(draft.validationError == "Choose a valid reporting-day start time.")
        draft.reportingDayStartText = "00:00"
        #expect(draft.validationError == nil)
    }

    @Test func W002_W005_inactiveInvalidShiftInputIsRetainedWithoutBlockingOtherModes() throws {
        let saved = WorkSchedule(mode: .rotatingShifts, workDays: 3, restDays: 4, firstWorkDay: anchor)
        var draft = WorkScheduleDraft(schedule: saved)
        draft.workDaysText = ""
        draft.restDaysText = "1.5"
        draft.firstWorkDayText = "2026-02-29"
        #expect(draft.validatedSchedule == nil)
        for mode in [ScheduleMode.anyDay, .chosenWeekdays] {
            draft.mode = mode
            let candidate = try draft.validated()
            #expect(candidate.mode == mode)
            #expect(candidate.workDays == 3)
            #expect(candidate.restDays == 4)
            #expect(candidate.firstWorkDay == anchor)
            #expect(draft.workDaysText == "")
            #expect(draft.restDaysText == "1.5")
            #expect(draft.firstWorkDayText == "2026-02-29")
        }
        draft.mode = .rotatingShifts
        #expect(draft.validationError == "Choose the first work day of your shift pattern.")
        draft.mode = .anyDay
        draft.workDaysText = "7"
        draft.firstWorkDayText = "2024-02-29"
        let candidate = try draft.validated()
        #expect(candidate.workDays == 7)
        #expect(candidate.restDays == 4)
        #expect(candidate.firstWorkDay == CivilDate(year: 2024, month: 2, day: 29))
        try candidate.validate()
    }

    @Test func W014_previewHasFourteenConsecutiveDatesAcrossTheYearAndUsesDraftCutoff() throws {
        let calendar = ReportingCalendar(timeZone: .gmt)
        let now = try #require(calendar.parseLocalDateTime("2026-12-28T03:30"))
        var draft = WorkScheduleDraft(schedule: WorkSchedule(firstWorkDay: anchor))
        draft.reportingDayStartText = "04:00"
        let days = try draft.preview(now: now, timeZone: .gmt)
        #expect(days.count == 14)
        #expect(days.first?.date == CivilDate(year: 2026, month: 12, day: 27))
        #expect(days.last?.date == CivilDate(year: 2027, month: 1, day: 9))
        #expect(days.first?.weekday == .sunday)
        for index in 1..<days.count {
            #expect(days[index].date == (try calendar.addingDays(1, to: days[index - 1].date)))
        }
        draft.reportingDayStartText = "03:30"
        #expect(try draft.preview(now: now, timeZone: .gmt).first?.date == CivilDate(year: 2026, month: 12, day: 28))
    }

    @Test func W004_W005_previewDistinguishesZeroWeekdaysAnyDayAndSpecificDays() throws {
        let calendar = ReportingCalendar(timeZone: .gmt)
        let now = try #require(calendar.parseLocalDateTime("2026-10-19T12:00"))
        var draft = WorkScheduleDraft(schedule: WorkSchedule(weekdays: [], firstWorkDay: anchor))
        #expect(try draft.preview(now: now, timeZone: .gmt).filter(\.isScheduled).count == 0)
        draft.mode = .anyDay
        #expect(try draft.preview(now: now, timeZone: .gmt).filter(\.isScheduled).count == 14)
        draft.mode = .chosenWeekdays
        draft.setWeekday(.saturday, selected: true)
        draft.setWeekday(.sunday, selected: true)
        let weekend = try draft.preview(now: now, timeZone: .gmt)
        #expect(weekend.filter(\.isScheduled).count == 4)
        #expect(weekend.filter(\.isScheduled).allSatisfy { [.saturday, .sunday].contains($0.weekday) })
    }

    @Test func W009_W012_previewRotatesBeforeTheAnchorAcrossBothKyivDSTChanges() throws {
        let zone = try #require(TimeZone(identifier: "Europe/Kyiv"))
        let calendar = ReportingCalendar(timeZone: zone)
        for anchorText in ["2026-03-29", "2026-10-25"] {
            let firstWorkDay = try #require(calendar.parseCivilDate(anchorText))
            let startDay = try calendar.addingDays(-2, to: firstWorkDay)
            let now = try calendar.date(at: startDay, cutoffMinutes: 12 * 60)
            let draft = WorkScheduleDraft(schedule: WorkSchedule(mode: .rotatingShifts, firstWorkDay: firstWorkDay))
            let days = try draft.preview(now: now, timeZone: zone)
            #expect(days.count == 14)
            #expect(days.map(\.isScheduled) == [false, false, true, true, false, false, true, true,
                                              false, false, true, true, false, false])
            #expect(days[2].date == firstWorkDay)
            #expect(days[2].weekday == .sunday)
        }
    }

    @Test func W014_W015_invalidDraftClearsPreviewAndCorrectionRestoresIt() throws {
        let now = Date(timeIntervalSince1970: 1_792_410_000)
        var draft = WorkScheduleDraft(schedule: WorkSchedule(mode: .rotatingShifts, firstWorkDay: anchor))
        draft.workDaysText = ""
        #expect(try draft.preview(now: now, timeZone: .gmt).isEmpty)
        draft.workDaysText = "1"
        #expect(try draft.preview(now: now, timeZone: .gmt).count == 14)
        draft.reportingDayStartText = "24:00"
        #expect(try draft.preview(now: now, timeZone: .gmt).isEmpty)
        draft.reportingDayStartText = "00:00"
        draft.firstWorkDayText = ""
        #expect(try draft.preview(now: now, timeZone: .gmt).isEmpty)
        draft.firstWorkDayText = "2026-10-19"
        #expect(try draft.preview(now: now, timeZone: .gmt).count == 14)
    }

    @Test func W014_previewRejectsAnUnrepresentableObservationTime() {
        let draft = WorkScheduleDraft(schedule: WorkSchedule(firstWorkDay: anchor))
        #expect(throws: ModelValidationError.self) {
            try draft.preview(now: Date(timeIntervalSince1970: .infinity), timeZone: .gmt)
        }
    }
}
