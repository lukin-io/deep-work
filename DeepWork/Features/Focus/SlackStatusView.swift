import AppKit
import SwiftUI

struct SlackStatusView: View {
    @ObservedObject var service: SlackStatusController

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Slack status", systemImage: "number")
                Spacer()
                Text(service.account == nil ? "Preview" : "Connected").foregroundStyle(.secondary)
            }.font(.caption)
            Surface {
                Text(service.account == nil ? "❌ Deep WORK, DND" : service.statusText)
                    .font(.system(size: 13, weight: .medium)).accessibilityIdentifier("dw-slack-status")
            }
            if let account = service.account {
                AvailabilityNote(text: "\(account.userName) · \(account.workspaceName). Status only; notifications are unchanged.")
            } else {
                AvailabilityNote(text: service.isConfigured
                    ? "Connect Slack to set your focus status and restore it after focus. Notifications are unchanged."
                    : "Slack is not configured in this build. No status changes are made.")
            }
            HStack {
                Button(service.account == nil ? "Connect Slack" : "Reconnect Slack") {
                    Task { await service.connect() }
                }.disabled(!service.canConnect).accessibilityIdentifier("dw-slack-connect")
                if service.account != nil {
                    Button("Disconnect") { Task { await service.disconnect() } }
                        .disabled(service.isBusy).accessibilityIdentifier("dw-slack-disconnect")
                }
                if service.isBusy { ProgressView().controlSize(.small).accessibilityLabel("Updating Slack") }
            }.controlSize(.small)
            if let failure = service.failureMessage {
                Text(failure).font(.caption).foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true).accessibilityIdentifier("dw-slack-error")
                Button("Retry") { Task { await service.retry() } }
                    .controlSize(.small).disabled(service.isBusy).accessibilityIdentifier("dw-slack-retry")
            }
        }
        .accessibilityElement(children: .contain).accessibilityIdentifier("dw-slack-section")
        .onChange(of: service.failureMessage) { _, value in
            guard let value else { return }
            NativeAccessibilityAnnouncer().announce(value, priority: .high)
        }
    }
}
