import AppKit
import Testing
import DeepWorkCore
@testable import DeepWorkApp

extension NativeApplicationTests {
@Suite(.serialized)
@MainActor
struct MenuBarIntegrationTests {
    @Test func testG003_G006_AC11NativeButtonReopensHiddenSettingsWithoutPausingOrRestartingFocus() async throws {
        prepareNativeTestApplication()
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let clock = TestTimerClock()
        let model = makeModel(directory: directory, clock: clock)
        let windowController = WindowController(model: model)
        var activationRequests = 0
        // The real status button/window run in-process. Foreground activation
        // belongs to the app's run loop; record that request in a hostless test.
        let menu = MenuBarController(model: model, windowController: windowController,
                                     activateApplication: { activationRequests += 1 })
        let button = try #require(menu.button)
        let window = try #require(windowController.window)
        defer { window.orderOut(nil) }
        configure(model)
        model.startFocus()
        let recordID = try #require(model.timer.liveRecord?.id)
        model.feedbackMessage = "An unsaved draft survives a menu-bar reopen"
        clock.advance(17)
        model.selectedTab = .settings
        windowController.showWindow(nil)
        requestNativeWindowClose(window)
        #expect(!window.isVisible)
        #expect(!model.timer.isPaused)

        clock.advance(10); model.refreshTimer()
        #expect(!window.isVisible)
        #expect(button.title == "00:33 - Deep work")
        // sendAction exercises the real button wiring without performClick's
        // synthetic click tracking, which ends the hostless SwiftPM main loop.
        #expect(button.sendAction(button.action, to: button.target))
        #expect(window.isVisible)
        #expect(model.selectedTab == .focus)
        #expect(model.timer.liveRecord?.id == recordID)
        #expect(!model.timer.isPaused)
        #expect(model.timer.remainingSeconds == 33)
        #expect(model.timer.liveRecord?.focusedSeconds == 27)
        #expect(button.title == "00:33 - Deep work")
        #expect(model.feedbackMessage == "An unsaved draft survives a menu-bar reopen")

        model.pauseTimer()
        model.selectedTab = .settings
        requestNativeWindowClose(window)
        #expect(!window.isVisible)
        clock.advance(600); model.refreshTimer()
        #expect(button.title == "00:33 - Deep work")
        #expect(button.sendAction(button.action, to: button.target))
        #expect(window.isVisible && model.selectedTab == .focus)
        #expect(model.timer.isPaused && model.timer.remainingSeconds == 33)
        #expect(model.timer.liveRecord?.id == recordID)
        #expect(model.timer.liveRecord?.focusedSeconds == 27)
        #expect(button.title == "00:33 - Deep work")
        #expect(button.accessibilityLabel()?.hasPrefix("Paused") == true)
        #expect(model.journal.records.isEmpty)

        model.selectedTab = .journal
        #expect(button.sendAction(button.action, to: button.target))
        #expect(model.selectedTab == .focus)
        #expect(model.timer.liveRecord?.id == recordID)
        #expect(activationRequests == 3)
        await model.flushPersistence()
        withExtendedLifetime(menu) {}
    }

    @Test func testG003_G004_G006_AC11HiddenBoundaryUpdatesMenuAndClickPreservesRunningAndPausedBreak() async throws {
        prepareNativeTestApplication()
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let clock = TestTimerClock()
        let model = makeModel(directory: directory, clock: clock)
        let windowController = WindowController(model: model)
        var activationRequests = 0
        let menu = MenuBarController(model: model, windowController: windowController,
                                     activateApplication: { activationRequests += 1 })
        let button = try #require(menu.button)
        let window = try #require(windowController.window)
        defer { window.orderOut(nil) }
        configure(model, repeats: false)
        model.startFocus()
        let recordID = try #require(model.timer.liveRecord?.id)
        clock.advance(55)
        model.selectedTab = .journal
        windowController.showWindow(nil)
        requestNativeWindowClose(window)
        #expect(!window.isVisible && !model.timer.isPaused)

        clock.advance(10); model.refreshTimer()
        let breakID = model.timer.phaseID
        #expect(!window.isVisible)
        #expect(button.title == "00:55 - Break")
        #expect(model.timer.state == .break && !model.timer.isPaused)
        #expect(model.journal.records.count == 1)
        #expect(model.journal.records.first?.id == recordID)
        #expect(model.journal.records.first?.outcome == .complete)
        #expect(model.journal.records.first?.focusedSeconds == 60)
        #expect(model.timer.liveRecord == nil)
        #expect(button.sendAction(button.action, to: button.target))
        #expect(windowController.window === window)
        #expect(window.isVisible && model.selectedTab == .focus)
        #expect(model.timer.phaseID == breakID)
        #expect(!model.timer.isPaused && model.timer.remainingSeconds == 55)

        model.pauseTimer()
        requestNativeWindowClose(window)
        clock.advance(600); model.refreshTimer()
        #expect(!window.isVisible && model.timer.isPaused)
        #expect(button.title == "00:55 - Break")
        #expect(button.sendAction(button.action, to: button.target))
        #expect(window.isVisible && model.selectedTab == .focus)
        #expect(model.timer.isPaused && model.timer.remainingSeconds == 55)
        #expect(model.timer.phaseID == breakID)
        #expect(model.journal.records.count == 1)
        #expect(activationRequests == 2)
        await model.flushPersistence()
        withExtendedLifetime(menu) {}
    }

    @Test func testG004_G005NativeStatusProjectionUsesCeilingTabularDigitsAndExactlyOneStateIcon() async throws {
        prepareNativeTestApplication()
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let clock = TestTimerClock()
        let model = makeModel(directory: directory, clock: clock)
        let windowController = WindowController(model: model)
        defer { windowController.window?.orderOut(nil) }
        let menu = MenuBarController(model: model, windowController: windowController)
        let button = try #require(menu.button)
        #expect(button.title == "Deep Work")
        #expect(button.toolTip == "Show Deep Work")
        expectIcon(button, description: "Timer")
        #expect(button.accessibilityLabel()?.contains("Show Deep Work window") == true)
        let font = try #require(button.font)
        let zeroWidth = ("000000" as NSString).size(withAttributes: [.font: font]).width
        for digit in 1...9 {
            let text = String(repeating: String(digit), count: 6) as NSString
            #expect(abs(text.size(withAttributes: [.font: font]).width - zeroWidth) < 0.001)
        }

        configure(model, focus: 60, rest: 10, repeats: false)
        model.startFocus()
        #expect(button.title == "60:00 - Deep work")
        clock.advance(0.25); model.refreshTimer()
        #expect(button.title == "60:00 - Deep work")
        clock.advance(0.75); model.refreshTimer()
        #expect(button.title == "59:59 - Deep work")
        model.pauseTimer()
        expectIcon(button, description: "Paused")
        #expect(button.accessibilityLabel()?.hasPrefix("Paused") == true)
        clock.advance(600); model.refreshTimer()
        #expect(button.title == "59:59 - Deep work")
        model.resumeTimer()
        expectIcon(button, description: "Timer")
        #expect(button.accessibilityLabel()?.hasPrefix("Paused") == false)
        clock.advance(3599); model.refreshTimer()
        #expect(button.title == "10:00 - Break")
        expectIcon(button, description: "Timer")
        model.pauseTimer()
        expectIcon(button, description: "Paused")
        model.resumeTimer()
        clock.advance(600); model.refreshTimer()
        #expect(button.title == "Deep Work")
        #expect(model.timer.state == .complete)
        expectIcon(button, description: "Timer")
        model.endSession()
        configure(model, focus: 480, rest: 1)
        model.startFocus()
        #expect(button.title == "480:00 - Deep work")
        await model.flushPersistence()
        withExtendedLifetime(menu) {}
    }

    private func expectIcon(_ button: NSStatusBarButton, description: String) {
        #expect(button.image != nil)
        #expect(button.image?.accessibilityDescription == description)
        #expect(button.image?.isTemplate == true)
        #expect(button.alternateImage == nil)
        #expect(button.imagePosition == .imageLeading)
    }

    private func makeModel(directory: URL, clock: TestTimerClock) -> AppModel {
        AppModel(journalStore: JournalStore(directory: directory), settingsStore: SettingsStore(directory: directory),
                 clock: clock, automaticRefresh: false)
    }

    private func configure(_ model: AppModel, focus: Int = 1, rest: Int = 1, repeats: Bool = true) {
        model.focusSelection.wrappedValue = .custom
        model.breakSelection.wrappedValue = .custom
        model.customFocusText = String(focus)
        model.customBreakText = String(rest)
        model.repeats.wrappedValue = repeats
    }

    private func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("DeepWorkMenuTests-\(UUID())")
    }
}

}
