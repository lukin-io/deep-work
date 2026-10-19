import Foundation
import SwiftUI
import Combine
import DeepWorkCore

enum ReportPeriod: String, CaseIterable { case day = "Day", week = "Week", range = "Range" }
enum ExportScope { case all, current }
enum FeedbackField { case email, message }

/// The sole mutable owner of app data; views never create stores or sessions.
@MainActor
final class AppModel: ObservableObject {
    @Published var selectedTab: AppTab = .journal {
        didSet {
            guard !isTerminating, selectedTab != oldValue else { return }
            // A showFocus action can be superseded before Focus ever mounts.
            // Returning with the tab keys must not consume that stale request.
            if selectedTab != .focus { focusControlRequested = false }
            refreshTimer()
            refreshReport()
            if selectedTab == .settings { refreshLoginItemStatus() }
            persistJournal()
        }
    }
    @Published private(set) var journal: JournalDocument
    @Published private(set) var settings: SettingsDocument
    @Published private(set) var journalFailure: StoreFailure?
    @Published private(set) var settingsFailure: StoreFailure?
    @Published var reportPeriod: ReportPeriod = .week { didSet { reportSelectionChanged() } }
    @Published var reportDate = Date() { didSet { reportSelectionChanged() } }
    @Published var rangeFromText = "" { didSet { reportSelectionChanged() } }
    @Published var rangeUntilText = "" { didSet { reportSelectionChanged() } }
    @Published var chartGrouping: JournalGrouping = .day { didSet { refreshReport() } }
    @Published private(set) var reportSnapshot = JournalReport.empty()
    @Published private(set) var showingExamples = false
    @Published private(set) var sessionPage = 0
    @Published private(set) var reportingTimeZone: TimeZone
    @Published var scheduleDraft: WorkScheduleDraft?
    @Published private(set) var isSavingSchedule = false
    @Published private(set) var scheduleSaveError: String?
    @Published private(set) var scheduleSaveStatus: String?
    @Published private(set) var scheduleNavigationRequest = 0
    @Published var exportScope: ExportScope = .all {
        didSet {
            settingsExportRevision += 1
            settingsExportStatus = nil
            settingsExportError = nil
        }
    }
    @Published private(set) var isExporting = false
    @Published private(set) var settingsExportStatus: String?
    @Published private(set) var settingsExportError: String?
    @Published private(set) var journalExportStatus: String?
    @Published private(set) var journalExportError: String?
    @Published var customFocusText: String { didSet { updateCustomDuration(isFocus: true) } }
    @Published var customBreakText: String { didSet { updateCustomDuration(isFocus: false) } }
    @Published var feedbackType: FeedbackType { didSet { clearFeedbackResult() } }
    @Published var feedbackEmail: String { didSet { clearFeedbackResult() } }
    @Published var feedbackMessage: String { didSet { clearFeedbackResult() } }
    @Published private(set) var feedbackError: String?
    @Published private(set) var feedbackStatus: String?
    @Published private(set) var loginItemStatus: LoginItemStatus?
    @Published private(set) var isChangingLoginItem = false
    @Published private(set) var loginItemError: String?
    @Published private(set) var isTerminating = false
    @Published private(set) var lifecycleFailureMessage: String?
    @Published private(set) var timer: TimerEngine
    @Published private(set) var pendingJournalWrites = 0
    @Published private(set) var pendingSettingsWrites = 0
    @Published private(set) var focusRequest = 0
    let slack: SlackStatusController?
    private let persistence: PersistenceWorker
    private let clock: any TimerClock
    private let automaticRefresh: Bool
    private let ownershipLock: StoreOwnershipLock?
    private let csvFileExporter: any CSVFileExporting
    private let feedbackClipboard: any FeedbackCopying
    private let loginItemService: (any LoginItemServicing)?
    private let announcements: any AccessibilityAnnouncing
    private var announcedTimer: TimerAnnouncementState
    private var loginItemTask: Task<Void, Never>?
    private var ticker: Task<Void, Never>?
    private var lastCheckpointElapsed: TimeInterval
    private var feedbackRevision = 0
    private var focusControlRequested = false
    private var exampleRecords: [SessionRecord] = []
    private var reportsReady = false
    private var updatingReport = false
    private var lastReportElapsed = -Double.infinity
    private var calendarNotifications: [AnyCancellable] = []
    private var calendarBoundaryTask: Task<Void, Never>?
    private var scheduleSaveTask: Task<Void, Never>?
    private var scheduleControlRequested = false
    private var consumedScheduleNavigationRequest = 0
    private var settingsExportRevision = 0
    private var terminationExportFailure: String?
    private var terminationSlackFailure: String?
    private var awaitingQuitChoice = false

    init(journalStore: JournalPersisting, settingsStore: SettingsPersisting,
         clock: (any TimerClock)? = nil, automaticRefresh: Bool = true,
         ownershipLock: StoreOwnershipLock? = nil, reportingTimeZone: TimeZone? = nil,
         csvFileExporter: (any CSVFileExporting)? = nil,
         feedbackClipboard: (any FeedbackCopying)? = nil,
         loginItemService: (any LoginItemServicing)? = nil,
         slack: SlackStatusController? = nil,
         announcements: (any AccessibilityAnnouncing)? = nil) {
        self.clock = clock ?? ContinuousTimerClock()
        self.automaticRefresh = automaticRefresh
        self.ownershipLock = ownershipLock
        self.csvFileExporter = csvFileExporter ?? NativeCSVFileExportService()
        self.feedbackClipboard = feedbackClipboard ?? FeedbackClipboard()
        self.loginItemService = loginItemService
        self.slack = slack
        self.announcements = announcements ?? NativeAccessibilityAnnouncer()
        self.reportingTimeZone = reportingTimeZone ?? .current
        let instant = self.clock.now()
        lastCheckpointElapsed = instant.elapsed
        let journalLoad = journalStore.load()
        let settingsLoad = settingsStore.load()
        journal = journalLoad.value; settings = settingsLoad.value
        journalFailure = journalLoad.failure; settingsFailure = settingsLoad.failure
        // Store validation already rejects malformed checkpoints. Keep recovery
        // defensive at this boundary without silently turning corrupt data into history.
        let initialTimer: TimerEngine
        if let checkpoint = journalLoad.value.activeCheckpoint {
            do { initialTimer = try TimerEngine(checkpoint: checkpoint, repeats: journalLoad.value.configuration.repeats, at: instant) }
            catch {
                initialTimer = TimerEngine(repeats: journalLoad.value.configuration.repeats)
                journalFailure = StoreFailure(operation: .validation, fileURL: URL(fileURLWithPath: JournalStore.filename),
                                              reason: error.localizedDescription)
            }
        } else { initialTimer = TimerEngine(repeats: journalLoad.value.configuration.repeats) }
        timer = initialTimer
        announcedTimer = TimerAnnouncementState(initialTimer)
        persistence = PersistenceWorker(journalStore: journalStore, settingsStore: settingsStore)
        customFocusText = String(journalLoad.value.configuration.customFocusMinutes)
        customBreakText = String(journalLoad.value.configuration.customBreakMinutes)
        feedbackType = settingsLoad.value.feedbackDraft.type
        feedbackEmail = settingsLoad.value.feedbackDraft.email
        feedbackMessage = settingsLoad.value.feedbackDraft.message
        if !feedbackMessage.isEmpty { feedbackStatus = "Your saved draft is ready." }
        reconcileLoginItemStatus(persist: false)
        initializeReports()
        if reportingTimeZone == nil {
            calendarNotifications.append(NotificationCenter.default.publisher(for: .NSSystemTimeZoneDidChange)
                .sink { [weak self] _ in
                    Task { @MainActor [weak self] in self?.updateReportingTimeZone(.current) }
                })
        }
        for name in [Notification.Name.NSCalendarDayChanged, NSApplication.didBecomeActiveNotification] {
            calendarNotifications.append(NotificationCenter.default.publisher(for: name)
                .sink { [weak self] _ in
                    Task { @MainActor [weak self] in
                        self?.refreshReportCalendar()
                        if name == NSApplication.didBecomeActiveNotification { self?.refreshLoginItemStatus() }
                    }
                })
        }
        // Prove writes work before displaying "saved" even on a first launch.
        // Stores protect unreadable/unsupported files from fallback writes.
        persistCommittedState()
        slack?.start()
    }

    static func live(feedbackClipboard: (any FeedbackCopying)? = nil) throws -> AppModel {
        do {
            let directory: URL
            let legacyDirectory: URL?
            #if DEBUG
            if let override = ProcessInfo.processInfo.environment["DEEP_WORK_DATA_DIR"], !override.isEmpty {
                directory = URL(fileURLWithPath: override, isDirectory: true)
                legacyDirectory = nil
            } else {
                directory = try StoreLocation.applicationSupportDirectory()
                legacyDirectory = try StoreLocation.legacyApplicationSupportDirectory()
            }
            #else
            directory = try StoreLocation.applicationSupportDirectory()
            legacyDirectory = try StoreLocation.legacyApplicationSupportDirectory()
            #endif
            let ownership = try StoreOwnershipLock(directory: directory)
            return AppModel(journalStore: JournalStore(directory: directory, legacyDirectory: legacyDirectory),
                            settingsStore: SettingsStore(directory: directory, legacyDirectory: legacyDirectory), ownershipLock: ownership,
                            feedbackClipboard: feedbackClipboard, loginItemService: NativeLoginItemService(),
                            slack: SlackStatusController(client: NativeSlackClient(), store: SlackStore(directory: directory)))
        } catch StoreOwnershipError.alreadyOwned {
            throw StoreOwnershipError.alreadyOwned
        } catch {
            let failure = StoreFailure(operation: .read, fileURL: URL(fileURLWithPath: NSHomeDirectory()),
                                       reason: "Application Support is unavailable: \(error.localizedDescription)")
            return AppModel(journalStore: UnavailableJournalStore(failure: failure), settingsStore: UnavailableSettingsStore(failure: failure),
                            feedbackClipboard: feedbackClipboard, loginItemService: NativeLoginItemService(),
                            slack: SlackStatusController(client: NativeSlackClient(), store: UnavailableSlackStore(failure: failure)))
        }
    }

    var focusSelection: Binding<DurationSelection> {
        Binding(get: { self.journal.configuration.focusSelection }, set: { guard !self.isTerminating else { return }; self.journal.configuration.focusSelection = $0; self.persistJournal() })
    }
    var breakSelection: Binding<DurationSelection> {
        Binding(get: { self.journal.configuration.breakSelection }, set: { guard !self.isTerminating else { return }; self.journal.configuration.breakSelection = $0; self.persistJournal() })
    }
    var repeats: Binding<Bool> {
        Binding(get: { self.journal.configuration.repeats }, set: { value in
            guard !self.isTerminating else { return }
            let records = self.timer.setRepeating(value, at: self.clock.now())
            self.journal.configuration.repeats = value
            self.applyTimerChange(records)
        })
    }
    var focusDurationError: String? {
        journal.configuration.focusSelection == .custom && validMinutes(customFocusText) == nil ? Self.durationError : nil
    }
    var breakDurationError: String? {
        journal.configuration.breakSelection == .custom && validMinutes(customBreakText) == nil ? Self.durationError : nil
    }
    private static let durationError = "Choose a whole number from 1 to 480."
    var configurationError: String? { focusDurationError ?? breakDurationError }
    var canStart: Bool { !isTerminating && timer.state == .setup && configurationError == nil && journal.configuration.canStart }
    var durationSummary: String {
        guard configurationError == nil, let focus = journal.configuration.resolvedFocusMinutes,
              let rest = journal.configuration.resolvedBreakMinutes else { return "Choose both durations to begin." }
        return "\(focus) min deep → \(rest) min break"
    }
    var repeatExplanation: String { timer.repeatExplanation }
    var timerCaption: String {
        guard timer.state == .complete else { return timer.caption }
        if journalFailure != nil { return "Your session is in memory. It could not be saved." }
        if pendingJournalWrites > 0 { return "Saving to your journal…" }
        return timer.caption
    }
    var journalStorageMessage: String {
        if journalFailure != nil { return "Saving unavailable · export your journal to keep it" }
        return pendingJournalWrites > 0 ? "Saving on this device…" : "Saved on this device"
    }
    var settingsStorageMessage: String {
        if settingsFailure != nil { return "Settings could not be saved. They last only while the app is open." }
        return pendingSettingsWrites > 0 ? "Saving settings on this device…" : "Settings saved on this device"
    }

    // MARK: Observed macOS login service

    /// Pending approval is a registered request that the person can turn off.
    /// Its caption must explain that macOS will not launch it until approved.
    var launchAtLoginRequested: Bool { loginItemStatus == .enabled || loginItemStatus == .requiresApproval }
    var canChangeLoginItem: Bool { loginItemService != nil && !isChangingLoginItem && !isTerminating }
    var showsLoginItemSettingsAction: Bool {
        loginItemService != nil && (loginItemStatus == .requiresApproval || loginItemStatus == .notFound ||
            loginItemStatus == .unknown || loginItemError != nil)
    }
    var loginItemStatusMessage: String {
        if isChangingLoginItem { return "Updating Launch at Login…" }
        switch loginItemStatus {
        case .enabled: return "Deep Work will open when you log in to your Mac."
        case .notRegistered: return "Deep Work will not open automatically."
        case .requiresApproval: return "Approval required. Allow Deep Work in Login Items in System Settings."
        case .notFound: return "macOS could not find this login item. Try enabling Launch at Login again. Keep Deep Work in Applications."
        case .unknown: return "macOS could not determine Launch at Login status. Open Login Items to review it."
        case nil: return "Launch at Login is unavailable in this application instance."
        }
    }

    func refreshLoginItemStatus() {
        guard !isTerminating, !isChangingLoginItem else { return }
        let previousStatus = loginItemStatus
        reconcileLoginItemStatus()
        if previousStatus != loginItemStatus { loginItemError = nil }
    }

    func setLaunchAtLogin(_ enabled: Bool) async {
        guard canChangeLoginItem, !Task.isCancelled, let loginItemService else { return }
        isChangingLoginItem = true
        loginItemError = nil
        let request = Task { @MainActor [weak self] in
            guard let self else { return }
            do { _ = try await loginItemService.setEnabled(enabled) }
            catch { self.loginItemError = "Launch at Login could not be changed. \(error.localizedDescription)" }
            // Even a failed operation can leave a new system state. Persist
            // only that observed result and only the explicitly saved draft.
            self.reconcileLoginItemStatus()
        }
        loginItemTask = request
        await request.value
        loginItemTask = nil
        isChangingLoginItem = false
    }

    func openLoginItemSettings() {
        guard canChangeLoginItem else { return }
        loginItemService?.openSystemSettings()
    }

    private func reconcileLoginItemStatus(persist: Bool = true) {
        guard let loginItemService else { return }
        let observedStatus = loginItemService.status
        loginItemStatus = observedStatus
        guard settings.launchAtLogin != observedStatus.isEnabled else { return }
        settings.launchAtLogin = observedStatus.isEnabled
        if persist { persistSettings() }
    }
    var scheduleSummary: String {
        let schedule = journal.schedule
        let pattern: String
        switch schedule.mode {
        case .anyDay: pattern = "Any day"
        case .rotatingShifts: pattern = "\(schedule.workDays) on / \(schedule.restDays) off"
        case .chosenWeekdays:
            if schedule.weekdays == [.monday, .tuesday, .wednesday, .thursday, .friday] { pattern = "Monday–Friday" }
            else if schedule.weekdays.isEmpty { pattern = "No fixed workdays" }
            else if schedule.weekdays.count == 7 { pattern = "Every day" }
            else { pattern = schedule.weekdays.sorted { $0.rawValue < $1.rawValue }.map { String($0.name.prefix(3)) }.joined(separator: ", ") }
        }
        let cutoff = schedule.reportingDayStartMinutes
        let cutoffText = cutoff == 0 ? "" : String(format: " · Day starts %02d:%02d", cutoff / 60, cutoff % 60)
        return "\(pattern) · Week starts \(schedule.weekStartsOn.name)\(cutoffText)"
    }

    func saveFeedbackDraft() -> FeedbackField? {
        guard !isTerminating else { return nil }
        clearFeedbackResult()
        let candidate = FeedbackDraft(type: feedbackType, email: feedbackEmail, message: feedbackMessage)
        do {
            settings.feedbackDraft = try candidate.validatedForSaving()
            feedbackError = nil
            feedbackStatus = settingsFailure == nil ? "Saving draft…" : "Draft could not be saved. Use Copy Feedback to keep it."
            persistSettings(savedDraftRevision: feedbackRevision)
            return nil
        } catch {
            feedbackStatus = nil
            feedbackError = error.localizedDescription
            return (error as? FeedbackValidationError) == .email ? .email : .message
        }
    }

    /// Copy observes the edited form, never the stored draft. Invalidate an
    /// earlier Save result so a delayed disk acknowledgment cannot replace it.
    func copyFeedback() -> FeedbackActionFocus? {
        guard !isTerminating else { return nil }
        clearFeedbackResult()
        let candidate = FeedbackDraft(type: feedbackType, email: feedbackEmail, message: feedbackMessage)
        let text: String
        do { text = try candidate.validatedClipboardText() }
        catch {
            feedbackError = error.localizedDescription
            return (error as? FeedbackValidationError) == .email ? .email : .message
        }
        do {
            try feedbackClipboard.copy(text)
            feedbackStatus = "Feedback copied. Nothing has been sent."
            return .copy
        } catch {
            feedbackStatus = "Copy is unavailable. Select and copy your message."
            return .selectMessage
        }
    }

    func startFocus() {
        guard canStart else { return } // Revalidate raw editing text, not only last valid persisted values.
        do {
            let records = try timer.start(configuration: journal.configuration, at: clock.now())
            showingExamples = false
            sessionPage = 0
            applyTimerChange(records)
        }
        catch { return } // Validation prevents mutation; inline field errors explain invalid inputs.
    }
    func pauseTimer() { guard !isTerminating else { return }; applyTimerChange(timer.pause(at: clock.now())) }
    func resumeTimer() { guard !isTerminating else { return }; applyTimerChange(timer.resume(at: clock.now())) }
    func restartTimer() {
        guard !isTerminating else { return }
        showingExamples = false
        sessionPage = 0
        applyTimerChange(timer.restart(at: clock.now()))
    }
    func advanceTimer(expectedPhaseID: UUID) { guard !isTerminating else { return }; applyTimerChange(timer.advance(expectedPhaseID: expectedPhaseID, at: clock.now())) }
    func endSession() { guard !isTerminating else { return }; applyTimerChange(timer.end(at: clock.now())) }

    /// A refresh observes elapsed time; neither refresh count nor window lifetime
    /// determines accounting. Boundary records and the new checkpoint commit together.
    func refreshTimer() {
        guard !isTerminating else { return }
        let instant = clock.now()
        let oldPhase = timer.phaseID
        let oldState = timer.state
        let records = timer.reconcile(at: instant)
        journal.records.append(contentsOf: records)
        journal.activeCheckpoint = timer.activeCheckpoint
        if !records.isEmpty || oldPhase != timer.phaseID || oldState != timer.state ||
            (!timer.isPaused && timer.activeCheckpoint != nil && instant.elapsed - lastCheckpointElapsed >= 5) {
            persistJournal()
        }
        updateTicker()
        updateSlackProjection()
        announceTimerChange(completedCycles: records.filter { $0.outcome == .complete }.count)
        if (selectedTab == .journal && scheduleDraft == nil) || selectedTab == .settings {
            refreshReport(force: !records.isEmpty || oldPhase != timer.phaseID || oldState != timer.state)
        }
    }

    func showFocus() {
        guard !isTerminating else { return }
        refreshTimer()
        focusControlRequested = true
        selectedTab = .focus
        focusRequest += 1
    }

    func consumeFocusControlRequest() -> Bool {
        defer { focusControlRequested = false }
        return focusControlRequested
    }

    func persistCommittedState() {
        guard !isTerminating else { return }
        refreshTimer()
        persistJournal()
        persistSettings()
    }

    func flushPersistence() async {
        // A pending system change enqueues its observed settings result before
        // completion. Quit must not exit after persisting the earlier state.
        await loginItemTask?.value
        await scheduleSaveTask?.value
        await persistence.flush()
    }

    /// Seal at the Quit request and drain all queued transactions and results.
    /// A failed save cancels automatic termination and restores usable controls.
    @discardableResult
    func prepareForTermination() async -> Bool {
        guard !isTerminating else {
            await flushPersistence()
            await slack?.flush()
            return journalFailure == nil && settingsFailure == nil && terminationExportFailure == nil && terminationSlackFailure == nil
        }
        isTerminating = true
        awaitingQuitChoice = false
        lifecycleFailureMessage = nil
        terminationExportFailure = nil
        terminationSlackFailure = nil
        sealAndSaveForTermination()
        // An accepted Save must finish before the process exits. An untouched
        // destination panel is cancelled rather than holding Quit indefinitely.
        if case .failed(let reason) = await csvFileExporter.prepareForTermination() {
            terminationExportFailure = reason
        }
        terminationSlackFailure = await slack?.prepareForTermination()
        // The pending schedule transaction owns the next journal write. Its
        // completion merges only the accepted schedule into the latest timer
        // state and enqueues that state before Quit drains the worker.
        await scheduleSaveTask?.value
        await flushPersistence()
        let saved = recordLifecycleSaveResult()
        if !saved {
            awaitingQuitChoice = true
            isTerminating = false
            slack?.cancelTermination()
            scheduleCalendarBoundary()
        }
        return saved
    }

    private func sealAndSaveForTermination() {
        applyTimerChange(timer.pause(at: clock.now()))
        ticker?.cancel(); ticker = nil
        calendarBoundaryTask?.cancel(); calendarBoundaryTask = nil
        persistSettings()
    }

    /// Called only after the person chooses Keep Open. Do not reapply a remote
    /// focus status while they could still choose Quit Without Saving.
    func keepOpenAfterCancelledQuit() {
        guard !isTerminating else { return }
        awaitingQuitChoice = false
        updateSlackProjection()
    }

    private func recordLifecycleSaveResult() -> Bool {
        let saved = journalFailure == nil && settingsFailure == nil && terminationExportFailure == nil && terminationSlackFailure == nil
        if let reason = terminationExportFailure {
            lifecycleFailureMessage = "The CSV export could not be saved. \(reason) Keep Deep Work open to retry."
        } else if let reason = terminationSlackFailure {
            lifecycleFailureMessage = "Slack changes could not be saved or restored. \(reason) Keep Deep Work open to retry. Quitting can lose unsaved authorization or leave the focus status in Slack; any recovery receipt stays on this Mac."
        } else {
            lifecycleFailureMessage = saved ? nil : "Changes could not be saved. Keep Deep Work open to preserve changes that are still in memory."
        }
        return saved
    }

    private func applyTimerChange(_ records: [SessionRecord]) {
        journal.records.append(contentsOf: records)
        journal.activeCheckpoint = timer.activeCheckpoint
        persistJournal()
        updateTicker()
        updateSlackProjection()
        announceTimerChange(completedCycles: records.filter { $0.outcome == .complete }.count)
        refreshReport()
    }

    func announce(_ message: String, priority: NSAccessibilityPriorityLevel = .medium) {
        announcements.announce(message, priority: priority)
    }

    private func announceTimerChange(completedCycles: Int) {
        let current = TimerAnnouncementState(timer)
        let previous = announcedTimer
        announcedTimer = current
        if let message = current.message(after: previous, completedCycles: completedCycles,
                                         repeatExplanation: timer.repeatExplanation) {
            announce(message)
        }
    }

    func announceWindowHidden() {
        let state = timer.isActive ? (timer.isPaused ? " Your timer stays paused." : " Your timer keeps running.") : ""
        announce("Window hidden.\(state) Use the menu-bar timer to reopen Deep Work.")
    }

    func announceWindowShown(isFirstPresentation: Bool) {
        if isFirstPresentation {
            if timer.isRecovered {
                announce("Your unfinished session is paused at its last saved point. Resume when you’re ready.")
            }
            return
        }
        let state = timer.isActive ? " \(timer.phaseTitle), \(timer.countdownText) remaining." : ""
        announce("Deep Work window shown. \(selectedTab.title).\(state)")
    }

    private func updateSlackProjection() {
        guard !isTerminating, !awaitingQuitChoice else { return }
        // Recovered focus remains paused without reapplying a remote status.
        // Normal Pause retains ownership; Resume starts/reconciles it again.
        slack?.update(focusCycle: timer.state == .focus && !timer.isRecovered ? timer.phaseID : nil)
    }

    private func updateTicker() {
        let running = timer.activeCheckpoint != nil && !timer.isPaused
        if !running { ticker?.cancel(); ticker = nil; return }
        guard automaticRefresh, ticker == nil else { return }
        ticker = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                do { try await Task.sleep(for: .milliseconds(250)) } catch { return }
                guard !Task.isCancelled else { return }
                guard let self else { return }
                self.refreshTimer()
            }
        }
    }

    private func persistJournal() {
        // While a schedule candidate is being committed, coalesce newer timer
        // state in memory. Replaying an older document here could overwrite
        // either the accepted schedule or a newly finalized focus record.
        guard !isSavingSchedule else { return }
        lastCheckpointElapsed = clock.now().elapsed
        pendingJournalWrites += 1
        persistence.enqueueJournal(journal) { [weak self] failure in
            guard let self else { return }
            self.pendingJournalWrites -= 1
            self.journalFailure = failure ?? self.journalFailure
        }
    }
    private func persistSettings(savedDraftRevision: Int? = nil) {
        pendingSettingsWrites += 1
        persistence.enqueueSettings(settings) { [weak self] failure in
            guard let self else { return }
            self.pendingSettingsWrites -= 1
            self.settingsFailure = failure ?? self.settingsFailure
            if let revision = savedDraftRevision, revision == self.feedbackRevision {
                self.feedbackStatus = self.settingsFailure == nil
                    ? "Draft saved on this device. Nothing has been sent."
                    : "Draft could not be saved. Use Copy Feedback to keep it."
            }
        }
    }

    // MARK: Shared CSV export

    var canExportJournal: Bool {
        !isTerminating && !isExporting && reportSnapshot.error == nil && !reportSnapshot.rows.isEmpty
    }
    var canExportSettings: Bool {
        !isTerminating && !isExporting && ((try? exportSnapshot(for: exportScope).canExport) ?? false)
    }
    var settingsExportSummary: String {
        guard let snapshot = try? exportSnapshot(for: exportScope) else {
            return exportScope == .current ? "Choose a valid date range in Journal first." : "Your journal could not be prepared for export."
        }
        let count = snapshot.rows.count
        let countText = "\(count) \(count == 1 ? "session" : "sessions")"
        let duration = JournalDuration.format(seconds: snapshot.focusedSeconds, precise: true)
        if exportScope == .all {
            return count == 0 ? "Your journal has no sessions yet. Choose Current Journal Report to export the example."
                : "\(countText) · \(duration) of focus. Includes all of your journal history."
        }
        return "\(snapshot.isExample ? "Example data" : "Your journal") · \(countText) · \(duration) of focus in the selected Journal range."
    }

    /// Callers reconcile first when taking an export. UI availability reads the
    /// most recent observation without mutating state during view rendering.
    func exportSnapshot(for scope: ExportScope) throws -> ReportExportSnapshot {
        switch scope {
        case .current:
            return try .currentReport(reportSnapshot, isExample: showingExamples, schedule: journal.schedule,
                                      scheduleSummary: scheduleSummary, timeZone: reportingTimeZone)
        case .all:
            var records = journal.records
            if let live = timer.liveRecord, !records.contains(where: { $0.id == live.id }) { records.append(live) }
            return try .allSessions(actualRecords: records, schedule: journal.schedule,
                                    scheduleSummary: scheduleSummary, timeZone: reportingTimeZone)
        }
    }

    func exportJournalCSV() async { await exportCSV(scope: .current, fromSettings: false) }
    func exportSettingsCSV() async { await exportCSV(scope: exportScope, fromSettings: true) }

    private func exportCSV(scope: ExportScope, fromSettings: Bool) async {
        guard !isTerminating, !isExporting else { return }
        if fromSettings { settingsExportStatus = nil; settingsExportError = nil }
        else { journalExportStatus = nil; journalExportError = nil }
        // Expired phases are finalized exactly once before capturing every row.
        // The immutable snapshot is unaffected by timer ticks or save-panel delay.
        refreshReport()
        let snapshot: ReportExportSnapshot
        do { snapshot = try exportSnapshot(for: scope) }
        catch { return } // Invalid selection remains explained beside its controls.
        guard snapshot.canExport else { return }
        let revision = settingsExportRevision
        isExporting = true
        defer { isExporting = false }
        let result: CSVFileExportResult
        do {
            let bytes = try await Task.detached(priority: .userInitiated) {
                try ReportCSVExporter.data(for: snapshot)
            }.value
            guard !isTerminating, !Task.isCancelled else { return }
            result = await csvFileExporter.save(data: bytes, suggestedFilename: snapshot.filename)
        } catch { result = .failed(error.localizedDescription) }
        // A changed scope must not acquire the result of the previous selection.
        guard !fromSettings || revision == settingsExportRevision else { return }
        switch result {
        case .saved:
            if fromSettings {
                settingsExportStatus = snapshot.isExample ? "Example report exported as CSV." : "Your journal exported as CSV."
            } else { journalExportStatus = "Report exported as CSV." }
            announce("Report exported as CSV.")
        case .cancelled: break
        case .failed(let reason):
            let message = "CSV could not be saved. \(reason)"
            if fromSettings { settingsExportError = message } else { journalExportError = message }
        }
    }

    // MARK: Journal selection and immutable report snapshots

    var reportNow: Date { clock.now().wallDate }
    var reportCalendar: ReportingCalendar { ReportingCalendar(timeZone: reportingTimeZone) }
    var currentReportingDay: CivilDate {
        (try? reportCalendar.day(containing: reportNow, cutoffMinutes: journal.schedule.reportingDayStartMinutes))
            ?? CivilDate(reportNow, timeZone: reportingTimeZone)
    }
    var rangeError: String? { reportSnapshot.error }
    var visibleSessionRows: [JournalReportRow] {
        Array(reportSnapshot.rows.dropFirst(sessionPage * 12).prefix(12))
    }
    var canPreviousPage: Bool { sessionPage > 0 }
    var canNextPage: Bool { (sessionPage + 1) * 12 < reportSnapshot.rows.count }
    var pageInfo: String {
        guard !reportSnapshot.rows.isEmpty else { return "No sessions" }
        return "\(sessionPage * 12 + 1)–\(min((sessionPage + 1) * 12, reportSnapshot.rows.count)) of \(reportSnapshot.rows.count)"
    }

    private func initializeReports() {
        let calendar = reportCalendar
        if let today = try? calendar.day(containing: reportNow, cutoffMinutes: journal.schedule.reportingDayStartMinutes),
           let date = try? calendar.date(at: today, cutoffMinutes: 720) {
            reportDate = date
        }
        if let bounds = try? calendar.weekBounds(for: CivilDate(reportDate, timeZone: reportingTimeZone), schedule: journal.schedule) {
            rangeFromText = calendar.localDateTime(bounds.from)
            rangeUntilText = calendar.localDateTime(bounds.until)
        }
        do { exampleRecords = try ExampleSessions.generate(now: reportNow, calendar: calendar) }
        catch { exampleRecords = [] } // Examples are optional and never replace actual history.
        showingExamples = journal.records.isEmpty && journal.activeCheckpoint == nil
        reportsReady = true
        refreshReport()
        scheduleCalendarBoundary()
    }

    private func reportSelectionChanged() {
        guard reportsReady, !updatingReport else { return }
        sessionPage = 0
        refreshReport()
    }

    func refreshReport(force: Bool = true) {
        guard reportsReady, !updatingReport else { return }
        let instant = clock.now()
        guard force || instant.elapsed - lastReportElapsed >= 1 else { return }
        updatingReport = true
        defer { updatingReport = false }
        // Selection/activation is also an observation boundary. A delayed UI
        // tick must not leave a completed focus showing as live in a new report.
        // The guard above prevents refreshTimer's report hook from recursing.
        if force { refreshTimer() }
        lastReportElapsed = instant.elapsed
        let calendar = reportCalendar
        var from: Date?
        var until: Date?
        switch reportPeriod {
        case .range:
            from = calendar.parseLocalDateTime(rangeFromText)
            until = calendar.parseLocalDateTime(rangeUntilText)
        case .day, .week:
            let day = CivilDate(reportDate, timeZone: reportingTimeZone)
            let bounds = try? (reportPeriod == .day
                ? calendar.dayBounds(for: day, schedule: journal.schedule)
                : calendar.weekBounds(for: day, schedule: journal.schedule))
            from = bounds?.from; until = bounds?.until
        }
        var records = showingExamples ? exampleRecords : journal.records
        if !showingExamples, let live = timer.liveRecord, !records.contains(where: { $0.id == live.id }) {
            records.append(live)
        }
        let snapshot = JournalReport.build(records: records, from: from, until: until,
                                           schedule: journal.schedule, grouping: chartGrouping, calendar: calendar)
        if chartGrouping != snapshot.grouping { chartGrouping = snapshot.grouping }
        reportSnapshot = snapshot
        sessionPage = min(sessionPage, max(0, (snapshot.rows.count - 1) / 12))
    }

    func updateReportingTimeZone(_ timeZone: TimeZone) {
        guard timeZone != reportingTimeZone else { refreshReportCalendar(); return }
        // The selected date and raw range fields are civil values. Only their
        // interpretation changes; persisted absolute timestamps never do.
        let selectedDay = CivilDate(reportDate, timeZone: reportingTimeZone)
        updatingReport = true
        reportingTimeZone = timeZone
        if let date = try? reportCalendar.date(at: selectedDay, cutoffMinutes: 720) { reportDate = date }
        updatingReport = false
        refreshReportCalendar()
    }

    /// One wakeup at the next reporting boundary keeps Today and draft previews
    /// current while idle/paused, without a polling loop or an accounting tick.
    var nextReportCalendarRefresh: Date? {
        let now = reportNow
        let cutoffs = Set([journal.schedule.reportingDayStartMinutes,
                           scheduleDraft?.validatedSchedule?.reportingDayStartMinutes].compactMap { $0 })
        return cutoffs.compactMap { cutoff -> Date? in
            guard let today = try? reportCalendar.day(containing: now, cutoffMinutes: cutoff),
                  let tomorrow = try? reportCalendar.addingDays(1, to: today) else { return nil }
            return try? reportCalendar.date(at: tomorrow, cutoffMinutes: cutoff)
        }.min()
    }
    func refreshReportCalendar() {
        refreshReport()
        scheduleCalendarBoundary()
    }
    private func scheduleCalendarBoundary() {
        calendarBoundaryTask?.cancel(); calendarBoundaryTask = nil
        guard automaticRefresh, !isTerminating, let next = nextReportCalendarRefresh else { return }
        let delay = max(0.01, next.timeIntervalSince(reportNow))
        calendarBoundaryTask = Task { @MainActor [weak self] in
            do { try await Task.sleep(for: .seconds(delay)) } catch { return }
            guard !Task.isCancelled else { return }
            self?.refreshReportCalendar()
        }
    }

    var reportTitle: String {
        guard let bounds = reportSnapshot.bounds else { return "Choose a valid range" }
        func formatted(_ date: Date, _ template: String) -> String {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = reportingTimeZone
            formatter.dateFormat = template
            return formatter.string(from: date)
        }
        switch reportPeriod {
        case .range: return "\(formatted(bounds.from, "MMM d, HH:mm")) – \(formatted(bounds.until, "MMM d, HH:mm"))"
        case .day:
            let selected = CivilDate(reportDate, timeZone: reportingTimeZone)
            return (selected == currentReportingDay ? "Today · " : "") + formatted(reportDate, "EEEE, MMMM d, yyyy")
        case .week:
            let thisWeek = try? reportCalendar.weekBounds(for: currentReportingDay, schedule: journal.schedule)
            let prefix = thisWeek?.from == bounds.from ? "This week · " : ""
            let lastDay = reportSnapshot.days.last?.key
            let endDate = lastDay.flatMap { try? reportCalendar.date(at: $0, cutoffMinutes: 720) } ?? bounds.until - 1
            return prefix + "\(formatted(bounds.from, "MMM d")) – \(formatted(endDate, "MMM d, yyyy"))"
        }
    }

    func previousReport() { moveReport(by: reportPeriod == .week ? -7 : -1) }
    func nextReport() { moveReport(by: reportPeriod == .week ? 7 : 1) }
    private func moveReport(by days: Int) {
        guard !isTerminating, reportPeriod != .range,
              let day = try? reportCalendar.addingDays(days, to: CivilDate(reportDate, timeZone: reportingTimeZone)),
              let date = try? reportCalendar.date(at: day, cutoffMinutes: 720) else { return }
        reportDate = date
    }
    func showToday() {
        guard !isTerminating else { return }
        updatingReport = true
        if reportPeriod == .range { reportPeriod = .day }
        if let date = try? reportCalendar.date(at: currentReportingDay, cutoffMinutes: 720) { reportDate = date }
        updatingReport = false
        reportSelectionChanged()
    }
    func toggleExamples() {
        guard !isTerminating else { return }
        showingExamples.toggle(); reportSelectionChanged()
    }
    func showActualJournal() {
        guard !isTerminating else { return }
        showingExamples = false; reportSelectionChanged()
    }
    func showFocusFromJournal() { showActualJournal(); showFocus() }
    func openReportBucket(_ bucket: JournalBucket) {
        guard !isTerminating else { return }
        let period: ReportPeriod = reportSnapshot.grouping == .day ? .day : .week
        updatingReport = true
        reportPeriod = period
        chartGrouping = .day
        if let date = try? reportCalendar.date(at: bucket.key, cutoffMinutes: 720) { reportDate = date }
        updatingReport = false
        reportSelectionChanged()
    }
    func previousSessionPage() { if !isTerminating && canPreviousPage { sessionPage -= 1 } }
    func nextSessionPage() { if !isTerminating && canNextPage { sessionPage += 1 } }

    // MARK: Explicit schedule drafts and commit acknowledgement

    func openSchedule() {
        guard !isTerminating, !isSavingSchedule else { return }
        if scheduleDraft == nil { scheduleDraft = WorkScheduleDraft(schedule: journal.schedule) }
        scheduleControlRequested = true
        scheduleSaveError = nil
        scheduleSaveStatus = nil
        scheduleCalendarBoundary()
    }
    func consumeScheduleControlRequest() -> Bool {
        defer { scheduleControlRequested = false }
        return scheduleControlRequested
    }
    func consumeScheduleReturnFocusRequest() -> Bool {
        guard scheduleNavigationRequest > consumedScheduleNavigationRequest else { return false }
        consumedScheduleNavigationRequest = scheduleNavigationRequest
        return true
    }
    func updateScheduleDraft(_ edit: (inout WorkScheduleDraft) -> Void) {
        guard !isTerminating, !isSavingSchedule, var draft = scheduleDraft else { return }
        edit(&draft); scheduleDraft = draft; scheduleSaveError = nil; scheduleSaveStatus = nil
        scheduleCalendarBoundary()
    }
    func cancelSchedule() {
        guard !isTerminating, !isSavingSchedule else { return }
        scheduleDraft = nil; scheduleSaveError = nil; scheduleSaveStatus = nil; scheduleNavigationRequest += 1
        refreshReport()
        scheduleCalendarBoundary()
    }
    func saveSchedule() async {
        guard !isTerminating, !isSavingSchedule, let candidate = scheduleDraft?.validatedSchedule else { return }
        refreshTimer()
        isSavingSchedule = true
        scheduleSaveError = nil
        var document = journal
        document.schedule = candidate
        pendingJournalWrites += 1
        let task = Task { @MainActor [self] in
            let failure: StoreFailure? = await withCheckedContinuation { continuation in
                persistence.enqueueJournal(document) { failure in continuation.resume(returning: failure) }
            }
            pendingJournalWrites -= 1
            if let failure {
                journalFailure = failure
                scheduleSaveError = "Schedule could not be saved. Your edits remain in this window."
            } else {
                // Merge only the accepted schedule. Timer records/configuration
                // may have changed while the disk transaction was in flight.
                journal.schedule = candidate
                scheduleDraft = nil
                scheduleSaveStatus = "Work schedule saved. Reports updated."
                scheduleNavigationRequest += 1
                sessionPage = 0
            }
            isSavingSchedule = false
            persistJournal()
            refreshReport()
            scheduleCalendarBoundary()
            scheduleSaveTask = nil
        }
        scheduleSaveTask = task
        await task.value
    }

    private func clearFeedbackResult() { feedbackRevision += 1; feedbackError = nil; feedbackStatus = nil }
    private func updateCustomDuration(isFocus: Bool) {
        guard !isTerminating, let minutes = validMinutes(isFocus ? customFocusText : customBreakText) else { return }
        if isFocus { journal.configuration.customFocusMinutes = minutes }
        else { journal.configuration.customBreakMinutes = minutes }
        persistJournal()
    }
    private func validMinutes(_ text: String) -> Int? {
        guard !text.isEmpty, text.allSatisfy({ $0.isASCII && $0.isNumber }), let minutes = Int(text), (1...480).contains(minutes) else { return nil }
        return minutes
    }
}

private struct UnavailableJournalStore: JournalPersisting {
    let failure: StoreFailure
    func load() -> StoreLoad<JournalDocument> { StoreLoad(value: JournalDocument(), failure: failure) }
    func save(_ journal: JournalDocument) -> StoreFailure? { failure }
}
private struct UnavailableSettingsStore: SettingsPersisting {
    let failure: StoreFailure
    func load() -> StoreLoad<SettingsDocument> { StoreLoad(value: SettingsDocument(), failure: failure) }
    func save(_ settings: SettingsDocument) -> StoreFailure? { failure }
}
private struct UnavailableSlackStore: SlackStateStoring {
    let failure: StoreFailure
    func load() async throws -> SlackDocument { throw failure }
    func save(_ document: SlackDocument) async throws { throw failure }
}
