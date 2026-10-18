import Foundation

public struct ActiveSegment: Codable, Equatable, Sendable {
    public var startedAt: Date
    public var endedAt: Date

    public init(startedAt: Date, endedAt: Date) {
        self.startedAt = startedAt
        self.endedAt = endedAt
    }
    public var duration: TimeInterval { endedAt.timeIntervalSince(startedAt) }
}

public enum SessionOutcome: String, Codable, Sendable { case complete, partial, live }

/// One focus cycle. Absolute timestamps and unrounded active segments are the
/// source data; pauses and breaks never become segments or separate records.
public struct SessionRecord: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var startedAt: Date
    public var endedAt: Date
    public var plannedFocusMinutes: Int
    public var outcome: SessionOutcome
    public var segments: [ActiveSegment]

    public init(id: UUID = UUID(), startedAt: Date, endedAt: Date,
                plannedFocusMinutes: Int, outcome: SessionOutcome, segments: [ActiveSegment]) {
        self.id = id
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.plannedFocusMinutes = plannedFocusMinutes
        self.outcome = outcome
        self.segments = segments
    }

    public var focusedSeconds: TimeInterval { segments.reduce(0) { $0 + $1.duration } }

    public func validate(allowLive: Bool = false) throws {
        try validateTimestamp(startedAt)
        try validateTimestamp(endedAt)
        try require(endedAt >= startedAt, "A session ends before it starts.")
        try require((1...480).contains(plannedFocusMinutes), "Planned focus minutes must be between 1 and 480.")
        try require(allowLive || outcome != .live, "Live observations belong only in an active checkpoint.")
        var previousEnd = startedAt
        for segment in segments {
            try validateTimestamp(segment.startedAt)
            try validateTimestamp(segment.endedAt)
            try require(segment.endedAt > segment.startedAt, "Active segments must have positive duration.")
            try require(segment.startedAt >= previousEnd && segment.endedAt <= endedAt,
                        "Active segments must be ordered, nonoverlapping, and inside their session.")
            previousEnd = segment.endedAt
        }
        let plannedSeconds = Double(plannedFocusMinutes) * 60
        try require(focusedSeconds.isFinite && focusedSeconds <= plannedSeconds + 0.001,
                    "Recorded focus exceeds its planned duration.")
        if outcome != .live {
            try require(focusedSeconds > 0, "Zero-time abandoned focus must not be saved.")
        }
        if outcome == .complete {
            try require(abs(focusedSeconds - plannedSeconds) <= 0.001,
                        "A completed focus must contain its entire planned active duration.")
        }
    }
}

public enum SessionPhase: String, Codable, Sendable { case focus, `break` }

/// A sealed snapshot only. No persisted deadline or open segment can count
/// process downtime. Recovery restores this snapshot paused before resuming.
public struct ActiveCheckpoint: Codable, Equatable, Sendable {
    public var phase: SessionPhase
    public var focusMinutes: Int
    public var breakMinutes: Int
    public var remainingSeconds: TimeInterval
    public var savedAt: Date
    public var focusRecord: SessionRecord?

    public init(phase: SessionPhase, focusMinutes: Int, breakMinutes: Int,
                remainingSeconds: TimeInterval, savedAt: Date, focusRecord: SessionRecord? = nil) {
        self.phase = phase
        self.focusMinutes = focusMinutes
        self.breakMinutes = breakMinutes
        self.remainingSeconds = remainingSeconds
        self.savedAt = savedAt
        self.focusRecord = focusRecord
    }

    public func validate() throws {
        try validateTimestamp(savedAt)
        try require((1...480).contains(focusMinutes) && (1...480).contains(breakMinutes),
                    "Checkpoint durations must be between 1 and 480 minutes.")
        let duration = Double(phase == .focus ? focusMinutes : breakMinutes) * 60
        try require(remainingSeconds.isFinite && remainingSeconds > 0 && remainingSeconds <= duration,
                    "Checkpoint remainder must be positive and no longer than its phase.")
        switch phase {
        case .focus:
            guard let record = focusRecord else { throw ModelValidationError("Focus checkpoints require a live record.") }
            try record.validate(allowLive: true)
            try require(record.outcome == .live && record.plannedFocusMinutes == focusMinutes,
                        "Checkpoint focus record must be live and match its duration.")
            try require(record.endedAt == savedAt, "The live observation must end at its checkpoint time.")
            try require(abs(record.focusedSeconds + remainingSeconds - duration) <= 0.001,
                        "Checkpoint active focus and remainder must equal the planned duration.")
        case .break:
            try require(focusRecord == nil, "Break checkpoints must not contain a live focus record.")
        }
    }
}
