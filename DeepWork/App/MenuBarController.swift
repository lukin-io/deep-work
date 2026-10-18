import AppKit
import Combine
import DeepWorkCore

/// Projects the app's existing timer into one retained native status item.
/// Clicking it reopens Focus through the same model and window controller.
@MainActor
final class MenuBarController: NSObject {
    private let model: AppModel
    private let windowController: WindowController
    private let activateApplication: @MainActor () -> Void
    // AppKit removes the item when its last strong reference is released.
    // AppDelegate retains this controller for the application's lifetime.
    private let statusItem: NSStatusItem
    private var timerProjection: AnyCancellable?

    var button: NSStatusBarButton? { statusItem.button }

    init(model: AppModel, windowController: WindowController,
         activateApplication: @escaping @MainActor () -> Void = { NSApp.activate(ignoringOtherApps: true) }) {
        self.model = model
        self.windowController = windowController
        self.activateApplication = activateApplication
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()
        button?.font = .monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
        button?.toolTip = "Show Deep Work"
        button?.target = self
        button?.action = #selector(showFocus)
        // Use the emitted value: @Published publishes before the model's stored
        // property changes. Reading model.timer here could lag one transition.
        timerProjection = model.$timer.sink { [weak self] timer in self?.update(timer) }
    }

    @objc func showFocus() {
        guard !model.isTerminating else { return }
        model.showFocus()
        windowController.showWindow(nil)
        activateApplication()
    }

    private func update(_ timer: TimerEngine) {
        button?.title = timer.menuBarTitle
        button?.image = NSImage(systemSymbolName: timer.isPaused ? "pause.fill" : "timer",
                               accessibilityDescription: timer.isPaused ? "Paused" : "Timer")
        button?.image?.isTemplate = true
        button?.imagePosition = .imageLeading
        let state = timer.isPaused ? "Paused" : timer.phaseTitle
        button?.setAccessibilityLabel("\(state), \(timer.menuBarTitle). Show Deep Work window")
    }
}
