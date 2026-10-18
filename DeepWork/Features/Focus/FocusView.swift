import SwiftUI
import DeepWorkCore

struct FocusView: View {
    @ObservedObject var model: AppModel
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Set your rhythm.").font(.system(size: 20, weight: .semibold))
            durationField("Deep work", placeholder: "Deep work cycle", selection: model.focusSelection, presets: [60, 90], custom: $model.customFocusText)
            durationField("Break", placeholder: "Break cycle", selection: model.breakSelection, presets: [10, 20], custom: $model.customBreakText)
            if let error = model.configurationError { Text(error).font(.caption).foregroundStyle(.red) }
            VStack(alignment: .leading, spacing: 4) {
                Toggle("Repeat cycles", isOn: model.repeats).toggleStyle(.checkbox)
                Text(model.repeatExplanation).font(.caption).foregroundStyle(.secondary)
            }
            Button("Start deep work") {}.buttonStyle(.borderedProminent)
                .frame(maxWidth: .infinity).disabled(true)
            AvailabilityNote(text: "The focus timer is not available yet.")
            if model.journalFailure != nil { Text(model.journalStorageMessage).font(.caption).foregroundStyle(.red) }
            Divider()
            HStack {
                Label("Slack status", systemImage: "number")
                Spacer()
                Text("Preview").foregroundStyle(.secondary)
            }.font(.caption)
            Surface { Text("❌ Deep WORK, DND").font(.system(size: 13, weight: .medium)) }
            AvailabilityNote(text: "Slack is not connected. No status changes are made.")
        }
        .frame(maxWidth: 440, alignment: .leading).frame(maxWidth: .infinity)
        .accessibilityIdentifier("dw-focus-panel")
    }

    private func durationField(_ title: String, placeholder: String, selection: Binding<DurationSelection>, presets: [Int], custom: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.system(size: 12)).foregroundStyle(.secondary)
            Picker(title, selection: selection) {
                Text(placeholder).tag(DurationSelection.unselected)
                ForEach(presets, id: \.self) { Text("\($0) minutes").tag(DurationSelection.preset($0)) }
                Text("Custom…").tag(DurationSelection.custom)
            }.labelsHidden().frame(maxWidth: .infinity).accessibilityLabel(placeholder)
            if selection.wrappedValue == .custom {
                HStack {
                    TextField("Minutes", text: custom).textFieldStyle(.roundedBorder)
                        .accessibilityLabel("\(title) custom minutes")
                    Text("min").foregroundStyle(.secondary)
                }
            }
        }
    }
}
