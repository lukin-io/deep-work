import SwiftUI
import DeepWorkCore

struct SettingsView: View {
    @ObservedObject var model: AppModel
    @FocusState private var field: FeedbackField?
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Settings").font(.system(size: 20, weight: .semibold))
            section("General") {
                Surface {
                    Toggle(isOn: .constant(false)) {
                        VStack(alignment: .leading, spacing: 5) {
                            Text("Launch at Login")
                            AvailabilityNote(text: "Open Deep Work automatically when you log in to your Mac.")
                        }
                    }.toggleStyle(.switch).disabled(true)
                    AvailabilityNote(text: "Launch at Login is not available yet.")
                }
            }
            section("Export") {
                Surface {
                    Picker("Include", selection: $model.exportScope) {
                        Text("All Sessions").tag(ExportScope.all)
                        Text("Current Journal Report").tag(ExportScope.current)
                    }.disabled(true)
                    AvailabilityNote(text: "Export all sessions from your journal, including partial sessions.")
                    HStack { Spacer(); Button("Export to CSV…") {}.disabled(true) }
                    AvailabilityNote(text: "CSV export is not available yet.")
                }
            }
            section("Feedback") {
                Surface {
                    AvailabilityNote(text: "Save a draft on this device. Nothing is sent.")
                    Picker("Feedback type", selection: $model.feedbackType) {
                        Text("Idea").tag(FeedbackType.idea)
                        Text("Problem").tag(FeedbackType.problem)
                        Text("General feedback").tag(FeedbackType.general)
                    }
                    VStack(alignment: .leading, spacing: 5) {
                        Text("Email (optional)")
                        TextField("you@example.com", text: $model.feedbackEmail)
                            .textFieldStyle(.roundedBorder).focused($field, equals: .email)
                            .accessibilityLabel("Email (optional)")
                    }
                    VStack(alignment: .leading, spacing: 5) {
                        Text("Your feedback")
                        TextEditor(text: $model.feedbackMessage).font(.system(size: 12))
                            .frame(height: 96).padding(4)
                            .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color(nsColor: .separatorColor)))
                            .focused($field, equals: .message).accessibilityLabel("Your feedback")
                    }
                    if let error = model.feedbackError { Text(error).foregroundStyle(.red).font(.caption) }
                    HStack {
                        Spacer()
                        Button("Save Draft") { field = model.saveFeedbackDraft() }
                        Button("Copy Feedback") {}.disabled(true)
                    }
                    if let status = model.feedbackStatus { AvailabilityNote(text: status) }
                    AvailabilityNote(text: "Copy Feedback is not available yet.")
                }
            }
            Text(model.settingsStorageMessage).font(.system(size: 11))
                .foregroundStyle(model.settingsFailure == nil ? Color.secondary : .red)
                .accessibilityIdentifier("dw-settings-storage-status")
        }.font(.system(size: 12)).accessibilityIdentifier("dw-settings-panel")
    }
    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).foregroundStyle(.secondary).fontWeight(.medium)
            content()
        }
    }
}
