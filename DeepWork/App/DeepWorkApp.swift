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
    private var terminationPending = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        do { model = try AppModel.live() }
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
        installMenus()
        let workspace = NSWorkspace.shared.notificationCenter
        workspace.addObserver(self, selector: #selector(willSleep), name: NSWorkspace.willSleepNotification, object: nil)
        workspace.addObserver(self, selector: #selector(didWake), name: NSWorkspace.didWakeNotification, object: nil)
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
            await model.prepareForTermination()
            sender.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }

    func applicationDidHide(_ notification: Notification) { model?.persistCommittedState() }
    @objc private func willSleep() { model?.persistCommittedState() }
    @objc private func didWake() { model?.refreshTimer() }

    @objc private func showFocus() { menuBarController.showFocus() }

    private func installMenus() {
        let menu = NSMenu()
        let app = NSMenuItem(); menu.addItem(app)
        let appMenu = NSMenu(title: "Deep Work"); app.submenu = appMenu
        appMenu.addItem(withTitle: "About Deep Work", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Hide Deep Work", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Quit Deep Work", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        let file = NSMenuItem(); menu.addItem(file)
        file.submenu = NSMenu(title: "File")
        let show = file.submenu!.addItem(withTitle: "Show Deep Work", action: #selector(showFocus), keyEquivalent: "0")
        show.target = self
        file.submenu!.addItem(withTitle: "Close Window", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        let edit = NSMenuItem(); menu.addItem(edit)
        edit.submenu = NSMenu(title: "Edit")
        edit.submenu!.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        edit.submenu!.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.submenu!.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.submenu!.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.submenu!.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        let window = NSMenuItem(); menu.addItem(window)
        let windowMenu = NSMenu(title: "Window"); window.submenu = windowMenu
        windowMenu.addItem(withTitle: "Minimize", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        windowMenu.addItem(withTitle: "Zoom", action: #selector(NSWindow.performZoom(_:)), keyEquivalent: "")
        let fullScreen = windowMenu.addItem(withTitle: "Toggle Full Screen", action: #selector(NSWindow.toggleFullScreen(_:)), keyEquivalent: "f")
        fullScreen.keyEquivalentModifierMask = [.control, .command]
        NSApp.windowsMenu = windowMenu
        NSApp.mainMenu = menu
    }
}
