import AppKit
import SwiftUI
import Combine

@MainActor
final class WindowController: NSWindowController, NSWindowDelegate {
    private let model: AppModel
    private var selection: AnyCancellable?

    init(model: AppModel) {
        self.model = model
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 696, height: 740),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable],
                              backing: .buffered, defer: false)
        window.title = "Deep Work"
        window.contentMinSize = NSSize(width: 320, height: 420)
        window.isReleasedWhenClosed = false
        window.collectionBehavior = [.fullScreenPrimary]
        window.contentViewController = NSHostingController(rootView: RootView(model: model))
        super.init(window: window)
        window.delegate = self
        window.center()
        // @Published emits before the property changes. Resizing synchronously
        // forces NSHostingController to lay out the *previous* panel and can
        // leave the selected tab and visible content one transition apart.
        selection = model.$selectedTab.removeDuplicates().receive(on: RunLoop.main).sink { [weak self] tab in
            self?.resize(for: tab)
        }
    }

    required init?(coder: NSCoder) { nil }

    override func showWindow(_ sender: Any?) {
        if window?.isMiniaturized == true { window?.deminiaturize(sender) }
        super.showWindow(sender)
        window?.makeKeyAndOrderFront(sender)
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        model.persistCommittedState()
        sender.orderOut(nil)
        return false
    }

    private func resize(for tab: AppTab) {
        guard let window, !window.styleMask.contains(.fullScreen) else { return }
        let contentHeight: CGFloat = tab == .focus ? 500 : 740
        let available = window.screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1200, height: 900)
        let size = NSSize(width: min(tab.preferredWidth, available.width), height: min(contentHeight, available.height - 40))
        let desired = window.frameRect(forContentRect: NSRect(origin: .zero, size: size))
        var frame = window.frame
        frame.origin.y += frame.height - desired.height
        frame.size = desired.size
        frame.origin.x = max(available.minX, min(frame.origin.x, available.maxX - frame.width))
        frame.origin.y = max(available.minY, min(frame.origin.y, available.maxY - frame.height))
        window.setFrame(frame, display: true)
    }
}
