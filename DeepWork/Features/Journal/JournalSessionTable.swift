import AppKit
import SwiftUI

/// AppKit supplies real table headers, row/cell accessibility, a fixed header,
/// alternating rows and independent scrolling without adding selection/editing.
struct JournalSessionTable: NSViewRepresentable {
    var rows: [JournalRowPresentation]

    func makeCoordinator() -> Coordinator { Coordinator(rows: rows) }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = true
        scroll.autohidesScrollers = true
        scroll.borderType = .bezelBorder
        let table = NSTableView()
        table.setAccessibilityIdentifier("dw-session-table")
        table.setAccessibilityLabel("Focus sessions")
        table.headerView = NSTableHeaderView()
        table.usesAlternatingRowBackgroundColors = true
        table.backgroundColor = .controlBackgroundColor
        table.rowHeight = 43
        table.intercellSpacing = NSSize(width: 12, height: 2)
        table.allowsColumnReordering = false
        table.allowsColumnResizing = true
        table.allowsMultipleSelection = false
        table.selectionHighlightStyle = .none
        table.columnAutoresizingStyle = .uniformColumnAutoresizingStyle
        for (index, title) in ["Started", "Ended", "Focus time", "Cycle"].enumerated() {
            let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(String(index)))
            column.title = title
            column.minWidth = index == 1 ? 105 : 90
            column.width = index == 1 ? 145 : 125
            column.isEditable = false
            column.headerCell.font = .systemFont(ofSize: 10)
            column.headerCell.alignment = index > 1 ? .right : .left
            table.addTableColumn(column)
        }
        table.dataSource = context.coordinator
        table.delegate = context.coordinator
        scroll.documentView = table
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let table = scroll.documentView as? NSTableView else { return }
        guard context.coordinator.rows != rows else { return }
        context.coordinator.rows = rows
        table.reloadData()
    }

    @MainActor
    final class Coordinator: NSObject, NSTableViewDataSource, NSTableViewDelegate {
        var rows: [JournalRowPresentation]
        init(rows: [JournalRowPresentation]) { self.rows = rows }

        func numberOfRows(in tableView: NSTableView) -> Int { rows.count }
        func tableView(_ tableView: NSTableView, shouldSelectRow row: Int) -> Bool { false }

        func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
            guard rows.indices.contains(row), let identifier = tableColumn?.identifier,
                  let index = Int(identifier.rawValue) else { return nil }
            let item = rows[row]
            let title: String
            let detail: String
            let help: String
            switch index {
            case 0: title = item.startedDate; detail = item.startedTime; help = item.startedHelp
            case 1: title = item.endedDate; detail = item.endedTime; help = item.endedHelp
            case 2: title = item.focus; detail = item.focusDetail; help = "\(item.focus) in range; \(item.focusDetail)"
            case 3: title = item.cycle; detail = item.cycleDetail; help = [title, detail].filter { !$0.isEmpty }.joined(separator: ", ")
            default: return nil
            }
            let cell = (tableView.makeView(withIdentifier: identifier, owner: nil) as? JournalTableCell) ?? JournalTableCell()
            cell.identifier = identifier
            cell.configure(title: title, detail: detail, help: help, trailing: index > 1,
                           accent: index == 3 && item.isLive, secondary: index == 3 && item.isPartial, hasStatusDot: index == 3)
            cell.setAccessibilityIdentifier("dw-session-\(item.id.uuidString)-\(index)")
            return cell
        }
    }
}

@MainActor
private final class JournalTableCell: NSTableCellView {
    private let primary = NSTextField(labelWithString: "")
    private let secondary = NSTextField(labelWithString: "")

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        for field in [primary, secondary] {
            field.translatesAutoresizingMaskIntoConstraints = false
            field.lineBreakMode = .byTruncatingTail
            addSubview(field)
        }
        primary.font = .monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        secondary.font = .monospacedDigitSystemFont(ofSize: 10, weight: .regular)
        secondary.textColor = .secondaryLabelColor
        NSLayoutConstraint.activate([
            primary.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 3),
            primary.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -3),
            primary.topAnchor.constraint(equalTo: topAnchor, constant: 5),
            secondary.leadingAnchor.constraint(equalTo: primary.leadingAnchor),
            secondary.trailingAnchor.constraint(equalTo: primary.trailingAnchor),
            secondary.topAnchor.constraint(equalTo: primary.bottomAnchor, constant: 2)
        ])
        setAccessibilityElement(true)
        setAccessibilityRole(.cell)
    }
    required init?(coder: NSCoder) { nil }

    func configure(title: String, detail: String, help: String, trailing: Bool, accent: Bool, secondary isSecondary: Bool, hasStatusDot: Bool) {
        primary.stringValue = hasStatusDot ? "• \(title)" : title
        secondary.stringValue = detail
        primary.alignment = trailing ? .right : .left
        secondary.alignment = primary.alignment
        primary.textColor = accent ? .controlAccentColor : (isSecondary ? .secondaryLabelColor : .labelColor)
        toolTip = help
        // The status dot is decorative; its meaning is carried by the label.
        setAccessibilityLabel(help)
    }
}
