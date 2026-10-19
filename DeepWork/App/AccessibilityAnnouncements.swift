import AppKit
import DeepWorkCore

@MainActor
protocol AccessibilityAnnouncing {
    func announce(_ message: String, priority: NSAccessibilityPriorityLevel)
}

/// AppKit requires announcementRequested on the application element, not the
/// key window. This also works when the retained content window is hidden.
@MainActor
struct NativeAccessibilityAnnouncer: AccessibilityAnnouncing {
    typealias Posting = @MainActor (NSApplication, NSAccessibility.Notification,
                                    [NSAccessibility.NotificationUserInfoKey: Any]) -> Void

    private let application: @MainActor () -> NSApplication?
    private let post: Posting

    init(application: @escaping @MainActor () -> NSApplication? = { NSApp },
         post: @escaping Posting = { application, notification, information in
             NSAccessibility.post(element: application, notification: notification, userInfo: information)
         }) {
        self.application = application
        self.post = post
    }

    func announce(_ message: String, priority: NSAccessibilityPriorityLevel) {
        guard !message.isEmpty, let application = application() else { return }
        post(application, .announcementRequested, [
            .announcement: message, .priority: priority.rawValue
        ])
    }
}

/// Deliberately excludes countdown/progress. Only semantic state changes may
/// produce speech; delayed catch-up describes the final state once.
struct TimerAnnouncementState: Equatable {
    let state: TimerState
    let paused: Bool
    let phaseID: UUID?
    let repeats: Bool

    init(_ timer: TimerEngine) {
        state = timer.state
        paused = timer.isPaused
        phaseID = timer.phaseID
        repeats = timer.repeats
    }

    func message(after previous: Self, completedCycles: Int, repeatExplanation: String) -> String? {
        guard self != previous else { return nil }
        var messages: [String] = []
        if completedCycles > 0 {
            messages.append(completedCycles == 1 ? "One focus cycle completed." : "\(completedCycles) focus cycles completed.")
        }
        if state != previous.state || paused != previous.paused || phaseID != previous.phaseID {
            switch state {
            case .setup: messages.append("Session ended. Your duration choices are ready.")
            case .complete: messages.append("Cycle complete.")
            case .focus, .break:
                let phase = state == .focus ? "Deep work" : "Break"
                let action = paused ? "paused" : (previous.paused && phaseID == previous.phaseID ? "resumed" : "started")
                messages.append("\(phase) \(action).")
            }
        }
        if repeats != previous.repeats { messages.append("Repeat cycles \(repeats ? "on" : "off"). \(repeatExplanation)") }
        return messages.isEmpty ? nil : messages.joined(separator: " ")
    }
}
