import Foundation

/// Gregorian civil dates in the device's reporting zone. Injecting the zone keeps
/// calendar arithmetic independent of the timer's absolute/monotonic clock.
public struct ReportingCalendar: Sendable {
    public let timeZone: TimeZone
    private let calendar: Calendar

    public init(timeZone: TimeZone = .current) {
        self.timeZone = timeZone
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        calendar.locale = Locale(identifier: "en_US_POSIX")
        self.calendar = calendar
    }

    /// Cutoffs move a missing local time forward while preserving its minutes;
    /// repeated times use the first occurrence, matching the approved reference.
    public func date(at day: CivilDate, cutoffMinutes: Int = 0) throws -> Date {
        try day.validate()
        try require((0...1439).contains(cutoffMinutes), "Reporting day start must be a valid minute of day.")
        guard let noon = calendar.date(from: DateComponents(year: day.year, month: day.month, day: day.day, hour: 12)),
              CivilDate(noon, timeZone: timeZone) == day else {
            throw ModelValidationError("The reporting date does not exist in this time zone.")
        }
        let start = calendar.startOfDay(for: noon)
        guard let result = calendar.nextDate(
            after: start.addingTimeInterval(-1),
            matching: DateComponents(hour: cutoffMinutes / 60, minute: cutoffMinutes % 60, second: 0),
            matchingPolicy: .nextTimePreservingSmallerComponents,
            repeatedTimePolicy: .first), CivilDate(result, timeZone: timeZone) == day else {
            throw ModelValidationError("The reporting date does not have a usable cutoff.")
        }
        return result
    }

    public func day(containing date: Date, cutoffMinutes: Int = 0) throws -> CivilDate {
        try validateTimestamp(date)
        try require(calendar.component(.era, from: date) == 1, "The date is outside the supported calendar.")
        let local = CivilDate(date, timeZone: timeZone)
        try local.validate()
        return date < (try self.date(at: local, cutoffMinutes: cutoffMinutes))
            ? try addingDays(-1, to: local) : local
    }

    /// Day offsets use a UTC Gregorian civil calendar, never elapsed local hours.
    public func addingDays(_ count: Int, to day: CivilDate) throws -> CivilDate {
        let calendar = Self.civilCalendar
        let value = try civilInstant(day)
        guard let shifted = calendar.date(byAdding: .day, value: count, to: value) else {
            throw ModelValidationError("The date is outside the supported calendar.")
        }
        try require(calendar.component(.era, from: shifted) == 1, "The date is outside the supported calendar.")
        let result = CivilDate(shifted, timeZone: .gmt)
        try result.validate()
        return result
    }

    public func weekday(of day: CivilDate) throws -> Weekday {
        let value = Self.civilCalendar.component(.weekday, from: try civilInstant(day))
        guard let result = Weekday(rawValue: (value + 5) % 7 + 1) else {
            throw ModelValidationError("The date has no valid weekday.")
        }
        return result
    }

    public func week(containing day: CivilDate, startsOn first: Weekday) throws -> CivilDate {
        let offset = ((try weekday(of: day)).rawValue - first.rawValue + 7) % 7
        return try addingDays(-offset, to: day)
    }

    public func isScheduled(_ day: CivilDate, schedule: WorkSchedule) throws -> Bool {
        try schedule.validate()
        try day.validate()
        switch schedule.mode {
        case .anyDay: return true
        case .chosenWeekdays: return try schedule.weekdays.contains(weekday(of: day))
        case .rotatingShifts:
            let calendar = Self.civilCalendar
            guard let offset = calendar.dateComponents([.day], from: try civilInstant(schedule.firstWorkDay),
                                                        to: try civilInstant(day)).day else {
                throw ModelValidationError("The shift date is outside the supported calendar.")
            }
            let period = schedule.workDays + schedule.restDays
            return ((offset % period) + period) % period < schedule.workDays
        }
    }

    public func dayBounds(for day: CivilDate, schedule: WorkSchedule) throws -> ReportBounds {
        try bounds(start: day, count: 1, schedule: schedule)
    }

    public func weekBounds(for day: CivilDate, schedule: WorkSchedule) throws -> ReportBounds {
        try bounds(start: week(containing: day, startsOn: schedule.weekStartsOn), count: 7, schedule: schedule)
    }

    /// Raw Range input is intentionally stricter than a reporting cutoff: a DST
    /// gap is invalid. An ambiguous value uses the earlier occurrence.
    public func parseLocalDateTime(_ raw: String) -> Date? {
        let bytes = Array(raw.utf8)
        guard bytes.count == 16, bytes[10] == 84, bytes[13] == 58,
              let day = parseCivilDate(String(raw.prefix(10))),
              let hour = Self.number(bytes[11..<13]), let minute = Self.number(bytes[14..<16]),
              (0...23).contains(hour), (0...59).contains(minute),
              let result = try? date(at: day, cutoffMinutes: hour * 60 + minute),
              localDateTime(result) == raw else { return nil }
        return result
    }

    public func parseCivilDate(_ raw: String) -> CivilDate? {
        let bytes = Array(raw.utf8)
        guard bytes.count == 10, bytes[4] == 45, bytes[7] == 45,
              let year = Self.number(bytes[0..<4]), let month = Self.number(bytes[5..<7]),
              let day = Self.number(bytes[8..<10]) else { return nil }
        let value = CivilDate(year: year, month: month, day: day)
        return (try? value.validate()) == nil ? nil : value
    }

    public func localDateTime(_ date: Date) -> String {
        let components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        guard let year = components.year, let month = components.month, let day = components.day,
              let hour = components.hour, let minute = components.minute else { return "" }
        return String(format: "%04d-%02d-%02dT%02d:%02d", year, month, day, hour, minute)
    }

    private func bounds(start: CivilDate, count: Int, schedule: WorkSchedule) throws -> ReportBounds {
        try schedule.validate()
        let from = try date(at: start, cutoffMinutes: schedule.reportingDayStartMinutes)
        let until = try date(at: addingDays(count, to: start), cutoffMinutes: schedule.reportingDayStartMinutes)
        try require(until > from, "Reporting boundaries must increase.")
        return ReportBounds(from: from, until: until)
    }

    private static var civilCalendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = .gmt
        return value
    }

    private func civilInstant(_ day: CivilDate) throws -> Date {
        try day.validate()
        guard let value = Self.civilCalendar.date(from: DateComponents(year: day.year, month: day.month, day: day.day)) else {
            throw ModelValidationError("The date is outside the supported calendar.")
        }
        return value
    }

    private static func number(_ bytes: ArraySlice<UInt8>) -> Int? {
        guard bytes.allSatisfy({ (48...57).contains($0) }) else { return nil }
        return bytes.reduce(0) { $0 * 10 + Int($1 - 48) }
    }
}
