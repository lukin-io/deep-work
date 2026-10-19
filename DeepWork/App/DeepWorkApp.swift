import AppKit
import SwiftUI
import DeepWorkCore

/// The delegate owns one model and one window for the entire process lifetime.
@main
struct DeepWorkApplication {
    @MainActor static func main() {
        let application = NSApplication.shared
        let delegate = AppDelegate()
        application.setActivationPolicy(.regular)
        application.delegate = delegate
        withExtendedLifetime(delegate) { application.run() }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var model: AppModel!
    private var windowController: WindowController!
    private var menuBarController: MenuBarController!
    private var applicationMenuController: ApplicationMenuController!
    private var workspaceLifecycleController: WorkspaceLifecycleController!
    private var terminationPending = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        do {
#if DEBUG
            let options = DebugAcceptanceOptions()
            if let appearance = options.appearance { NSApp.appearance = NSAppearance(named: appearance) }
            model = try AppModel.live(feedbackClipboard: options.clipboard)
#else
            model = try AppModel.live()
#endif
        }
        catch {
            let alert = NSAlert()
            alert.messageText = "Deep Work is already open"
            alert.informativeText = "Another process owns this data folder. Use its window or quit it before opening another copy."
            alert.addButton(withTitle: "OK")
            alert.runModal()
            NSApp.terminate(nil)
            return
        }
        windowController = WindowController(model: model)
        menuBarController = MenuBarController(model: model, windowController: windowController)
        applicationMenuController = ApplicationMenuController(model: model, windowController: windowController)
        applicationMenuController.install()
        workspaceLifecycleController = WorkspaceLifecycleController(model: model)
        windowController.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        windowController.showWindow(nil)
        return true
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let model else { return .terminateNow }
        guard !terminationPending else { return .terminateLater }
        terminationPending = true
        Task { @MainActor in
            let saved = await model.prepareForTermination()
            var shouldQuit = saved
            if !saved {
                windowController.showWindow(nil)
                sender.activate(ignoringOtherApps: true)
                let alert = NSAlert()
                alert.alertStyle = .warning
                alert.messageText = "Changes could not be saved"
                let timerMessage = model.timer.isPaused ? "Your timer is paused. " : ""
                alert.informativeText = timerMessage + (model.lifecycleFailureMessage ?? "Keep Deep Work open to preserve changes that are still in memory.") + " Quitting without saving may lose those changes."
                alert.addButton(withTitle: "Keep Open")
                alert.addButton(withTitle: "Quit Without Saving")
                shouldQuit = alert.runModal() == .alertSecondButtonReturn
            }
            if !shouldQuit { model.keepOpenAfterCancelledQuit() }
            terminationPending = false
            sender.reply(toApplicationShouldTerminate: shouldQuit)
        }
        return .terminateLater
    }

    func applicationDidHide(_ notification: Notification) { model?.persistCommittedState() }
}
