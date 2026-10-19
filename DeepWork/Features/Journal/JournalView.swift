import AppKit
import SwiftUI
import DeepWorkCore

struct JournalView: View {
    @ObservedObject var model: AppModel
    @FocusState private var scheduleFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if model.scheduleDraft != nil {
                WorkScheduleView(model: model)
            } else {
                report
            }
        }
        .font(.system(size: 12))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("dw-journal-panel")
        .onChange(of: model.scheduleSaveStatus) { _, status in if let status { announce(status) } }
        .onChange(of: model.rangeError) { _, error in if let error { announce(error) } }
        .onChange(of: model.journalExportError) { _, error in if let error { announce(error) } }
        .onChange(of: model.showingExamples) { _, examples in
            announce(examples ? "Showing example data, separate from your journal." : "Showing your journal.")
        }
    }

    private var report: some View {
        VStack(alignment: .leading, spacing: 18) {
            heading
            reportControls
            if model.reportPeriod == .range { customRange }
            HStack(alignment: .firstTextBaseline) {
                Text(model.reportTitle).fontWeight(.medium).fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("dw-period-title")
                Spacer(minLength: 8)
                Button("Today") { model.showToday() }.buttonStyle(.link).accessibilityIdentifier("dw-today")
            }
            if model.showingExamples { exampleBanner }
            metrics
            activity
            sessions
            footer
        }
    }

    private var heading: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 5) {
                Text("Focus journal").font(.system(size: 20, weight: .semibold)).accessibilityAddTraits(.isHeader)
                Text(model.scheduleSummary).font(.system(size: 11)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true).accessibilityIdentifier("dw-schedule-summary")
            }
            Spacer(minLength: 8)
            Button { model.openSchedule() } label: { Label("Schedule", systemImage: "calendar") }
                .focused($scheduleFocused).accessibilityIdentifier("dw-open-schedule")
                .task(id: model.scheduleNavigationRequest) {
                    guard model.consumeScheduleReturnFocusRequest() else { return }
                    // Wait until SwiftUI has inserted the returning report's
                    // button. Cancelling this task on navigation prevents it
                    // from taking focus after the user leaves Journal.
                    await Task.yield()
                    guard !Task.isCancelled, model.selectedTab == .journal,
                          model.scheduleDraft == nil else { return }
                    scheduleFocused = true
                }
        }
    }

    private var reportControls: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 16) { periodPicker; Spacer(minLength: 0); dateNavigation }
            VStack(alignment: .leading, spacing: 10) { periodPicker; dateNavigation }
        }
    }

    private var periodPicker: some View {
        Picker("Report period", selection: $model.reportPeriod) {
            ForEach(ReportPeriod.allCases, id: \.self) { Text($0.rawValue).tag($0) }
        }
        .pickerStyle(.segmented).labelsHidden().accessibilityLabel("Report period")
        .frame(width: 190).accessibilityIdentifier("dw-periods")
    }

    @ViewBuilder private var dateNavigation: some View {
        if model.reportPeriod != .range {
            HStack(spacing: 4) {
                Button { model.previousReport() } label: { Image(systemName: "chevron.left") }
                    .accessibilityLabel(model.reportPeriod == .day ? "Previous day" : "Previous week")
                    .accessibilityIdentifier("dw-previous-period")
                DatePicker("Choose report date or week", selection: $model.reportDate, displayedComponents: .date)
                    .labelsHidden().datePickerStyle(.field).fixedSize()
                    .environment(\.timeZone, model.reportingTimeZone)
                    .accessibilityLabel("Choose report date or week").accessibilityIdentifier("dw-report-date")
                Button { model.nextReport() } label: { Image(systemName: "chevron.right") }
                    .accessibilityLabel(model.reportPeriod == .day ? "Next day" : "Next week")
                    .accessibilityIdentifier("dw-next-period")
            }.buttonStyle(.borderless)
        }
    }

    private var customRange: some View {
        VStack(alignment: .leading, spacing: 7) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 12) { rangeFrom; rangeUntil }
                VStack(alignment: .leading, spacing: 10) { rangeFrom; rangeUntil }
            }
            Text("Includes the start; stops at the end time. Dates use your local time zone.")
                .font(.system(size: 10)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            Text("Date and time: YYYY-MM-DDTHH:mm, for example 2026-10-19T09:00.")
                .font(.system(size: 10)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            if let error = model.rangeError {
                Text(error).font(.caption).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("dw-range-error")
            }
        }
    }
    private var rangeFrom: some View { rangeField("From", text: $model.rangeFromText, identifier: "dw-range-from") }
    private var rangeUntil: some View { rangeField("Until", text: $model.rangeUntilText, identifier: "dw-range-to") }
    private func rangeField(_ title: String, text: Binding<String>, identifier: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title).foregroundStyle(.secondary)
            TextField("YYYY-MM-DDTHH:mm", text: text).textFieldStyle(.roundedBorder)
                .font(.system(size: 12).monospacedDigit()).frame(minWidth: 205)
                .accessibilityLabel(title).accessibilityIdentifier(identifier)
                .accessibilityHint(model.rangeError ?? "Local date and time, year-month-day, T, hour:minute")
        }
    }

    private var exampleBanner: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Example data").fontWeight(.medium)
                Text("A preview, separate from your journal.").font(.system(size: 11)).foregroundStyle(.secondary)
            }
            Spacer(minLength: 4)
            Button("Show my journal") { model.showActualJournal() }.buttonStyle(.link)
                .accessibilityIdentifier("dw-show-own")
        }
        .padding(10).background(Color.accentColor.opacity(0.07), in: RoundedRectangle(cornerRadius: 6))
        .accessibilityElement(children: .contain).accessibilityIdentifier("dw-sample-banner")
    }

    private var metrics: some View {
        Surface {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: 16) {
                    focusMetric; Divider(); cycleMetric; Divider(); daysMetric
                }.fixedSize(horizontal: false, vertical: true)
                    .accessibilityElement(children: .contain)
                VStack(alignment: .leading, spacing: 12) {
                    focusMetric; Divider(); cycleMetric; Divider(); daysMetric
                }.accessibilityElement(children: .contain)
            }.accessibilityElement(children: .contain)
        }.accessibilityElement(children: .contain).accessibilityIdentifier("dw-statistics")
    }
    private var focusMetric: some View {
        metric("Focus time", value: JournalDuration.format(seconds: model.reportSnapshot.focusedSeconds, precise: false),
               note: "Breaks & pauses excluded", identifier: "dw-stat-time")
            .help(JournalDuration.format(seconds: model.reportSnapshot.focusedSeconds, precise: true))
    }
    private var cycleMetric: some View {
        let count = model.reportSnapshot.partialSessions
        return metric("Completed cycles", value: String(model.reportSnapshot.completedCycles),
                      note: "\(count) partial \(count == 1 ? "session" : "sessions")", identifier: "dw-stat-cycles")
    }
    private var daysMetric: some View {
        let report = model.reportSnapshot
        return metric("Days with focus", value: "\(report.daysWithFocus) / \(report.days.count)",
                      note: "\(report.scheduledDays) scheduled \(report.scheduledDays == 1 ? "day" : "days")", identifier: "dw-stat-days")
    }
    private func metric(_ title: String, value: String, note: String, identifier: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).foregroundStyle(.secondary)
            Text(value).font(.system(size: 27, weight: .medium)).monospacedDigit()
            Text(note).font(.system(size: 10)).foregroundStyle(.secondary)
        }.frame(minWidth: 135, maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(title).accessibilityValue(value).accessibilityHint(note)
            .accessibilityIdentifier(identifier)
    }

    private var activity: some View {
        VStack(alignment: .leading, spacing: 12) {
            ViewThatFits(in: .horizontal) {
                HStack { activityTitle; Spacer(); activityTools }
                VStack(alignment: .leading, spacing: 8) { activityTitle; activityTools }
            }
            JournalActivityChart(buckets: model.reportSnapshot.buckets, grouping: model.reportSnapshot.grouping,
                                 shortWeekdayLabels: model.reportPeriod == .week && model.reportSnapshot.buckets.count <= 7,
                                 today: model.currentReportingDay, timeZone: model.reportingTimeZone,
                                 open: model.openReportBucket)
            Text("Click a \(model.chartGrouping == .day ? "day" : "week") to see its sessions. All focus time is included, even on days off.")
                .font(.system(size: 10)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("dw-chart-note")
        }
    }
    private var activityTitle: some View {
        Text(model.chartGrouping == .day ? "Daily focus" : "Weekly focus").fontWeight(.medium)
            .accessibilityAddTraits(.isHeader).accessibilityIdentifier("dw-activity-title")
    }
    private var activityTools: some View {
        HStack(spacing: 12) {
            if model.chartGrouping == .day {
                HStack(spacing: 4) {
                    Circle().fill(Color(nsColor: .tertiaryLabelColor)).frame(width: 6, height: 6).accessibilityHidden(true)
                    Text("Day off")
                }.foregroundStyle(.secondary).font(.system(size: 10)).accessibilityIdentifier("dw-offday-legend")
            }
            Picker("Group activity", selection: $model.chartGrouping) {
                Text("By day").tag(JournalGrouping.day)
                Text("By week").tag(JournalGrouping.week)
            }.labelsHidden().fixedSize().accessibilityIdentifier("dw-grouping")
        }
    }

    private var sessions: some View {
        VStack(alignment: .leading, spacing: 12) {
            Divider()
            HStack {
                HStack(spacing: 6) {
                    Text("Sessions").fontWeight(.medium).accessibilityAddTraits(.isHeader)
                    Text(String(model.reportSnapshot.rows.count)).font(.system(size: 10)).foregroundStyle(.secondary)
                        .padding(.horizontal, 5).padding(.vertical, 2)
                        .background(Color(nsColor: .quaternaryLabelColor), in: RoundedRectangle(cornerRadius: 4))
                }.accessibilityElement(children: .combine).accessibilityIdentifier("dw-sessions-title")
                Spacer()
                Button("Export CSV") { Task { await model.exportJournalCSV() } }.disabled(!model.canExportJournal)
                    .accessibilityIdentifier("dw-export")
            }
            if let error = model.journalExportError {
                Text(error).font(.caption).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("dw-export-error")
            } else if let status = model.journalExportStatus {
                Text(status).font(.caption).foregroundStyle(.secondary)
                    .accessibilityIdentifier("dw-export-status")
            }
            if model.reportSnapshot.rows.isEmpty { emptyState }
            else {
                JournalSessionTable(rows: model.visibleSessionRows.map {
                    JournalRowPresentation(row: $0, paused: model.timer.isPaused, timeZone: model.reportingTimeZone)
                })
                .frame(height: min(274, CGFloat(model.visibleSessionRows.count * 45 + 28)))
                .clipShape(RoundedRectangle(cornerRadius: 7))
                if model.reportSnapshot.rows.count > 12 {
                    HStack {
                        Text(model.pageInfo).foregroundStyle(.secondary).accessibilityIdentifier("dw-page-info")
                        Spacer()
                        Button("Previous") { model.previousSessionPage() }.disabled(!model.canPreviousPage)
                            .accessibilityIdentifier("dw-page-prev")
                        Button("Next") { model.nextSessionPage() }.disabled(!model.canNextPage)
                            .accessibilityIdentifier("dw-page-next")
                    }.font(.system(size: 11))
                }
            }
            Text("Focus time is clipped to this range. Pauses and breaks are excluded. A completed cycle is counted at its finish time; partial sessions add time only.")
                .font(.system(size: 10)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("dw-accounting-note")
        }
    }
    private var emptyState: some View {
        Surface {
            VStack(spacing: 8) {
                Image(systemName: "book").font(.title2).foregroundStyle(.secondary).accessibilityHidden(true)
                Text("No focus sessions here yet.")
                Text("Every focused minute will find its place here.").font(.caption).foregroundStyle(.secondary)
                Button("Start a focus cycle") { model.showFocusFromJournal() }.buttonStyle(.link)
                    .accessibilityIdentifier("dw-empty-focus")
            }.frame(maxWidth: .infinity).padding(.vertical, 10)
        }.accessibilityElement(children: .contain).accessibilityIdentifier("dw-empty")
    }
    private var footer: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(model.journalStorageMessage).foregroundStyle(model.journalFailure == nil ? Color.secondary : .red)
                .fixedSize(horizontal: false, vertical: true).accessibilityIdentifier("dw-storage-status")
            Spacer(minLength: 0)
            Button(model.showingExamples ? "Show my journal" : "View example") { model.toggleExamples() }
                .buttonStyle(.link).fixedSize().accessibilityIdentifier("dw-toggle-sample")
        }.font(.system(size: 11)).accessibilityElement(children: .contain)
    }
    private func announce(_ message: String) {
        guard let window = NSApp.keyWindow else { return }
        NSAccessibility.post(element: window, notification: .announcementRequested,
                             userInfo: [.announcement: message, .priority: NSAccessibilityPriorityLevel.medium.rawValue])
    }
}

struct JournalActivityChart: View {
    let buckets: [JournalBucket]
    let grouping: JournalGrouping
    let shortWeekdayLabels: Bool
    let today: CivilDate
    let timeZone: TimeZone
    let open: (JournalBucket) -> Void
    @FocusState private var focusedBucket: String?

    var body: some View {
        GeometryReader { geometry in
            let maximum = buckets.map(\.focusedSeconds).max() ?? 0
            let count = max(1, buckets.count)
            let minWidth: CGFloat = buckets.count > 14 ? 44 : 35
            let columnWidth = max(minWidth, (geometry.size.width - CGFloat(count - 1) * 9) / CGFloat(count))
            ScrollView(.horizontal) {
                HStack(alignment: .bottom, spacing: 9) {
                    ForEach(buckets, id: \.key) { bucket in
                        bar(bucket, width: columnWidth, maximum: maximum)
                    }
                }
                .frame(minWidth: geometry.size.width, alignment: .leading)
                .background(alignment: .bottom) {
                    VStack(spacing: 41) { Divider(); Divider(); Divider() }
                        .padding(.bottom, 29).accessibilityHidden(true)
                }
            }
        }
        .frame(height: 169)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(grouping == .day ? "Focus time by day" : "Focus time by week")
        .accessibilityIdentifier("dw-chart")
    }

    private func bar(_ bucket: JournalBucket, width: CGFloat, maximum: TimeInterval) -> some View {
        let height = JournalPresentation.barHeight(seconds: bucket.focusedSeconds, maximum: maximum)
        let isToday = bucket.key == today
        let empty = bucket.focusedSeconds <= 0
        let offDay = grouping == .day && bucket.scheduledDays == 0
        let description = JournalPresentation.bucketDescription(bucket, grouping: grouping, timeZone: timeZone)
        return Button { open(bucket) } label: {
            VStack(spacing: 5) {
                Spacer(minLength: 0)
                Text(JournalDuration.format(seconds: bucket.focusedSeconds, precise: false))
                    .font(.system(size: 10)).foregroundStyle(.secondary).monospacedDigit()
                UnevenRoundedRectangle(topLeadingRadius: 4, bottomLeadingRadius: 1, bottomTrailingRadius: 1, topTrailingRadius: 4)
                    .fill(empty ? Color(nsColor: .separatorColor) : (offDay ? Color(nsColor: .tertiaryLabelColor) : .accentColor))
                    .frame(width: min(42, width), height: height)
                Text(JournalPresentation.date(bucket.start, pattern: grouping == .day && shortWeekdayLabels ? "EEE" : "MMM d", timeZone: timeZone))
                    .font(.system(size: 10, weight: isToday ? .semibold : .regular))
                    .foregroundStyle(isToday ? Color.accentColor : .secondary).lineLimit(1)
                    .frame(height: 25)
            }.frame(width: width, height: 159).contentShape(Rectangle())
        }
        .buttonStyle(.plain).focused($focusedBucket, equals: bucket.key.iso8601Date)
        .overlay(RoundedRectangle(cornerRadius: 4).stroke(focusedBucket == bucket.key.iso8601Date ? Color.accentColor : .clear, lineWidth: 2))
        .accessibilityLabel(description).accessibilityIdentifier("dw-bucket-\(bucket.key.iso8601Date)")
        .help(description)
    }
}
