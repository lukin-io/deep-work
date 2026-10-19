import Foundation

/// Captured before presenting the save panel. A slow destination choice must not
/// change the exported rows, schedule, zone or observation time underneath it.
public struct ReportExportSnapshot: Equatable, Sendable {
    public let rows: [JournalReportRow]
    public let bounds: ReportBounds?
    public let isExample: Bool
    public let schedule: WorkSchedule
    public let scheduleSummary: String
    public let timeZone: TimeZone
    public let filename: String

    public var canExport: Bool { !rows.isEmpty }
    public var focusedSeconds: TimeInterval { rows.reduce(0) { $0 + $1.focusedSeconds } }

    private init(rows: [JournalReportRow], bounds: ReportBounds?, isExample: Bool,
                 schedule: WorkSchedule, scheduleSummary: String, timeZone: TimeZone,
                 filename: String) {
        self.rows = rows; self.bounds = bounds; self.isExample = isExample
        self.schedule = schedule; self.scheduleSummary = scheduleSummary
        // Resolve an autoupdating zone too, so this remains an immutable export.
        self.timeZone = TimeZone(identifier: timeZone.identifier) ?? timeZone
        self.filename = filename
    }

    public static func currentReport(_ report: JournalReport, isExample: Bool,
                                     schedule: WorkSchedule, scheduleSummary: String,
                                     timeZone: TimeZone) throws -> ReportExportSnapshot {
        if let error = report.error { throw ModelValidationError(error) }
        guard let bounds = report.bounds else { throw ModelValidationError(JournalReport.rangeError) }
        try schedule.validate()
        let from = CivilDate(bounds.from, timeZone: timeZone).iso8601Date
        let until = CivilDate(bounds.until, timeZone: timeZone).iso8601Date
        return ReportExportSnapshot(rows: report.rows, bounds: bounds, isExample: isExample,
            schedule: schedule, scheduleSummary: scheduleSummary, timeZone: timeZone,
            filename: "deep-work-\(isExample ? "example-" : "")\(from)-to-\(until).csv")
    }

    /// The owner supplies only actual history and its current live observation.
    /// No report-range limit, grouping or table pagination applies to history.
    public static func allSessions(actualRecords: [SessionRecord], schedule: WorkSchedule,
                                   scheduleSummary: String, timeZone: TimeZone) throws -> ReportExportSnapshot {
        try schedule.validate()
        var rows: [JournalReportRow] = []
        var seenIDs = Set<UUID>()
        for record in actualRecords {
            try record.validate(allowLive: true)
            try require(seenIDs.insert(record.id).inserted, "The export contains a duplicate session identifier.")
            let seconds = record.focusedSeconds
            let complete = record.outcome == .complete
            if seconds > 0 || complete {
                rows.append(JournalReportRow(record: record, focusedSeconds: seconds,
                    totalFocusedSeconds: seconds, completedInRange: complete))
            }
        }
        rows.sort {
            $0.record.startedAt == $1.record.startedAt
                ? $0.id.uuidString < $1.id.uuidString : $0.record.startedAt > $1.record.startedAt
        }
        return ReportExportSnapshot(rows: rows, bounds: nil, isExample: false, schedule: schedule,
            scheduleSummary: scheduleSummary, timeZone: timeZone,
            filename: "deep-work-journal-all-sessions.csv")
    }
}

/// The shared byte contract for Journal and Settings. File selection and writing
/// belong to the native service; this pure serializer never changes app state.
public enum ReportCSVExporter {
    public static let columns = [
        "Data", "Report from", "Report until (exclusive)", "Reporting day starts", "Schedule",
        "Session ID", "Started", "Ended / observed at", "Outcome", "Planned minutes",
        "Focus seconds in range", "Total focus seconds", "Completed cycle in range"
    ]

    public static func data(for snapshot: ReportExportSnapshot) throws -> Data {
        try require(snapshot.canExport, "There are no focus sessions to export.")
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = snapshot.timeZone
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = calendar
        formatter.timeZone = snapshot.timeZone
        // Lowercase xxx retains a numeric +00:00 offset instead of Z at UTC.
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ssxxx"
        let from = try snapshot.bounds.map { try timestamp($0.from, formatter: formatter, calendar: calendar) } ?? ""
        let until = try snapshot.bounds.map { try timestamp($0.until, formatter: formatter, calendar: calendar) } ?? ""
        let cutoff = snapshot.schedule.reportingDayStartMinutes
        let cutoffText = String(format: "%02d:%02d", cutoff / 60, cutoff % 60)
        var lines = [columns.map(quote).joined(separator: ",")]
        lines.reserveCapacity(snapshot.rows.count + 1)
        for row in snapshot.rows {
            let record = row.record
            let cells = [snapshot.isExample ? "Example" : "Journal", from, until, cutoffText,
                snapshot.scheduleSummary, record.id.uuidString,
                try timestamp(record.startedAt, formatter: formatter, calendar: calendar),
                try timestamp(record.endedAt, formatter: formatter, calendar: calendar),
                record.outcome.rawValue, String(record.plannedFocusMinutes),
                seconds(row.focusedSeconds), seconds(row.totalFocusedSeconds), row.completedInRange ? "1" : "0"]
            lines.append(cells.map(quote).joined(separator: ","))
        }
        // Match the approved reference: separators are CRLF, without an extra
        // empty record at the end. Embedded newlines remain inside quoted cells.
        return Data(("\u{FEFF}" + lines.joined(separator: "\r\n")).utf8)
    }

    private static func quote(_ text: String) -> String {
        "\"" + text.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }

    private static func seconds(_ value: TimeInterval) -> String {
        // Positive half-thousandths round up, as in the reference's toFixed(3),
        // rather than printf's ties-to-even (0.0625 must become 0.063).
        let rounded = (value * 1_000).rounded(.toNearestOrAwayFromZero) / 1_000
        var result = String(format: "%.3f", locale: Locale(identifier: "en_US_POSIX"), rounded)
        while result.last == "0" { result.removeLast() }
        if result.last == "." { result.removeLast() }
        return result
    }

    private static func timestamp(_ date: Date, formatter: DateFormatter, calendar: Calendar) throws -> String {
        try validateTimestamp(date)
        let year = calendar.component(.year, from: date)
        try require(calendar.component(.era, from: date) == 1 && (1...9999).contains(year),
                    "An export timestamp is outside the supported Gregorian calendar.")
        return formatter.string(from: date)
    }
}
