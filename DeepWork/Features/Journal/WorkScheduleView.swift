import AppKit
import SwiftUI
import DeepWorkCore

/// The editor renders the shared transient draft. Leaving Journal never commits
/// or discards it; only the explicit Save and Cancel intentions do that.
struct WorkScheduleView: View {
    @ObservedObject var model: AppModel
    @FocusState private var focusedControl: Control?

    private enum Control: Hashable { case mode, workDays, restDays, anchor, cutoff }

    private var draft: WorkScheduleDraft {
        model.scheduleDraft ?? WorkScheduleDraft(schedule: model.journal.schedule)
    }

    private var preview: (days: [SchedulePreviewDay], error: String?) {
        do { return (try draft.preview(now: model.reportNow, timeZone: model.reportingTimeZone), nil) }
        catch { return ([], "The schedule preview could not be calculated. \(error.localizedDescription)") }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("Work schedule").font(.system(size: 20, weight: .semibold))
                        .accessibilityAddTraits(.isHeader).accessibilityIdentifier("dw-schedule-title")
                    AvailabilityNote(text: "Make the journal fit the way you work.")
                }
                Spacer()
                Image(systemName: "calendar").font(.system(size: 24)).foregroundStyle(.secondary)
                    .accessibilityHidden(true)
            }

            Surface {
                settingRow("Reporting days", helper: "Your pattern of work and rest") {
                    Picker("Reporting days", selection: binding(\.mode)) {
                        Text("Chosen weekdays").tag(ScheduleMode.chosenWeekdays)
                        Text("Any day").tag(ScheduleMode.anyDay)
                        Text("Rotating shifts").tag(ScheduleMode.rotatingShifts)
                    }.labelsHidden().frame(width: 155)
                        .accessibilityLabel("Reporting days").accessibilityIdentifier("dw-schedule-mode")
                        .focused($focusedControl, equals: .mode)
                }
                Divider()
                modeDetails
            }

            Surface {
                settingRow("Week starts on", helper: "Used by weekly reports") {
                    Picker("Week starts on", selection: binding(\.weekStartsOn)) {
                        ForEach(Weekday.allCases, id: \.self) { Text($0.name).tag($0) }
                    }.labelsHidden().frame(width: 155)
                        .accessibilityLabel("Week starts on").accessibilityIdentifier("dw-week-start")
                }
                Divider()
                settingRow("Reporting day starts at", helper: "Keep overnight work on the same day") {
                    TextField("HH:mm", text: binding(\.reportingDayStartText))
                        .textFieldStyle(.roundedBorder).monospacedDigit().frame(width: 78)
                        .focused($focusedControl, equals: .cutoff)
                        .accessibilityLabel("Reporting day starts at")
                        .accessibilityHint("24-hour time, HH:mm, from 00:00 to 23:59")
                        .accessibilityIdentifier("dw-day-start")
                }
            }

            schedulePreview

            if let error = draft.validationError ?? preview.error {
                Text(error).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("dw-schedule-error")
            }
            if let error = model.scheduleSaveError {
                Text(error).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("dw-schedule-save-error")
            }
            AvailabilityNote(text: "This sets how reports are grouped. Focus sessions on days off are always recorded. Changing the schedule recalculates reports and keeps your history.")
                .accessibilityIdentifier("dw-schedule-footnote")
            HStack {
                Spacer()
                Button("Cancel") { model.cancelSchedule() }.keyboardShortcut(.cancelAction)
                    .accessibilityIdentifier("dw-cancel-schedule")
                Button(model.isSavingSchedule ? "Saving…" : "Save schedule") {
                    Task { await model.saveSchedule() }
                }.buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
                    .disabled(draft.validationError != nil || preview.error != nil)
                    .accessibilityIdentifier("dw-save-schedule")
            }
        }
        .font(.system(size: 12))
        .disabled(model.isSavingSchedule)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("dw-schedule-panel")
        .task(id: model.scheduleNavigationRequest) {
            guard model.consumeScheduleControlRequest() else { return }
            // Wait for the newly inserted native picker to enter the window.
            // SwiftUI cancels this task on navigation, preventing a delayed
            // request from stealing focus after the user changes tabs.
            await Task.yield()
            guard !Task.isCancelled else { return }
            focusedControl = .mode
        }
        .onChange(of: draft.validationError) { _, error in if let error { announce(error) } }
        .onChange(of: model.scheduleSaveError) { _, error in if let error { announce(error) } }
    }

    @ViewBuilder private var modeDetails: some View {
        switch draft.mode {
        case .chosenWeekdays:
            VStack(alignment: .leading, spacing: 8) {
                ScheduleWeekdayButtons(weekdays: draft.weekdays) { weekday, selected in
                    model.updateScheduleDraft { $0.setWeekday(weekday, selected: selected) }
                }
                AvailabilityNote(text: "Choose any combination. A 5/2 week starts with Monday–Friday selected.")
            }.accessibilityElement(children: .contain).accessibilityIdentifier("dw-weekdays-setting")
        case .anyDay:
            AvailabilityNote(text: "Every day is available for focus. There are no fixed days off.")
                .accessibilityIdentifier("dw-everyday-setting")
        case .rotatingShifts:
            VStack(alignment: .leading, spacing: 12) {
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .bottom, spacing: 18) { shiftCounts; anchorField }
                    VStack(alignment: .leading, spacing: 12) { shiftCounts; anchorField }
                }
                AvailabilityNote(text: "This work/rest pattern repeats from the first work day.")
            }.accessibilityElement(children: .contain).accessibilityIdentifier("dw-shifts-setting")
        }
    }

    private var shiftCounts: some View {
        HStack(spacing: 12) {
            shiftCount("Work", path: \.workDaysText, control: .workDays, identifier: "dw-shift-on")
            shiftCount("Rest", path: \.restDaysText, control: .restDays, identifier: "dw-shift-off")
        }.fixedSize()
    }

    private func shiftCount(_ title: String, path: WritableKeyPath<WorkScheduleDraft, String>,
                            control: Control, identifier: String) -> some View {
        HStack(spacing: 5) {
            Text(title).foregroundStyle(.secondary)
            TextField("2", text: binding(path)).textFieldStyle(.roundedBorder).monospacedDigit().frame(width: 45)
                .focused($focusedControl, equals: control)
                .accessibilityLabel("\(title) days").accessibilityHint("Whole days from 1 to 31")
                .accessibilityIdentifier(identifier)
            Text("days").foregroundStyle(.secondary)
        }
    }

    private var anchorField: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("First work day").foregroundStyle(.secondary)
            TextField("YYYY-MM-DD", text: binding(\.firstWorkDayText))
                .textFieldStyle(.roundedBorder).monospacedDigit().frame(width: 132)
                .focused($focusedControl, equals: .anchor)
                .accessibilityLabel("First work day").accessibilityHint("Calendar date, YYYY-MM-DD")
                .accessibilityIdentifier("dw-shift-anchor")
        }
    }

    private var schedulePreview: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Next 14 days").fontWeight(.medium).accessibilityAddTraits(.isHeader)
                Spacer()
                Label("Work day", systemImage: "square.fill").foregroundStyle(.secondary)
                    .labelStyle(WorkDayLegendStyle())
            }
            ViewThatFits(in: .horizontal) {
                previewGrid(columns: 14).frame(minWidth: 555)
                previewGrid(columns: 7)
            }.accessibilityElement(children: .contain).accessibilityIdentifier("dw-schedule-days")
        }
    }

    private func previewGrid(columns: Int) -> some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 5), count: columns), spacing: 5) {
            ForEach(preview.days) { day in
                VStack(spacing: 4) {
                    Text(String(day.weekday.name.prefix(2))).font(.system(size: 10)).foregroundStyle(.secondary)
                    Text("\(day.date.day)").monospacedDigit()
                    // Work/Rest text also distinguishes the states without color.
                    Text(day.isScheduled ? "Work" : "Rest").font(.system(size: 10)).foregroundStyle(.secondary)
                }.padding(.vertical, 7).frame(maxWidth: .infinity)
                    .background(day.isScheduled ? Color.accentColor.opacity(0.08) : Color(nsColor: .controlBackgroundColor),
                                in: RoundedRectangle(cornerRadius: 5))
                    .overlay(RoundedRectangle(cornerRadius: 5)
                        .stroke(day.isScheduled ? Color.accentColor : Color(nsColor: .separatorColor), lineWidth: 1))
                    .help(previewLabel(day))
                    .accessibilityElement(children: .ignore).accessibilityLabel(previewLabel(day))
                    .accessibilityIdentifier("dw-schedule-day-\(day.date.iso8601Date)")
            }
        }
    }

    private func previewLabel(_ day: SchedulePreviewDay) -> String {
        let months = ["January", "February", "March", "April", "May", "June", "July", "August", "September", "October", "November", "December"]
        let month = months.indices.contains(day.date.month - 1) ? months[day.date.month - 1] : ""
        return "\(day.weekday.name), \(month) \(day.date.day) · \(day.isScheduled ? "Work" : "Rest")"
    }

    private func binding<Value>(_ path: WritableKeyPath<WorkScheduleDraft, Value>) -> Binding<Value> {
        Binding(get: { draft[keyPath: path] }, set: { value in model.updateScheduleDraft { $0[keyPath: path] = value } })
    }

    private func settingRow<ControlView: View>(_ title: String, helper: String,
                                              @ViewBuilder control: () -> ControlView) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 15) {
                settingLabel(title, helper: helper).fixedSize(horizontal: true, vertical: false)
                Spacer(minLength: 10)
                control()
            }
            VStack(alignment: .leading, spacing: 8) { settingLabel(title, helper: helper); control() }
        }
    }

    private func settingLabel(_ title: String, helper: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).fontWeight(.medium)
            AvailabilityNote(text: helper)
        }
    }

    private func announce(_ message: String) {
        model.announce(message, priority: .high)
    }
}

/// Keep the ordinary seven-column arrangement while allowing complete native
/// button labels to wrap into additional rows in a narrow window.
struct ScheduleWeekdayButtons: View {
    let weekdays: [Weekday]
    let setWeekday: (Weekday, Bool) -> Void

    var body: some View {
        ViewThatFits(in: .horizontal) {
            grid(columns: Array(repeating: GridItem(.flexible(minimum: 52), spacing: 4), count: 7))
            grid(columns: [GridItem(.adaptive(minimum: 52), spacing: 4)])
        }
        .accessibilityElement(children: .contain).accessibilityLabel("Scheduled workdays")
        .accessibilityIdentifier("dw-weekday-buttons")
    }

    private func grid(columns: [GridItem]) -> some View {
        LazyVGrid(columns: columns, spacing: 4) {
            ForEach(Weekday.allCases, id: \.self) { weekday in
                Toggle(String(weekday.name.prefix(3)), isOn: Binding(
                    get: { weekdays.contains(weekday) },
                    set: { selected in setWeekday(weekday, selected) }
                ))
                .toggleStyle(.button).buttonStyle(.bordered).controlSize(.small)
                .frame(maxWidth: .infinity, minHeight: 24)
                .accessibilityLabel(weekday.name)
                .accessibilityIdentifier("dw-weekday-\(weekday.rawValue)")
            }
        }
    }
}

private struct WorkDayLegendStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 5) {
            configuration.icon.foregroundStyle(Color.accentColor).font(.system(size: 9)).accessibilityHidden(true)
            configuration.title.font(.system(size: 11))
        }
    }
}
