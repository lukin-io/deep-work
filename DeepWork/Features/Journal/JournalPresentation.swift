import AppKit
import DeepWorkCore

/// Shared display values for the native chart/table. Accounting remains in the
/// report engine; rounding belongs only at this presentation boundary.
enum JournalPresentation {
    static func date(_ date: Date, pattern: String, timeZone: TimeZone) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = timeZone
        formatter.dateFormat = pattern
        return formatter.string(from: date)
    }

    static func fullTimestamp(_ date: Date, timeZone: TimeZone) -> String {
        self.date(date, pattern: "EEEE, MMMM d, yyyy 'at' HH:mm:ss XXX", timeZone: timeZone)
    }

    static func barHeight(seconds: TimeInterval, maximum: TimeInterval) -> Double {
        guard seconds.isFinite, maximum.isFinite, seconds > 0, maximum > 0 else { return 3 }
        return max(3, min(105, seconds / maximum * 105))
    }

    static func bucketCaption(_ bucket: JournalBucket, grouping: JournalGrouping,
                              shortWeekdayLabels: Bool, timeZone: TimeZone) -> String {
        date(bucket.start, pattern: grouping == .day && shortWeekdayLabels ? "EEE" : "MMM d", timeZone: timeZone)
    }

    /// Native text metrics keep complete duration/date labels inside equal-width
    /// columns. Extra columns scroll instead of compressing essential values.
    @MainActor
    static func minimumChartColumnWidth(buckets: [JournalBucket], grouping: JournalGrouping,
                                        shortWeekdayLabels: Bool, timeZone: TimeZone) -> CGFloat {
        let durationFont = NSFont.monospacedDigitSystemFont(ofSize: 10, weight: .regular)
        let captionFont = NSFont.systemFont(ofSize: 10, weight: .semibold)
        return buckets.reduce(buckets.count > 14 ? 44 : 35) { width, bucket in
            let duration = JournalDuration.format(seconds: bucket.focusedSeconds, precise: false) as NSString
            let caption = bucketCaption(bucket, grouping: grouping, shortWeekdayLabels: shortWeekdayLabels,
                                        timeZone: timeZone) as NSString
            let textWidth = max(duration.size(withAttributes: [.font: durationFont]).width,
                                caption.size(withAttributes: [.font: captionFont]).width)
            return max(width, ceil(textWidth) + 4)
        }
    }

    static func bucketDescription(_ bucket: JournalBucket, grouping: JournalGrouping, timeZone: TimeZone) -> String {
        let date = self.date(bucket.start, pattern: "EEEE, MMMM d, yyyy", timeZone: timeZone)
        let context = grouping == .week ? "Week of \(date)" : date
        let duration = JournalDuration.format(seconds: bucket.focusedSeconds, precise: true)
        let cycles = "\(bucket.completedCycles) completed \(bucket.completedCycles == 1 ? "cycle" : "cycles")"
        let offDay = grouping == .day && bucket.scheduledDays == 0 ? ", day off" : ""
        let action = grouping == .day ? "Open day report" : "Open week report"
        return "\(context): \(duration), \(cycles)\(offDay). \(action)."
    }
}

struct JournalRowPresentation: Equatable, Identifiable {
    let id: UUID
    let startedDate: String
    let startedTime: String
    let startedHelp: String
    let endedDate: String
    let endedTime: String
    let endedHelp: String
    let focus: String
    let focusDetail: String
    let cycle: String
    let cycleDetail: String
    let isLive: Bool
    let isPartial: Bool

    init(row: JournalReportRow, paused: Bool, timeZone: TimeZone) {
        let record = row.record
        id = record.id
        startedDate = JournalPresentation.date(record.startedAt, pattern: "MMM d", timeZone: timeZone)
        startedTime = JournalPresentation.date(record.startedAt, pattern: "HH:mm", timeZone: timeZone)
        startedHelp = JournalPresentation.fullTimestamp(record.startedAt, timeZone: timeZone)
        isLive = record.outcome == .live
        isPartial = record.outcome == .partial
        endedDate = isLive ? (paused ? "Paused" : "In progress") : JournalPresentation.date(record.endedAt, pattern: "MMM d", timeZone: timeZone)
        endedTime = isLive ? "Current session" : JournalPresentation.date(record.endedAt, pattern: "HH:mm", timeZone: timeZone)
        endedHelp = (isLive ? "Observed " : "") + JournalPresentation.fullTimestamp(record.endedAt, timeZone: timeZone)
        focus = JournalDuration.format(seconds: row.focusedSeconds, precise: true)
        focusDetail = row.focusedSeconds < row.totalFocusedSeconds
            ? "\(JournalDuration.format(seconds: row.totalFocusedSeconds, precise: true)) total"
            : "\(JournalDuration.format(seconds: Double(record.plannedFocusMinutes) * 60)) planned"
        switch record.outcome {
        case .complete: cycle = "Complete"
        case .partial: cycle = "Partial"
        case .live: cycle = paused ? "Paused" : "Live"
        }
        cycleDetail = record.outcome == .complete && !row.completedInRange ? "Outside range" : ""
    }
}
