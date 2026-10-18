import AppKit
import SwiftUI

enum AppTab: Int, CaseIterable {
    case focus, journal, settings
    var title: String { ["Focus", "Journal", "Settings"][rawValue] }
    var symbol: String { ["timer", "book", "gearshape"][rawValue] }
    var preferredWidth: CGFloat { [390, 696, 560][rawValue] }

    func moving(_ delta: Int) -> AppTab {
        AppTab(rawValue: (rawValue + delta + Self.allCases.count) % Self.allCases.count)!
    }
}

/// One native key-view entry. Arrow/Home/End handling is scoped to this control,
/// so report and feedback fields keep their ordinary editing keys.
final class TabSegmentedControl: NSSegmentedControl {
    override var acceptsFirstResponder: Bool { true }
    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        super.mouseDown(with: event)
    }
    override func keyDown(with event: NSEvent) {
        let tab = AppTab(rawValue: selectedSegment) ?? .journal
        let next: AppTab
        switch event.keyCode {
        case 123: next = tab.moving(-1)
        case 124: next = tab.moving(1)
        case 115: next = .focus
        case 119: next = .settings
        default: super.keyDown(with: event); return
        }
        selectedSegment = next.rawValue
        sendAction(action, to: target)
    }
}

struct NavigationTabs: NSViewRepresentable {
    @Binding var selection: AppTab

    func makeNSView(context: Context) -> TabSegmentedControl {
        let control = TabSegmentedControl()
        control.segmentCount = AppTab.allCases.count
        control.trackingMode = .selectOne
        control.segmentStyle = .rounded
        control.controlSize = .regular
        control.font = .systemFont(ofSize: 12)
        control.setAccessibilityLabel("Views")
        for tab in AppTab.allCases {
            control.setLabel(tab.title, forSegment: tab.rawValue)
            control.setWidth(95, forSegment: tab.rawValue)
            control.setImage(NSImage(systemSymbolName: tab.symbol, accessibilityDescription: nil), forSegment: tab.rawValue)
        }
        control.target = context.coordinator
        control.action = #selector(Coordinator.changed(_:))
        return control
    }
    func updateNSView(_ control: TabSegmentedControl, context: Context) {
        context.coordinator.parent = self
        control.selectedSegment = selection.rawValue
    }
    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }
    final class Coordinator: NSObject {
        var parent: NavigationTabs
        init(parent: NavigationTabs) { self.parent = parent }
        @objc func changed(_ control: NSSegmentedControl) {
            if let tab = AppTab(rawValue: control.selectedSegment) { parent.selection = tab }
        }
    }
}
