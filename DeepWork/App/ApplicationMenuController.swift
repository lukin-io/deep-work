import AppKit

/// Native commands operate on the retained app model/window. Standard editing
/// and window commands keep a nil target so AppKit resolves the responder chain.
@MainActor
final class ApplicationMenuController: NSObject, NSMenuItemValidation {
    let menu = NSMenu()
    private let windowMenu = NSMenu(title: "Window")
    private let servicesMenu = NSMenu(title: "Services")
    private let model: AppModel
    private let windowController: WindowController
    private let activateApplication: @MainActor () -> Void

    init(model: AppModel, windowController: WindowController,
         activateApplication: @escaping @MainActor () -> Void = { NSApp.activate(ignoringOtherApps: true) }) {
        self.model = model
        self.windowController = windowController
        self.activateApplication = activateApplication
        super.init()
        buildMenus()
    }

    func install() {
        let application = NSApplication.shared
        application.servicesMenu = servicesMenu
        application.windowsMenu = windowMenu
        application.mainMenu = menu
    }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool { !model.isTerminating }

    @objc private func showSettings(_ sender: Any?) {
        guard !model.isTerminating else { return }
        model.refreshTimer()
        model.selectedTab = .settings
        showWindow(sender)
    }

    @objc private func showFocus(_ sender: Any?) {
        guard !model.isTerminating else { return }
        model.showFocus()
        showWindow(sender)
    }

    private func showWindow(_ sender: Any?) {
        windowController.showWindow(sender)
        activateApplication()
    }

    private func buildMenus() {
        let appMenu = addMenu(title: "Deep Work")
        appMenu.addItem(withTitle: "About Deep Work", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        let settings = appMenu.addItem(withTitle: "Settings…", action: #selector(showSettings(_:)), keyEquivalent: ",")
        settings.target = self
        appMenu.addItem(.separator())
        let services = appMenu.addItem(withTitle: "Services", action: nil, keyEquivalent: "")
        services.submenu = servicesMenu
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Hide Deep Work", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        let hideOthers = appMenu.addItem(withTitle: "Hide Others", action: #selector(NSApplication.hideOtherApplications(_:)), keyEquivalent: "h")
        hideOthers.keyEquivalentModifierMask = [.option, .command]
        appMenu.addItem(withTitle: "Show All", action: #selector(NSApplication.unhideAllApplications(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Quit Deep Work", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")

        let fileMenu = addMenu(title: "File")
        let show = fileMenu.addItem(withTitle: "Show Deep Work", action: #selector(showFocus(_:)), keyEquivalent: "0")
        show.target = self
        fileMenu.addItem(withTitle: "Close Window", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")

        let editMenu = addMenu(title: "Edit")
        editMenu.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        let redo = editMenu.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "z")
        redo.keyEquivalentModifierMask = [.shift, .command]
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")

        let window = menu.addItem(withTitle: "Window", action: nil, keyEquivalent: "")
        window.submenu = windowMenu
        windowMenu.addItem(withTitle: "Minimize", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        windowMenu.addItem(withTitle: "Zoom", action: #selector(NSWindow.performZoom(_:)), keyEquivalent: "")
        let fullScreen = windowMenu.addItem(withTitle: "Toggle Full Screen", action: #selector(NSWindow.toggleFullScreen(_:)), keyEquivalent: "f")
        fullScreen.keyEquivalentModifierMask = [.control, .command]
    }

    private func addMenu(title: String) -> NSMenu {
        let item = menu.addItem(withTitle: title, action: nil, keyEquivalent: "")
        let submenu = NSMenu(title: title)
        item.submenu = submenu
        return submenu
    }
}
