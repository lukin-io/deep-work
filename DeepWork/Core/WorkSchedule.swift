import Foundation

/// A civil date is not a UTC instant: changing reporting zones cannot shift a
/// stored rotating-shift anchor into the neighboring date.
public struct CivilDate: Codable, Equatable, Hashable, Sendable {
    public var year: Int
    public var month: Int
    public var day: Int

    public init(year: Int, month: Int, day: Int) {
        self.year = year; self.month = month; self.day = day
    }

    public init(_ date: Date, timeZone: TimeZone = .current) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        self.init(year: components.year!, month: components.month!, day: components.day!)
    }

    public func validate() throws {
        try require((1...9999).contains(year) && (1...12).contains(month) && (1...31).contains(day),
                    "First work day must be a valid Gregorian calendar date.")
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let components = DateComponents(year: year, month: month, day: day)
        guard let date = calendar.date(from: components) else {
            throw ModelValidationError("First work day must be a valid Gregorian calendar date.")
        }
        let result = calendar.dateComponents([.year, .month, .day], from: date)
        try require(result.year == year && result.month == month && result.day == day,
                    "First work day must be a valid Gregorian calendar date.")
    }

    public var iso8601Date: String { String(format: "%04d-%02d-%02d", year, month, day) }
}

/// ISO weekday numbering; explicit cases avoid Calendar's Sunday-first indexing.
public enum Weekday: Int, Codable, CaseIterable, Sendable {
    case monday = 1, tuesday, wednesday, thursday, friday, saturday, sunday

    public var name: String {
        switch self {
        case .monday: return "Monday"
        case .tuesday: return "Tuesday"
        case .wednesday: return "Wednesday"
        case .thursday: return "Thursday"
        case .friday: return "Friday"
        case .saturday: return "Saturday"
        case .sunday: return "Sunday"
        }
    }
}

public enum ScheduleMode: String, Codable, Sendable { case chosenWeekdays, anyDay, rotatingShifts }

public struct WorkSchedule: Codable, Equatable, Sendable {
    public var mode: ScheduleMode
    public var weekdays: [Weekday]
    public var workDays: Int
    public var restDays: Int
    public var firstWorkDay: CivilDate
    public var weekStartsOn: Weekday
    public var reportingDayStartMinutes: Int

    public init(mode: ScheduleMode = .chosenWeekdays,
                weekdays: [Weekday] = [.monday, .tuesday, .wednesday, .thursday, .friday],
                workDays: Int = 2, restDays: Int = 2,
                firstWorkDay: CivilDate = CivilDate(Date()), weekStartsOn: Weekday = .monday,
                reportingDayStartMinutes: Int = 0) {
        self.mode = mode; self.weekdays = weekdays
        self.workDays = workDays; self.restDays = restDays
        self.firstWorkDay = firstWorkDay; self.weekStartsOn = weekStartsOn
        self.reportingDayStartMinutes = reportingDayStartMinutes
    }

    public static func defaults(now: Date = Date(), timeZone: TimeZone = .current) -> WorkSchedule {
        WorkSchedule(firstWorkDay: CivilDate(now, timeZone: timeZone))
    }

    public func validate() throws {
        try require(Set(weekdays).count == weekdays.count, "Chosen weekdays must not contain duplicates.")
        try require((1...31).contains(workDays) && (1...31).contains(restDays),
                    "Rotating shifts require 1 through 31 work days and rest days.")
        try firstWorkDay.validate()
        try require((0...1439).contains(reportingDayStartMinutes), "Reporting day start must be a valid minute of day.")
    }
}
