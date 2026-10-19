import AppKit
import SwiftUI
import DeepWorkCore

struct SettingsView: View {
    @ObservedObject var model: AppModel
    @FocusState private var field: FeedbackActionFocus?
    @StateObject private var presentation = FeedbackPresentation()
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Settings").font(.system(size: 20, weight: .semibold))
                .accessibilityAddTraits(.isHeader).accessibilityIdentifier("dw-settings-title")
            section("General") {
                Surface {
                    Toggle(isOn: Binding(get: { model.launchAtLoginRequested }, set: { enabled in
                        Task { await model.setLaunchAtLogin(enabled) }
                    })) {
                        VStack(alignment: .leading, spacing: 5) {
                            Text("Launch at Login")
                            AvailabilityNote(text: "Open Deep Work automatically when you log in to your Mac.")
                                .accessibilityIdentifier("dw-launch-helper")
                        }
                    }.toggleStyle(.switch).disabled(!model.canChangeLoginItem).accessibilityIdentifier("dw-launch-login")
                        .accessibilityLabel("Launch at Login")
                        .accessibilityHint("Open Deep Work automatically when you log in to your Mac. \(model.loginItemStatusMessage)")
                    AvailabilityNote(text: model.loginItemStatusMessage).accessibilityIdentifier("dw-launch-preview")
                    if let error = model.loginItemError {
                        Text(error).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier("dw-launch-error")
                    }
                    if model.showsLoginItemSettingsAction {
                        Button("Open Login Items…", action: model.openLoginItemSettings)
                            .disabled(!model.canChangeLoginItem).accessibilityIdentifier("dw-launch-open-settings")
                    }
                }
            }
            section("Export") {
                Surface {
                    Picker("Include", selection: $model.exportScope) {
                        Text("All Sessions").tag(ExportScope.all)
                        Text("Current Journal Report").tag(ExportScope.current)
                    }.accessibilityIdentifier("dw-settings-export-scope")
                    AvailabilityNote(text: model.settingsExportSummary)
                        .accessibilityIdentifier("dw-settings-export-note")
                    HStack {
                        Spacer()
                        Button("Export to CSV…") { Task { await model.exportSettingsCSV() } }
                            .disabled(!model.canExportSettings || model.isExporting)
                            .accessibilityIdentifier("dw-settings-export-button")
                    }
                    if let error = model.settingsExportError {
                        Text(error).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier("dw-settings-export-error")
                    }
                    if let status = model.settingsExportStatus {
                        AvailabilityNote(text: status).accessibilityIdentifier("dw-settings-export-status")
                    }
                }
            }
            section("Feedback") {
                Surface {
                    AvailabilityNote(text: "This preview can save a draft or copy your feedback to share.")
                        .accessibilityIdentifier("dw-feedback-note")
                    Picker("Feedback type", selection: $model.feedbackType) {
                        Text("Idea").tag(FeedbackType.idea)
                        Text("Problem").tag(FeedbackType.problem)
                        Text("General feedback").tag(FeedbackType.general)
                    }.accessibilityIdentifier("dw-feedback-type")
                    VStack(alignment: .leading, spacing: 5) {
                        Text("Email (optional)")
                        FeedbackEmailField(text: Binding(
                            get: { model.feedbackEmail },
                            set: { model.feedbackEmail = FeedbackPresentation.limitedInput($0, utf16Limit: 254) }
                        ), focusRequest: presentation.emailFocusRequest,
                        accessibilityHint: model.feedbackError == FeedbackValidationError.email.localizedDescription
                            ? FeedbackValidationError.email.localizedDescription : "Optional reply address", onSubmit: saveDraft)
                            .frame(height: 22)
                    }
                    VStack(alignment: .leading, spacing: 5) {
                        Text("Your feedback")
                        ZStack(alignment: .topLeading) {
                            FeedbackMessageEditor(text: Binding(
                                get: { model.feedbackMessage },
                                set: { model.feedbackMessage = FeedbackPresentation.limitedInput($0, utf16Limit: 5000) }
                            ), focusRequest: presentation.focusRequest, selectionRequest: presentation.selectionRequest,
                            accessibilityHint: model.feedbackError == FeedbackValidationError.message.localizedDescription
                                ? FeedbackValidationError.message.localizedDescription : "Required. 5 to 5,000 characters.")
                                .frame(height: 96)
                            if model.feedbackMessage.isEmpty {
                                Text("What would you like to share?").foregroundStyle(.tertiary)
                                    .padding(.horizontal, 9).padding(.top, 5)
                                    .allowsHitTesting(false).accessibilityHidden(true)
                            }
                        }.overlay(RoundedRectangle(cornerRadius: 4).stroke(Color(nsColor: .separatorColor)))
                    }
                    if let error = model.feedbackError {
                        Text(error).foregroundStyle(.red).font(.caption)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier("dw-feedback-error")
                    }
                    HStack {
                        Spacer()
                        Button("Save Draft", action: saveDraft)
                            .keyboardShortcut(.return, modifiers: .command)
                            .accessibilityIdentifier("dw-feedback-save")
                        Button("Copy Feedback", action: copyFeedback)
                            .buttonStyle(.borderedProminent).focused($field, equals: .copy)
                            .accessibilityIdentifier("dw-feedback-copy")
                    }
                    if let status = model.feedbackStatus {
                        AvailabilityNote(text: status).accessibilityIdentifier("dw-feedback-status")
                    }
                }
            }
            Text(model.settingsStorageMessage).font(.system(size: 11))
                .foregroundStyle(model.settingsFailure == nil ? Color.secondary : .red)
                .accessibilityIdentifier("dw-settings-storage-status")
        }.font(.system(size: 12))
            .accessibilityElement(children: .contain).accessibilityIdentifier("dw-settings-panel")
            .onAppear { model.refreshLoginItemStatus() }
            .onChange(of: model.loginItemError) { _, error in if let error { announce(error, priority: .high) } }
            .onChange(of: model.loginItemStatus) { _, _ in announce(model.loginItemStatusMessage) }
            .onChange(of: model.feedbackError) { _, error in if let error { announce(error, priority: .high) } }
            .onChange(of: model.feedbackStatus) { _, status in if let status { announce(status) } }
            .onChange(of: model.settingsExportError) { _, error in if let error { announce(error, priority: .high) } }
    }
    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).foregroundStyle(.secondary).fontWeight(.medium).accessibilityAddTraits(.isHeader)
            content()
        }
    }

    private func saveDraft() {
        switch model.saveFeedbackDraft() {
        case .email:
            field = nil
            presentation.focusEmail()
        case .message:
            field = nil
            presentation.focusMessage()
        case nil: break
        }
    }

    private func copyFeedback() {
        guard let target = model.copyFeedback() else { return }
        if target == .email {
            field = nil
            presentation.focusEmail()
        } else if target == .selectMessage {
            field = nil
            presentation.selectMessage()
        } else if target == .message {
            field = nil
            presentation.focusMessage()
        } else {
            field = target
        }
    }

    private func announce(_ message: String, priority: NSAccessibilityPriorityLevel = .medium) {
        guard let window = NSApp.keyWindow else { return }
        NSAccessibility.post(element: window, notification: .announcementRequested,
                             userInfo: [.announcement: message, .priority: priority.rawValue])
    }
}
