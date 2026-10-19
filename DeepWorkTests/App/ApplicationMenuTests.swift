import AppKit
import Testing
import DeepWorkCore
@testable import DeepWorkApp

extension NativeApplicationTests {
@Suite(.serialized)
@MainActor
struct ApplicationMenuTests {
    @Test func testG002NativeMenuInventoryUsesStandardShortcutsAndResponderChainTargets() async throws {
        let fixture = makeFixture()
        defer { fixture.close() }
        let previousMain = NSApp.mainMenu
        let previousWindow = NSApp.windowsMenu
        let previousServices = NSApp.servicesMenu
        defer {
            NSApp.servicesMenu = previousServices
            NSApp.windowsMenu = previousWindow
            NSApp.mainMenu = previousMain
        }
        fixture.menus.install()
        #expect(NSApp.mainMenu === fixture.menus.menu)
        #expect(fixture.menus.menu.items.map(\.title) == ["Deep Work", "File", "Edit", "Window"])
        #expect(NSApp.windowsMenu?.title == "Window")
        #expect(NSApp.servicesMenu?.title == "Services")
        let settings = try item("Settings…", in: "Deep Work", fixture: fixture)
        #expect(settings.keyEquivalent == "," && settings.keyEquivalentModifierMask == .command)
        #expect(settings.target === fixture.menus)
        let show = try item("Show Deep Work", in: "File", fixture: fixture)
        #expect(show.keyEquivalent == "0" && show.keyEquivalentModifierMask == .command)
        #expect(show.target === fixture.menus)
        let expected: [(String, String, String, NSEvent.ModifierFlags, Selector)] = [
            ("Deep Work", "About Deep Work", "", .command, #selector(NSApplication.orderFrontStandardAboutPanel(_:))),
            ("Deep Work", "Hide Deep Work", "h", .command, #selector(NSApplication.hide(_:))),
            ("Deep Work", "Hide Others", "h", [.option, .command], #selector(NSApplication.hideOtherApplications(_:))),
            ("Deep Work", "Show All", "", .command, #selector(NSApplication.unhideAllApplications(_:))),
            ("Deep Work", "Quit Deep Work", "q", .command, #selector(NSApplication.terminate(_:))),
            ("File", "Close Window", "w", .command, #selector(NSWindow.performClose(_:))),
            ("Edit", "Undo", "z", .command, Selector(("undo:"))),
            ("Edit", "Redo", "z", [.shift, .command], Selector(("redo:"))),
            ("Edit", "Cut", "x", .command, #selector(NSText.cut(_:))),
            ("Edit", "Copy", "c", .command, #selector(NSText.copy(_:))),
            ("Edit", "Paste", "v", .command, #selector(NSText.paste(_:))),
            ("Edit", "Select All", "a", .command, #selector(NSText.selectAll(_:))),
            ("Window", "Minimize", "m", .command, #selector(NSWindow.performMiniaturize(_:))),
            ("Window", "Zoom", "", .command, #selector(NSWindow.performZoom(_:))),
            ("Window", "Toggle Full Screen", "f", [.control, .command], #selector(NSWindow.toggleFullScreen(_:)))
        ]
        for (menu, title, shortcut, modifiers, action) in expected {
            let command = try item(title, in: menu, fixture: fixture)
            #expect(command.keyEquivalent == shortcut, "Unexpected shortcut for \(title)")
            #expect(command.keyEquivalentModifierMask == modifiers, "Unexpected modifiers for \(title)")
            #expect(command.action == action, "Unexpected action for \(title)")
            #expect(command.target == nil, "\(title) must follow the current responder chain")
        }
        await fixture.model.flushPersistence()
    }

    @Test(arguments: [false, true])
    func testG002_G006SettingsShortcutReopensSameWindowWithoutResettingRunningOrPausedSession(_ paused: Bool) async throws {
        let fixture = makeFixture()
        defer { fixture.close() }
        let window = try #require(fixture.window.window)
        fixture.model.focusSelection.wrappedValue = .preset(60)
        fixture.model.breakSelection.wrappedValue = .preset(10)
        fixture.model.startFocus()
        fixture.clock.advance(17)
        fixture.model.refreshTimer()
        if paused { fixture.model.pauseTimer() }
        let recordID = try #require(fixture.model.timer.liveRecord?.id)
        let remaining = fixture.model.timer.remainingSeconds
        fixture.model.selectedTab = .journal
        fixture.model.feedbackMessage = "A retained unsaved draft"
        fixture.window.showWindow(nil)
        requestNativeWindowClose(window)
        #expect(!window.isVisible)
        fixture.clock.advance(4)
        let settings = try item("Settings…", in: "Deep Work", fixture: fixture)
        #expect(fixture.menus.validateMenuItem(settings))
        let key = try keyEvent(",", code: 43, modifiers: .command, window: window)
        #expect(fixture.menus.menu.performKeyEquivalent(with: key))
        #expect(window.isVisible)
        #expect(fixture.window.window === window)
        #expect(fixture.model.selectedTab == .settings)
        #expect(fixture.model.timer.liveRecord?.id == recordID)
        #expect(fixture.model.timer.isPaused == paused)
        #expect(fixture.model.timer.remainingSeconds == remaining - (paused ? 0 : 4))
        #expect(fixture.model.feedbackMessage == "A retained unsaved draft")
        #expect(fixture.activation.requests == 1)
        #expect(fixture.model.journal.records.isEmpty)

        // Repeating the Settings command reuses the visible window. The File
        // command still selects Focus using the same live timer/model.
        #expect(NSApp.sendAction(settings.action!, to: settings.target, from: settings))
        #expect(fixture.model.selectedTab == .settings && fixture.window.window === window)
        let show = try item("Show Deep Work", in: "File", fixture: fixture)
        #expect(NSApp.sendAction(show.action!, to: show.target, from: show))
        #expect(fixture.model.selectedTab == .focus)
        #expect(fixture.model.timer.liveRecord?.id == recordID && fixture.model.timer.isPaused == paused)
        #expect(fixture.activation.requests == 3)
        await fixture.model.flushPersistence()
    }

    @Test func testG002NavigationCommandsCannotReopenOrChangeTabsDuringQuit() async throws {
        let fixture = makeFixture()
        defer { fixture.close() }
        let window = try #require(fixture.window.window)
        fixture.model.selectedTab = .journal
        #expect(await fixture.model.prepareForTermination())
        window.orderOut(nil)
        for (title, menu) in [("Settings…", "Deep Work"), ("Show Deep Work", "File")] {
            let command = try item(title, in: menu, fixture: fixture)
            #expect(!fixture.menus.validateMenuItem(command))
            #expect(NSApp.sendAction(command.action!, to: command.target, from: command))
        }
        #expect(!window.isVisible)
        #expect(fixture.model.selectedTab == .journal)
        #expect(fixture.activation.requests == 0)
    }

    @Test func testG002_S016NativeEditCommandsUndoAndRedoFeedbackWithoutSaving() async throws {
        let fixture = makeFixture()
        defer { fixture.close() }
        let window = try #require(fixture.window.window)
        fixture.model.selectedTab = .settings
        fixture.model.feedbackMessage = "Retained feedback"
        fixture.window.showWindow(nil)
        let content = try #require(window.contentView)
        var message: NSTextView?
        for _ in 0..<100 {
            content.layoutSubtreeIfNeeded()
            message = findMessage(in: content)
            if message?.string == "Retained feedback" { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        let editor = try #require(message)
        try #require(window.makeFirstResponder(editor))
        let undoManager = try #require(editor.undoManager)
        undoManager.removeAllActions()
        editor.insertText("!", replacementRange: NSRange(location: editor.string.utf16.count, length: 0))
        #expect(fixture.model.feedbackMessage == "Retained feedback!")
        let undo = try item("Undo", in: "Edit", fixture: fixture)
        let redo = try item("Redo", in: "Edit", fixture: fixture)
        // The hostless runner has no NSApplication.keyWindow even after
        // makeKeyAndOrderFront. Resolve each real menu selector through the
        // native responder chain here. The inventory test requires nil
        // production targets; the compiled app verifies global routing.
        #expect(editor.tryToPerform(try #require(undo.action), with: undo))
        #expect(editor.string == "Retained feedback")
        #expect(fixture.model.feedbackMessage == "Retained feedback")
        #expect(undoManager.canRedo)
        #expect(editor.tryToPerform(try #require(redo.action), with: redo))
        #expect(editor.string == "Retained feedback!")
        #expect(fixture.model.feedbackMessage == "Retained feedback!")
        let select = try item("Select All", in: "Edit", fixture: fixture)
        #expect(editor.tryToPerform(try #require(select.action), with: select))
        #expect(editor.selectedRange() == NSRange(location: 0, length: editor.string.utf16.count))
        await fixture.model.flushPersistence()
        #expect(SettingsStore(directory: fixture.directory).load().value.feedbackDraft == .empty)
    }

    private final class Activation { var requests = 0 }

    private struct Fixture {
        let directory: URL
        let model: AppModel
        let clock: TestTimerClock
        let window: WindowController
        let menus: ApplicationMenuController
        let activation: Activation

        @MainActor func close() {
            window.window?.orderOut(nil)
            try? FileManager.default.removeItem(at: directory)
        }
    }

    private func makeFixture() -> Fixture {
        prepareNativeTestApplication()
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("DeepWorkAppMenus-\(UUID())")
        let clock = TestTimerClock()
        let model = AppModel(journalStore: JournalStore(directory: directory), settingsStore: SettingsStore(directory: directory),
                             clock: clock, automaticRefresh: false)
        let window = WindowController(model: model)
        let activation = Activation()
        let menus = ApplicationMenuController(model: model, windowController: window, activateApplication: { activation.requests += 1 })
        return Fixture(directory: directory, model: model, clock: clock, window: window, menus: menus, activation: activation)
    }

    private func item(_ title: String, in menu: String, fixture: Fixture) throws -> NSMenuItem {
        let submenu = try #require(fixture.menus.menu.item(withTitle: menu)?.submenu)
        return try #require(submenu.item(withTitle: title))
    }

    private func keyEvent(_ characters: String, code: UInt16, modifiers: NSEvent.ModifierFlags, window: NSWindow) throws -> NSEvent {
        try #require(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: modifiers, timestamp: 0,
                                    windowNumber: window.windowNumber, context: nil, characters: characters,
                                    charactersIgnoringModifiers: characters, isARepeat: false, keyCode: code))
    }

    private func findMessage(in view: NSView) -> NSTextView? {
        if let editor = view as? NSTextView, editor.accessibilityIdentifier() == "dw-feedback-message" { return editor }
        return view.subviews.lazy.compactMap { findMessage(in: $0) }.first
    }
}
}
