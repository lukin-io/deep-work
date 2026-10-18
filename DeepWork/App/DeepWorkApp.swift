import AppKit
import SwiftUI

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
    private var statusItem: NSStatusItem!

    func applicationDidFinishLaunching(_ notification: Notification) {
        model = AppModel.live()
        windowController = WindowController(model: model)
        installMenus()
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.title = "Deep Work"
        statusItem.button?.toolTip = "Show Deep Work"
        statusItem.button?.setAccessibilityLabel("Show Deep Work window")
        statusItem.button?.target = self
        statusItem.button?.action = #selector(showFocus)
        windowController.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        windowController.showWindow(nil)
        return true
    }

    func applicationWillTerminate(_ notification: Notification) { model?.persistCommittedState() }

    @objc private func showFocus() {
        model.selectedTab = .focus
        windowController.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

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
