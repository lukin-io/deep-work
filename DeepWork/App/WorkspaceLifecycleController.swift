import AppKit

/// Observes process-lifetime workspace events independently of window lifetime.
/// Sleep seals a checkpoint without pausing; wake reconciles continuous elapsed
/// time. Persistence stays asynchronous and does not hold up system sleep.
@MainActor
final class WorkspaceLifecycleController: NSObject {
    private weak var model: AppModel?

    init(model: AppModel, notificationCenter: NotificationCenter? = nil) {
        self.model = model
        super.init()
        let center = notificationCenter ?? NSWorkspace.shared.notificationCenter
        center.addObserver(self, selector: #selector(willSleep(_:)),
                           name: NSWorkspace.willSleepNotification, object: nil)
        center.addObserver(self, selector: #selector(didWake(_:)),
                           name: NSWorkspace.didWakeNotification, object: nil)
        // Selector observations use weak storage on supported macOS versions;
        // NotificationCenter removes them after this controller is released.
    }

    @objc nonisolated private func willSleep(_ notification: Notification) {
        onMainActor { $0.persistCommittedState() }
    }

    @objc nonisolated private func didWake(_ notification: Notification) {
        onMainActor { $0.refreshTimer() }
    }

    nonisolated private func onMainActor(_ action: @escaping @MainActor @Sendable (AppModel) -> Void) {
        if Thread.isMainThread {
            // Preserve the checkpoint snapshot during normal main-thread
            // delivery, before the system proceeds into sleep.
            MainActor.assumeIsolated {
                if let model { action(model) }
            }
        } else {
            Task { @MainActor [weak self] in
                if let model = self?.model { action(model) }
            }
        }
    }
}
