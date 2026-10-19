import Foundation

public enum JournalGrouping: String, CaseIterable, Sendable { case day = "By day", week = "By week" }

public struct ReportBounds: Equatable, Sendable {
    public let from: Date
    public let until: Date
    public init(from: Date, until: Date) { self.from = from; self.until = until }
    public var duration: TimeInterval { until.timeIntervalSince(from) }
}

public struct JournalReportRow: Equatable, Identifiable, Sendable {
    public let record: SessionRecord
    public let focusedSeconds: TimeInterval
    public let totalFocusedSeconds: TimeInterval
    public let completedInRange: Bool
    public var id: UUID { record.id }
    public init(record: SessionRecord, focusedSeconds: TimeInterval, totalFocusedSeconds: TimeInterval, completedInRange: Bool) {
        self.record = record; self.focusedSeconds = focusedSeconds
        self.totalFocusedSeconds = totalFocusedSeconds; self.completedInRange = completedInRange
    }
}

public struct JournalReportDay: Equatable, Identifiable, Sendable {
    public let key: CivilDate
    public let start: Date
    public let end: Date
    public let focusedSeconds: TimeInterval
    public let completedCycles: Int
    public let isScheduled: Bool
    public var id: String { key.iso8601Date }
}

public struct JournalBucket: Equatable, Identifiable, Sendable {
    public let key: CivilDate
    /// Full calendar boundaries, even when the report clips this bucket.
    public let start: Date
    public let end: Date
    public let focusedSeconds: TimeInterval
    public let completedCycles: Int
    public let scheduledDays: Int
    public var id: String { key.iso8601Date }
    public init(key: CivilDate, start: Date, end: Date, focusedSeconds: TimeInterval,
                completedCycles: Int, scheduledDays: Int) {
        self.key = key; self.start = start; self.end = end
        self.focusedSeconds = focusedSeconds; self.completedCycles = completedCycles
        self.scheduledDays = scheduledDays
    }
}

/// One immutable projection supplies metrics, chart and every row (including the
/// future export), independently of the UI's current session page.
public struct JournalReport: Equatable, Sendable {
    public static let maximumDuration: TimeInterval = 3_660 * 86_400
    public static let dailyGroupingLimit: TimeInterval = 93 * 86_400
    public static let rangeError = "Choose valid local dates and an end time after the start, within a 10-year range."

    public let bounds: ReportBounds?
    public let error: String?
    public let grouping: JournalGrouping
    public let days: [JournalReportDay]
    public let buckets: [JournalBucket]
    public let rows: [JournalReportRow]
    public let focusedSeconds: TimeInterval
    public let completedCycles: Int
    public let partialSessions: Int
    public let daysWithFocus: Int
    public let scheduledDays: Int
    public let workedScheduledDays: Int

    public static func empty(error: String? = nil, grouping: JournalGrouping = .day) -> JournalReport {
        JournalReport(bounds: nil, error: error, grouping: grouping, days: [], buckets: [], rows: [],
                      focusedSeconds: 0, completedCycles: 0, partialSessions: 0, daysWithFocus: 0,
                      scheduledDays: 0, workedScheduledDays: 0)
    }

    public static func build(records: [SessionRecord], from: Date?, until: Date?, schedule: WorkSchedule,
                             grouping: JournalGrouping = .day,
                             calendar: ReportingCalendar = ReportingCalendar()) -> JournalReport {
        guard let from, let until else { return empty(error: rangeError, grouping: grouping) }
        let bounds = ReportBounds(from: from, until: until)
        guard from.timeIntervalSince1970.isFinite, until.timeIntervalSince1970.isFinite,
              bounds.duration > 0, bounds.duration <= maximumDuration else {
            return empty(error: rangeError, grouping: grouping)
        }
        let effectiveGrouping: JournalGrouping = bounds.duration > dailyGroupingLimit ? .week : grouping
        do {
            return try project(records: records, bounds: bounds, schedule: schedule,
                               grouping: effectiveGrouping, calendar: calendar)
        } catch {
            return empty(error: error.localizedDescription, grouping: effectiveGrouping)
        }
    }

    private static func project(records: [SessionRecord], bounds: ReportBounds, schedule: WorkSchedule,
                                grouping: JournalGrouping, calendar: ReportingCalendar) throws -> JournalReport {
        try schedule.validate()
        let cutoff = schedule.reportingDayStartMinutes
        var dayValues: [(key: CivilDate, start: Date, end: Date, scheduled: Bool)] = []
        var dayIndices: [CivilDate: Int] = [:]
        var key = try calendar.day(containing: bounds.from, cutoffMinutes: cutoff)
        var start = try calendar.date(at: key, cutoffMinutes: cutoff)
        while start < bounds.until {
            // The elapsed limit permits at most a few extra short local dates.
            try require(dayValues.count < 3_670, "The reporting calendar exceeds the supported range.")
            let next = try calendar.addingDays(1, to: key)
            let end = try calendar.date(at: next, cutoffMinutes: cutoff)
            try require(end > start, "Reporting boundaries must increase.")
            if end > bounds.from {
                dayIndices[key] = dayValues.count
                dayValues.append((key, start, end, try calendar.isScheduled(key, schedule: schedule)))
            }
            key = next; start = end
        }
        var seconds = Array(repeating: TimeInterval(0), count: dayValues.count)
        var cycles = Array(repeating: 0, count: dayValues.count)
        var rows: [JournalReportRow] = []
        var seenIDs = Set<UUID>()
        for record in records {
            // Persisted and live native records obey the same domain invariants;
            // never silently sanitize corruption as the browser preview does.
            try record.validate(allowLive: true)
            try require(seenIDs.insert(record.id).inserted, "The report contains a duplicate session identifier.")
            var focused: TimeInterval = 0
            for segment in record.segments {
                var cursor = max(bounds.from, segment.startedAt)
                let clippedEnd = min(bounds.until, segment.endedAt)
                if cursor >= clippedEnd { continue }
                focused += clippedEnd.timeIntervalSince(cursor)
                while cursor < clippedEnd {
                    let day = try calendar.day(containing: cursor, cutoffMinutes: cutoff)
                    guard let index = dayIndices[day] else {
                        throw ModelValidationError("Active time falls outside the reporting calendar.")
                    }
                    let end = min(clippedEnd, dayValues[index].end)
                    try require(end > cursor, "Active time cannot advance to the next reporting day.")
                    seconds[index] += end.timeIntervalSince(cursor)
                    cursor = end
                }
            }
            let completed = record.outcome == .complete && record.endedAt >= bounds.from && record.endedAt < bounds.until
            if completed {
                let day = try calendar.day(containing: record.endedAt, cutoffMinutes: cutoff)
                guard let index = dayIndices[day] else { throw ModelValidationError("The completion has no reporting date.") }
                cycles[index] += 1
            }
            if focused > 0 || completed {
                rows.append(JournalReportRow(record: record, focusedSeconds: focused,
                                             totalFocusedSeconds: record.focusedSeconds, completedInRange: completed))
            }
        }
        rows.sort {
            $0.record.startedAt == $1.record.startedAt
                ? $0.id.uuidString < $1.id.uuidString : $0.record.startedAt > $1.record.startedAt
        }
        let days = dayValues.enumerated().map { index, day in
            JournalReportDay(key: day.key, start: day.start, end: day.end, focusedSeconds: seconds[index],
                             completedCycles: cycles[index], isScheduled: day.scheduled)
        }
        var buckets: [JournalBucket] = []
        for day in days {
            let key = grouping == .week ? try calendar.week(containing: day.key, startsOn: schedule.weekStartsOn) : day.key
            let start = try calendar.date(at: key, cutoffMinutes: cutoff)
            let end = try calendar.date(at: calendar.addingDays(grouping == .week ? 7 : 1, to: key), cutoffMinutes: cutoff)
            if let previous = buckets.last, previous.key == key {
                buckets[buckets.count - 1] = JournalBucket(key: key, start: start, end: end,
                    focusedSeconds: previous.focusedSeconds + day.focusedSeconds,
                    completedCycles: previous.completedCycles + day.completedCycles,
                    scheduledDays: previous.scheduledDays + (day.isScheduled ? 1 : 0))
            } else {
                buckets.append(JournalBucket(key: key, start: start, end: end, focusedSeconds: day.focusedSeconds,
                    completedCycles: day.completedCycles, scheduledDays: day.isScheduled ? 1 : 0))
            }
        }
        return JournalReport(bounds: bounds, error: nil, grouping: grouping, days: days, buckets: buckets, rows: rows,
            focusedSeconds: rows.reduce(0) { $0 + $1.focusedSeconds }, completedCycles: cycles.reduce(0, +),
            partialSessions: rows.filter { $0.record.outcome == .partial && $0.focusedSeconds > 0 }.count,
            daysWithFocus: days.filter { $0.focusedSeconds > 0 }.count,
            scheduledDays: days.filter(\.isScheduled).count,
            workedScheduledDays: days.filter { $0.isScheduled && $0.focusedSeconds > 0 }.count)
    }
}

public enum JournalDuration {
    public static func format(seconds: TimeInterval, precise: Bool = false) -> String {
        guard seconds.isFinite, seconds >= 0, seconds < Double(Int.max) else { return precise ? "0s" : "0m" }
        let total = Int(seconds.rounded(.down))
        let hours = total / 3_600, minutes = total % 3_600 / 60, remainder = total % 60
        if precise {
            if hours > 0 { return "\(hours)h \(minutes)m" + (remainder > 0 ? " \(remainder)s" : "") }
            if minutes > 0 { return "\(minutes)m" + (remainder > 0 ? " \(remainder)s" : "") }
            return "\(remainder)s"
        }
        if hours > 0 { return "\(hours)h" + (minutes > 0 ? " \(minutes)m" : "") }
        if minutes > 0 { return "\(minutes)m" }
        return remainder > 0 ? "\(remainder)s" : "0m"
    }
}
