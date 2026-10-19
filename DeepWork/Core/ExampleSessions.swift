import Foundation

/// Ephemeral examples use the same validated native record schema. They are
/// generated once per app launch, held separately and never written to SQLite.
public enum ExampleSessions {
    public static func generate(now: Date, calendar: ReportingCalendar = ReportingCalendar()) throws -> [SessionRecord] {
        try validateTimestamp(now)
        let today = try calendar.day(containing: now)
        var result: [SessionRecord] = []
        for offset in -34...0 {
            let date = try calendar.addingDays(offset, to: today)
            let weekday = try calendar.weekday(of: date)
            let count: Int
            switch weekday {
            case .monday, .thursday: count = 3
            case .tuesday, .friday: count = 2
            case .wednesday: count = 4
            case .saturday: count = 1
            case .sunday: count = 0
            }
            var next = try calendar.date(at: date, cutoffMinutes: 9 * 60 + 10)
            for index in 0..<count {
                let plannedMinutes = index % 2 == 0 ? 60 : 90
                let partial = (weekday == .tuesday && index == count - 1) || weekday == .saturday
                let actual: TimeInterval = Double(partial ? (weekday == .saturday ? 35 : 25) : plannedMinutes) * 60
                let pause: TimeInterval = index == 1 ? 10 * 60 : 0
                let end = next.addingTimeInterval(actual + pause)
                if end <= now {
                    let segments: [ActiveSegment]
                    if pause > 0 {
                        segments = [ActiveSegment(startedAt: next, endedAt: next.addingTimeInterval(actual / 2)),
                                    ActiveSegment(startedAt: next.addingTimeInterval(actual / 2 + pause), endedAt: end)]
                    } else { segments = [ActiveSegment(startedAt: next, endedAt: end)] }
                    let record = SessionRecord(id: identifier(date: date, index: index), startedAt: next, endedAt: end,
                        plannedFocusMinutes: plannedMinutes, outcome: partial ? .partial : .complete, segments: segments)
                    try record.validate()
                    result.append(record)
                }
                next = end.addingTimeInterval(20 * 60)
            }
        }
        return result
    }

    // Stable UUIDs retain native Identifiable semantics without random IDs on
    // redraw. The fixed prefix distinguishes generated fixture identity.
    private static func identifier(date: CivilDate, index: Int) -> UUID {
        UUID(uuid: (0x45, 0x58, 0x41, 0x4D, 0x50, 0x4C, 0x45, 0x53,
                    0, 0, UInt8(date.year / 256), UInt8(date.year % 256),
                    UInt8(date.month), UInt8(date.day), 0, UInt8(index)))
    }
}
