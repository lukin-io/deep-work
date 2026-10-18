import Foundation

/// An elapsed-clock reading paired with a civil timestamp. Only `elapsed` drives
/// accounting. The application supplies ContinuousClock readings so background
/// execution and sleep follow the same boundary rules as ordinary elapsed time.
public struct TimerInstant: Equatable, Sendable {
    public let elapsed: TimeInterval
    public let wallDate: Date

    public init(elapsed: TimeInterval, wallDate: Date) {
        self.elapsed = elapsed
        self.wallDate = wallDate
    }
}

public enum TimerState: Equatable, Sendable {
    case setup, focus, `break`, complete
}

/// A deterministic phase machine, independent of views, refresh cadence and I/O.
/// Mutations return only newly finalized records. The application commits those
/// records together with `activeCheckpoint` in one journal transaction.
public struct TimerEngine: Sendable {
    public private(set) var state: TimerState = .setup
    public private(set) var isPaused = false
    public private(set) var isRecovered = false
    public private(set) var repeats: Bool
    public private(set) var phaseID: UUID?
    public private(set) var focusMinutes: Int?
    public private(set) var breakMinutes: Int?
    public private(set) var remainingSeconds: TimeInterval = 0

    private var deadline: TimeInterval?
    private var currentRecord: SessionRecord?
    private var openSegmentStart: TimeInterval?
    private var anchorElapsed: TimeInterval = 0
    private var anchorDate = Date(timeIntervalSince1970: 0)
    private var observedElapsed: TimeInterval = 0

    public init(repeats: Bool = true) {
        self.repeats = repeats
    }

    /// No persisted deadline is resumed. Process downtime is absent from active
    /// segments; the recovered remainder requires an explicit Resume action.
    public init(checkpoint: ActiveCheckpoint, repeats: Bool, at instant: TimerInstant) throws {
        try checkpoint.validate()
        try Self.validate(instant)
        self.init(repeats: repeats)
        focusMinutes = checkpoint.focusMinutes
        breakMinutes = checkpoint.breakMinutes
        state = checkpoint.phase == .focus ? .focus : .break
        phaseID = UUID()
        isPaused = true
        isRecovered = true
        remainingSeconds = checkpoint.remainingSeconds
        currentRecord = checkpoint.focusRecord
        anchorElapsed = instant.elapsed
        observedElapsed = instant.elapsed
        // A backwards civil-clock adjustment must never create overlapping or
        // negative segments when an older checkpoint is resumed.
        anchorDate = max(instant.wallDate, checkpoint.savedAt)
    }

    public var isActive: Bool { state == .focus || state == .break }

    public var progressFraction: Double {
        if state == .complete { return 1 }
        guard let duration = phaseDuration, duration > 0 else { return 0 }
        return min(1, max(0, 1 - remainingSeconds / duration))
    }

    public var countdownText: String {
        let seconds = Int(ceil(max(0, remainingSeconds)))
        return String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }

    public var phaseTitle: String {
        switch state {
        case .setup: return "Set your rhythm."
        case .focus: return isPaused ? "Deep work paused" : "Deep work"
        case .break: return isPaused ? "Break paused" : "Take a break"
        case .complete: return "Cycle complete"
        }
    }

    public var caption: String {
        if state == .complete { return "Saved to your journal." }
        if isPaused { return "Paused time is excluded from your journal." }
        switch state {
        case .focus: return "\(breakMinutes ?? 0)-minute break next"
        case .break: return repeats ? "\(focusMinutes ?? 0)-minute deep work next" : "Your final break."
        case .setup, .complete: return ""
        }
    }

    public var repeatExplanation: String {
        if state == .complete {
            return repeats ? "Your next session will repeat." : "Session complete. Repeat is off."
        }
        if repeats { return "Deep work, then break. Repeat until unchecked." }
        switch state {
        case .setup: return "One deep work cycle and one break, then stop."
        case .focus: return "Stops after your upcoming break."
        case .break: return "Stops after this break."
        case .complete: return "Session complete. Repeat is off."
        }
    }

    public var nextActionTitle: String? {
        switch state {
        case .focus: return "Take break"
        case .break: return repeats ? "Skip break" : "Finish break"
        case .setup, .complete: return nil
        }
    }

    public var primaryActionTitle: String {
        if state == .setup { return "Start deep work" }
        if state == .complete { return "Start again" }
        return isPaused ? "Resume" : "Pause"
    }

    public var menuBarTitle: String {
        switch state {
        case .focus: return "\(countdownText) - deep"
        case .break: return "\(countdownText) - break"
        case .setup, .complete: return "Deep Work"
        }
    }

    /// A sealed projection at the last reconciled instant. Reading this does not
    /// split the running segment, finalize a record or mutate the engine.
    public var liveRecord: SessionRecord? {
        guard state == .focus, var record = currentRecord else { return nil }
        let observation = logicalDate(at: observedElapsed)
        if let segmentStart = openSegmentStart {
            let startedAt = logicalDate(at: segmentStart)
            if observation > startedAt {
                record.segments.append(ActiveSegment(startedAt: startedAt, endedAt: observation))
            }
        }
        record.endedAt = observation
        return record
    }

    public var activeCheckpoint: ActiveCheckpoint? {
        guard isActive, let focusMinutes, let breakMinutes, remainingSeconds > 0 else { return nil }
        return ActiveCheckpoint(phase: state == .focus ? .focus : .break,
                                focusMinutes: focusMinutes, breakMinutes: breakMinutes,
                                remainingSeconds: remainingSeconds,
                                savedAt: logicalDate(at: observedElapsed), focusRecord: liveRecord)
    }

    @discardableResult
    public mutating func start(configuration: FocusConfiguration, at instant: TimerInstant) throws -> [SessionRecord] {
        try configuration.validate()
        try Self.validate(instant)
        guard let focus = configuration.resolvedFocusMinutes,
              let rest = configuration.resolvedBreakMinutes else {
            throw ModelValidationError("Choose both durations to begin.")
        }
        guard state == .setup else { return [] }
        focusMinutes = focus
        breakMinutes = rest
        repeats = configuration.repeats
        resetTimeline(at: instant)
        beginFocus(at: instant.elapsed)
        return []
    }

    /// Walk every crossed boundary at its exact deadline. Repeated calls at the
    /// same instant are idempotent and never count a break as focused time.
    @discardableResult
    public mutating func reconcile(at instant: TimerInstant) -> [SessionRecord] {
        guard Self.isValid(instant) else { return [] }
        observedElapsed = max(observedElapsed, instant.elapsed)
        guard isActive, !isPaused else { return [] }
        var records: [SessionRecord] = []
        while isActive, let boundary = deadline, boundary <= observedElapsed {
            switch state {
            case .focus:
                if let record = finalizeFocus(outcome: .complete, at: boundary) { records.append(record) }
                beginBreak(at: boundary)
            case .break:
                if repeats { beginFocus(at: boundary) } else { finishPair() }
            case .setup, .complete:
                break
            }
        }
        if let deadline, isActive { remainingSeconds = max(0, deadline - observedElapsed) }
        return records
    }

    @discardableResult
    public mutating func pause(at instant: TimerInstant) -> [SessionRecord] {
        let records = reconcile(at: instant)
        guard isActive, !isPaused else { return records }
        sealSegment(at: observedElapsed)
        deadline = nil
        isPaused = true
        return records
    }

    @discardableResult
    public mutating func resume(at instant: TimerInstant) -> [SessionRecord] {
        let records = reconcile(at: instant)
        guard isActive, isPaused, Self.isValid(instant) else { return records }
        // Re-anchor only on recovered Resume. Its first segment uses the current
        // civil time while retaining all original pre-quit timestamps.
        if isRecovered {
            anchorDate = max(logicalDate(at: observedElapsed), instant.wallDate)
            anchorElapsed = observedElapsed
        }
        deadline = observedElapsed + remainingSeconds
        isPaused = false
        isRecovered = false
        if state == .focus { openSegmentStart = observedElapsed }
        return records
    }

    /// The rendered phase identity must still match after reconciliation. This
    /// deliberately tightens the preview's phase-name-only guard: a delayed
    /// click cannot prematurely end a later cycle with the same phase name.
    @discardableResult
    public mutating func advance(expectedPhaseID: UUID, at instant: TimerInstant) -> [SessionRecord] {
        var records = reconcile(at: instant)
        guard isActive, phaseID == expectedPhaseID else { return records }
        switch state {
        case .focus:
            if let record = finalizeFocus(outcome: .partial, at: observedElapsed) { records.append(record) }
            beginBreak(at: observedElapsed)
        case .break:
            if repeats { beginFocus(at: observedElapsed) } else { finishPair() }
        case .setup, .complete:
            break
        }
        return records
    }

    @discardableResult
    public mutating func end(at instant: TimerInstant) -> [SessionRecord] {
        var records = reconcile(at: instant)
        if state == .focus,
           let record = finalizeFocus(outcome: .partial, at: observedElapsed) { records.append(record) }
        state = .setup
        isPaused = false
        isRecovered = false
        phaseID = nil
        remainingSeconds = 0
        deadline = nil
        currentRecord = nil
        openSegmentStart = nil
        return records
    }

    @discardableResult
    public mutating func restart(at instant: TimerInstant) -> [SessionRecord] {
        let records = reconcile(at: instant)
        guard state == .complete, Self.isValid(instant) else { return records }
        resetTimeline(at: instant)
        beginFocus(at: observedElapsed)
        return records
    }

    @discardableResult
    public mutating func setRepeating(_ value: Bool, at instant: TimerInstant) -> [SessionRecord] {
        let records = reconcile(at: instant)
        repeats = value
        return records
    }

    private var phaseDuration: TimeInterval? {
        switch state {
        case .focus: return focusMinutes.map { Double($0) * 60 }
        case .break: return breakMinutes.map { Double($0) * 60 }
        case .setup, .complete: return nil
        }
    }

    private mutating func resetTimeline(at instant: TimerInstant) {
        anchorElapsed = instant.elapsed
        observedElapsed = instant.elapsed
        anchorDate = instant.wallDate
    }

    private func logicalDate(at elapsed: TimeInterval) -> Date {
        anchorDate.addingTimeInterval(elapsed - anchorElapsed)
    }

    private mutating func beginFocus(at elapsed: TimeInterval) {
        guard let focusMinutes else { return }
        state = .focus
        isPaused = false
        isRecovered = false
        phaseID = UUID()
        remainingSeconds = Double(focusMinutes) * 60
        deadline = elapsed + remainingSeconds
        let startedAt = logicalDate(at: elapsed)
        currentRecord = SessionRecord(startedAt: startedAt, endedAt: startedAt,
                                      plannedFocusMinutes: focusMinutes, outcome: .live, segments: [])
        openSegmentStart = elapsed
    }

    private mutating func beginBreak(at elapsed: TimeInterval) {
        guard let breakMinutes else { return }
        state = .break
        isPaused = false
        isRecovered = false
        phaseID = UUID()
        remainingSeconds = Double(breakMinutes) * 60
        deadline = elapsed + remainingSeconds
        currentRecord = nil
        openSegmentStart = nil
    }

    private mutating func finishPair() {
        state = .complete
        isPaused = false
        isRecovered = false
        phaseID = nil
        remainingSeconds = 0
        deadline = nil
        currentRecord = nil
        openSegmentStart = nil
    }

    private mutating func sealSegment(at elapsed: TimeInterval) {
        guard var record = currentRecord else { return }
        let endedAt = logicalDate(at: elapsed)
        if let openSegmentStart {
            let startedAt = logicalDate(at: openSegmentStart)
            if endedAt > startedAt {
                record.segments.append(ActiveSegment(startedAt: startedAt, endedAt: endedAt))
            }
        }
        record.endedAt = endedAt
        currentRecord = record
        openSegmentStart = nil
    }

    private mutating func finalizeFocus(outcome: SessionOutcome, at elapsed: TimeInterval) -> SessionRecord? {
        sealSegment(at: elapsed)
        defer { currentRecord = nil }
        guard var record = currentRecord, record.focusedSeconds > 0 else { return nil }
        record.outcome = outcome
        return record
    }

    private static func isValid(_ instant: TimerInstant) -> Bool {
        instant.elapsed.isFinite && instant.wallDate.timeIntervalSince1970.isFinite &&
            abs(instant.wallDate.timeIntervalSince1970) < 8_640_000_000_000
    }

    private static func validate(_ instant: TimerInstant) throws {
        try require(isValid(instant), "The timer clock reading is invalid.")
    }
}
