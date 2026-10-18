import SwiftUI

struct JournalView: View {
    @ObservedObject var model: AppModel
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("Focus journal").font(.system(size: 20, weight: .semibold))
                    Text(model.scheduleSummary).font(.system(size: 11)).foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                Button("Schedule") {}.disabled(true)
            }
            Picker("Report period", selection: $model.reportPeriod) {
                ForEach(ReportPeriod.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }.pickerStyle(.segmented).disabled(true)
            HStack { Text("This week").fontWeight(.medium); Spacer(); Button("Today") {}.disabled(true) }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), alignment: .leading)], alignment: .leading, spacing: 16) {
                metric("Focus time", note: "Breaks & pauses excluded")
                metric("Completed cycles", note: "Full focus cycles")
                metric("Days with focus", note: "")
            }
            Divider()
            HStack { Text("Daily focus").fontWeight(.medium); Spacer(); Text("By day").foregroundStyle(.secondary) }
            Surface {
                AvailabilityNote(text: "Journal reports and example data are not available yet.")
                Color.clear.frame(height: 48)
            }
            AvailabilityNote(text: "All focus time is included, even on days off.")
            HStack {
                Text("Sessions").fontWeight(.medium)
                Spacer()
                Button("Export CSV") {}.disabled(true)
            }
            Surface {
                VStack(spacing: 8) {
                    Image(systemName: "book").font(.title2).foregroundStyle(.secondary)
                    Text(model.journal.records.isEmpty ? "No focus sessions here yet." : "\(model.journal.records.count) saved sessions on this device.")
                    Text(model.journal.records.isEmpty ? "Every focused minute will find its place here." : "Your history is retained. Session reports are not available yet.")
                        .font(.caption).foregroundStyle(.secondary)
                    Button("Start a focus cycle") { model.selectedTab = .focus }
                }.frame(maxWidth: .infinity).padding(.vertical, 10)
            }
            AvailabilityNote(text: "Partial sessions add focus time. A cycle counts only when its full focus duration is complete.")
            VStack(alignment: .leading, spacing: 6) {
                Text(model.journalStorageMessage)
                    .foregroundStyle(model.journalFailure == nil ? Color.secondary : .red)
                    .accessibilityIdentifier("dw-storage-status")
                HStack { Spacer(); Button("View example") {}.disabled(true) }
            }.font(.system(size: 11))
        }.font(.system(size: 12)).accessibilityIdentifier("dw-journal-panel")
    }
    private func metric(_ title: String, note: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title).foregroundStyle(.secondary)
            Text("—").font(.system(size: 27, weight: .medium)).monospacedDigit()
            Text(note).font(.system(size: 10)).foregroundStyle(.secondary)
        }
    }
}
