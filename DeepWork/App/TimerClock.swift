import Foundation
import DeepWorkCore

/// Process-local elapsed time. Persist sealed checkpoints, never clock instants.
@MainActor
protocol TimerClock {
    func now() -> TimerInstant
}

@MainActor
struct ContinuousTimerClock: TimerClock {
    private let clock = ContinuousClock()
    private let origin = ContinuousClock.now

    func now() -> TimerInstant {
        let duration = origin.duration(to: clock.now).components
        return TimerInstant(elapsed: Double(duration.seconds) + Double(duration.attoseconds) / 1e18,
                            wallDate: Date())
    }
}
