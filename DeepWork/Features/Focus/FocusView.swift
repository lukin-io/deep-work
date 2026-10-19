import AppKit
import SwiftUI
import DeepWorkCore

struct FocusView: View {
    @ObservedObject var model: AppModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @FocusState private var focusedControl: Control?
    private enum Control: Hashable { case focusPicker, breakPicker, focusCustom, breakCustom, start, primary }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            if model.timer.isRecovered {
                Text("Your unfinished session is paused at its last saved point. Resume when you’re ready.")
                    .font(.caption).foregroundStyle(.secondary).padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.accentColor.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
                    .accessibilityIdentifier("dw-recovery-note")
            }
            if model.timer.state == .setup { setup } else { sessionDisplay }
            VStack(alignment: .leading, spacing: 4) {
                Toggle("Repeat cycles", isOn: model.repeats).toggleStyle(.checkbox)
                    .accessibilityIdentifier("dw-repeat")
                Text(model.repeatExplanation).font(.caption).foregroundStyle(.secondary)
                    .accessibilityIdentifier("dw-repeat-note")
            }
            if model.timer.state == .setup {
                VStack(spacing: 10) {
                    Text(model.durationSummary).font(.caption).foregroundStyle(.secondary)
                        .accessibilityIdentifier("dw-summary")
                    Button("Start deep work") { model.startFocus(); focusedControl = .primary }
                        .buttonStyle(.borderedProminent).controlSize(.large)
                        .disabled(!model.canStart).focused($focusedControl, equals: .start)
                        .accessibilityIdentifier("dw-start")
                }.frame(maxWidth: .infinity)
            } else { sessionControls }
            if model.journalFailure != nil {
                Text(model.journalStorageMessage).font(.caption).foregroundStyle(.red)
                    .accessibilityIdentifier("dw-focus-storage-warning")
            }
            Divider()
            if let slack = model.slack { SlackStatusView(service: slack) }
        }
        .frame(maxWidth: 440, alignment: .leading).frame(maxWidth: .infinity)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("dw-focus-panel")
        .task(id: model.focusRequest) {
            guard model.consumeFocusControlRequest() else { return }
            // Explicit navigation can insert this panel before its native
            // controls exist. Let insertion finish, then honor the request
            // only while this view still owns the selected tab.
            await Task.yield()
            guard !Task.isCancelled, model.selectedTab == .focus else { return }
            focusRelevantControl()
        }
        .onChange(of: model.durationSummary) { _, text in if model.timer.state == .setup { announce(text) } }
        .onChange(of: model.focusDurationError) { _, error in if let error { announce("Deep work: \(error)") } }
        .onChange(of: model.breakDurationError) { _, error in if let error { announce("Break: \(error)") } }
    }

    private var setup: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Set your rhythm.").font(.system(size: 20, weight: .semibold))
            durationField("Deep work", placeholder: "Deep work cycle", selection: model.focusSelection,
                          presets: [60, 90], custom: $model.customFocusText, isFocus: true, error: model.focusDurationError)
            durationField("Break", placeholder: "Break cycle", selection: model.breakSelection,
                          presets: [10, 20], custom: $model.customBreakText, isFocus: false, error: model.breakDurationError)
        }.accessibilityElement(children: .contain).accessibilityIdentifier("dw-setup")
    }

    private var sessionDisplay: some View {
        VStack(spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: model.timer.state == .focus ? "scope" : "cup.and.saucer").accessibilityHidden(true)
                Text(model.timer.phaseTitle).accessibilityAddTraits(.isHeader).accessibilityIdentifier("dw-phase-name")
            }.font(.system(size: 12, weight: .medium)).foregroundStyle(.secondary)
            Text(model.timer.countdownText).font(.system(size: 58, weight: .light)).monospacedDigit()
                .minimumScaleFactor(0.6).lineLimit(1)
                .accessibilityElement(children: .ignore)
                .accessibilityAddTraits(.updatesFrequently)
                .accessibilityLabel("Time remaining").accessibilityValue(model.timer.countdownText)
                .accessibilityIdentifier("dw-timer")
            Text(model.timerCaption).font(.caption).foregroundStyle(.secondary)
                .accessibilityIdentifier("dw-run-caption")
            FocusProgressView(fraction: model.timer.progressFraction, reduceMotion: reduceMotion)
        }.frame(maxWidth: .infinity).padding(.vertical, 6)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("dw-running")
    }

    private var sessionControls: some View {
        VStack(spacing: 14) {
            HStack(spacing: 10) {
                // Separate handlers preserve the action the user actually invoked.
                // A stale Pause reconciles to completion without becoming Start again.
                if model.timer.state == .complete {
                    Button("Start again") { model.restartTimer() }.focused($focusedControl, equals: .primary)
                        .accessibilityIdentifier("dw-pause")
                } else if model.timer.isPaused {
                    Button("Resume") { model.resumeTimer() }.focused($focusedControl, equals: .primary)
                        .accessibilityIdentifier("dw-pause")
                } else {
                    Button("Pause") { model.pauseTimer() }.focused($focusedControl, equals: .primary)
                        .accessibilityIdentifier("dw-pause")
                }
                if let title = model.timer.nextActionTitle, let phaseID = model.timer.phaseID {
                    Button(title) { model.advanceTimer(expectedPhaseID: phaseID) }
                        .buttonStyle(.bordered).accessibilityIdentifier("dw-next")
                }
            }.buttonStyle(.borderedProminent).controlSize(.large)
            Button("End session") { model.endSession(); focusedControl = .start }
                .buttonStyle(.plain).foregroundStyle(.secondary).accessibilityIdentifier("dw-end")
        }.frame(maxWidth: .infinity)
    }

    private func durationField(_ title: String, placeholder: String, selection: Binding<DurationSelection>,
                               presets: [Int], custom: Binding<String>, isFocus: Bool, error: String?) -> some View {
        let prefix = isFocus ? "dw-focus" : "dw-break"
        return VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.system(size: 12)).foregroundStyle(.secondary)
            Picker(title, selection: selection) {
                Text(placeholder).tag(DurationSelection.unselected).disabled(true)
                ForEach(presets, id: \.self) { Text("\($0) minutes").tag(DurationSelection.preset($0)) }
                Text("Custom…").tag(DurationSelection.custom)
            }.labelsHidden().frame(maxWidth: .infinity).accessibilityLabel(placeholder)
                .accessibilityIdentifier("\(prefix)-select")
                .focused($focusedControl, equals: isFocus ? .focusPicker : .breakPicker)
            if selection.wrappedValue == .custom {
                HStack {
                    TextField("Minutes", text: custom).textFieldStyle(.roundedBorder)
                        .focused($focusedControl, equals: isFocus ? .focusCustom : .breakCustom)
                        .accessibilityLabel(isFocus ? "Custom deep work minutes" : "Custom break minutes")
                        .accessibilityHint(error ?? "Whole minutes from 1 to 480")
                        .accessibilityIdentifier("\(prefix)-custom")
                    Text("minutes").foregroundStyle(.secondary)
                }
            }
            if let error {
                Text(error).font(.caption).foregroundStyle(.red).accessibilityIdentifier("\(prefix)-error")
            }
        }
        .onChange(of: selection.wrappedValue) { _, value in
            guard value == .custom else { return }
            focusedControl = isFocus ? .focusCustom : .breakCustom
            // Give the newly inserted SwiftUI field its editor before selecting.
            DispatchQueue.main.async { NSApp.sendAction(#selector(NSText.selectAll(_:)), to: nil, from: nil) }
        }
    }

    private func focusRelevantControl() {
        focusedControl = model.timer.state == .setup ? .focusPicker : .primary
    }
    private func announce(_ message: String) {
        model.announce(message)
    }
}
