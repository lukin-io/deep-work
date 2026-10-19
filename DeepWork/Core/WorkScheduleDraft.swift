import Foundation

/// Form input stays separate from the validated schedule used by reports and
/// SQLite. An incomplete hidden shift field must not invalidate Any day.
public struct WorkScheduleDraft: Equatable, Sendable {
    public var mode: ScheduleMode
    public var weekdays: [Weekday]
    public var workDaysText: String
    public var restDaysText: String
    public var firstWorkDayText: String
    public var weekStartsOn: Weekday
    public var reportingDayStartText: String

    private let savedSchedule: WorkSchedule

    public init(schedule: WorkSchedule) {
        savedSchedule = schedule
        mode = schedule.mode
        weekdays = schedule.weekdays
        workDaysText = String(schedule.workDays)
        restDaysText = String(schedule.restDays)
        firstWorkDayText = schedule.firstWorkDay.iso8601Date
        weekStartsOn = schedule.weekStartsOn
        reportingDayStartText = String(format: "%02d:%02d", schedule.reportingDayStartMinutes / 60,
                                       schedule.reportingDayStartMinutes % 60)
    }

    public var validationError: String? {
        do { _ = try validated(); return nil }
        catch { return error.localizedDescription }
    }

    public var validatedSchedule: WorkSchedule? { try? validated() }

    /// Preserve the reference's active-field error priority: an invalid shift
    /// anchor replaces a count error, which replaces a cutoff error.
    public func validated() throws -> WorkSchedule {
        let cutoff = Self.parseCutoff(reportingDayStartText)
        let work = Self.parseCount(workDaysText)
        let rest = Self.parseCount(restDaysText)
        let anchor = ReportingCalendar(timeZone: .gmt).parseCivilDate(firstWorkDayText)
        var error: String?
        if cutoff == nil { error = "Choose a valid reporting-day start time." }
        if mode == .rotatingShifts {
            if work == nil || rest == nil { error = "Choose 1–31 work days and 1–31 rest days." }
            if anchor == nil { error = "Choose the first work day of your shift pattern." }
        }
        if let error { throw ModelValidationError(error) }
        guard let cutoff else { throw ModelValidationError("Choose a valid reporting-day start time.") }

        // Inactive raw edits remain in the draft. Only valid typed values enter
        // storage; invalid inactive fields retain their last committed values.
        let result = WorkSchedule(mode: mode, weekdays: weekdays, workDays: work ?? savedSchedule.workDays,
                                  restDays: rest ?? savedSchedule.restDays,
                                  firstWorkDay: anchor ?? savedSchedule.firstWorkDay,
                                  weekStartsOn: weekStartsOn, reportingDayStartMinutes: cutoff)
        try result.validate()
        return result
    }

    public mutating func setWeekday(_ weekday: Weekday, selected: Bool) {
        var selection = Set(weekdays)
        if selected { selection.insert(weekday) } else { selection.remove(weekday) }
        weekdays = Weekday.allCases.filter { selection.contains($0) }
    }

    /// Invalid input deliberately clears the preview. Calendar failures remain
    /// errors so the native UI can report them instead of presenting false dates.
    public func preview(now: Date, timeZone: TimeZone) throws -> [SchedulePreviewDay] {
        guard let schedule = validatedSchedule else { return [] }
        let reportingCalendar = ReportingCalendar(timeZone: timeZone)
        let first = try reportingCalendar.day(containing: now, cutoffMinutes: schedule.reportingDayStartMinutes)
        return try (0..<14).map { offset in
            let day = try reportingCalendar.addingDays(offset, to: first)
            let weekday = try reportingCalendar.weekday(of: day)
            return SchedulePreviewDay(date: day, weekday: weekday,
                                      isScheduled: try reportingCalendar.isScheduled(day, schedule: schedule))
        }
    }

    private static func parseCount(_ raw: String) -> Int? {
        guard !raw.isEmpty, raw.utf8.allSatisfy({ (48...57).contains($0) }),
              let count = Int(raw), (1...31).contains(count) else { return nil }
        return count
    }

    private static func parseCutoff(_ raw: String) -> Int? {
        let parts = raw.split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count == 2, parts.allSatisfy({ $0.utf8.count == 2 && $0.utf8.allSatisfy { (48...57).contains($0) } }),
              let hour = Int(parts[0]), (0...23).contains(hour),
              let minute = Int(parts[1]), (0...59).contains(minute) else { return nil }
        return hour * 60 + minute
    }

}

public struct SchedulePreviewDay: Equatable, Sendable, Identifiable {
    public let date: CivilDate
    public let weekday: Weekday
    public let isScheduled: Bool
    public var id: CivilDate { date }
}
