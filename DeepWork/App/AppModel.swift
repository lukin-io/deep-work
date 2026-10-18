import Foundation
import SwiftUI
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
            refreshTimer()
            persistJournal()
        }
    }
    @Published private(set) var journal: JournalDocument
    @Published private(set) var settings: SettingsDocument
    @Published private(set) var journalFailure: StoreFailure?
    @Published private(set) var settingsFailure: StoreFailure?
    @Published var reportPeriod: ReportPeriod = .week
    @Published var reportDate = Date()
    @Published var scheduleDraft: WorkSchedule?
    @Published var exportScope: ExportScope = .all
    @Published var customFocusText: String { didSet { updateCustomDuration(isFocus: true) } }
    @Published var customBreakText: String { didSet { updateCustomDuration(isFocus: false) } }
    @Published var feedbackType: FeedbackType { didSet { clearFeedbackResult() } }
    @Published var feedbackEmail: String { didSet { clearFeedbackResult() } }
    @Published var feedbackMessage: String { didSet { clearFeedbackResult() } }
    @Published private(set) var feedbackError: String?
    @Published private(set) var feedbackStatus: String?
    @Published private(set) var isTerminating = false
    @Published private(set) var timer: TimerEngine
    @Published private(set) var pendingJournalWrites = 0
    @Published private(set) var pendingSettingsWrites = 0
    @Published private(set) var focusRequest = 0
    private let persistence: PersistenceWorker
    private let clock: any TimerClock
    private let automaticRefresh: Bool
    private let ownershipLock: StoreOwnershipLock?
    private var ticker: Task<Void, Never>?
    private var lastCheckpointElapsed: TimeInterval
    private var feedbackRevision = 0
    private var focusControlRequested = false

    init(journalStore: JournalPersisting, settingsStore: SettingsPersisting,
         clock: (any TimerClock)? = nil, automaticRefresh: Bool = true,
         ownershipLock: StoreOwnershipLock? = nil) {
        self.clock = clock ?? ContinuousTimerClock()
        self.automaticRefresh = automaticRefresh
        self.ownershipLock = ownershipLock
        let instant = self.clock.now()
        lastCheckpointElapsed = instant.elapsed
        let journalLoad = journalStore.load()
        let settingsLoad = settingsStore.load()
        journal = journalLoad.value; settings = settingsLoad.value
        journalFailure = journalLoad.failure; settingsFailure = settingsLoad.failure
        // Store validation already rejects malformed checkpoints. Keep recovery
        // defensive at this boundary without silently turning corrupt data into history.
        if let checkpoint = journalLoad.value.activeCheckpoint {
            do { timer = try TimerEngine(checkpoint: checkpoint, repeats: journalLoad.value.configuration.repeats, at: instant) }
            catch {
                timer = TimerEngine(repeats: journalLoad.value.configuration.repeats)
                journalFailure = StoreFailure(operation: .validation, fileURL: URL(fileURLWithPath: JournalStore.filename),
                                              reason: error.localizedDescription)
            }
        } else { timer = TimerEngine(repeats: journalLoad.value.configuration.repeats) }
        persistence = PersistenceWorker(journalStore: journalStore, settingsStore: settingsStore)
        customFocusText = String(journalLoad.value.configuration.customFocusMinutes)
        customBreakText = String(journalLoad.value.configuration.customBreakMinutes)
        feedbackType = settingsLoad.value.feedbackDraft.type
        feedbackEmail = settingsLoad.value.feedbackDraft.email
        feedbackMessage = settingsLoad.value.feedbackDraft.message
        // Prove writes work before displaying "saved" even on a first launch.
        // Stores protect unreadable/unsupported files from fallback writes.
        persistCommittedState()
    }

    static func live() throws -> AppModel {
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
                            settingsStore: SettingsStore(directory: directory, legacyDirectory: legacyDirectory), ownershipLock: ownership)
        } catch StoreOwnershipError.alreadyOwned {
            throw StoreOwnershipError.alreadyOwned
        } catch {
            let failure = StoreFailure(operation: .read, fileURL: URL(fileURLWithPath: NSHomeDirectory()),
                                       reason: "Application Support is unavailable: \(error.localizedDescription)")
            return AppModel(journalStore: UnavailableJournalStore(failure: failure), settingsStore: UnavailableSettingsStore(failure: failure))
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
        if journalFailure != nil { return "Saving unavailable. Changes last only while the app is open. CSV export is not available yet." }
        return pendingJournalWrites > 0 ? "Saving on this device…" : "Saved on this device"
    }
    var settingsStorageMessage: String {
        if settingsFailure != nil { return "Settings could not be saved. They last only while the app is open." }
        return pendingSettingsWrites > 0 ? "Saving settings on this device…" : "Settings saved on this device"
    }
    var scheduleSummary: String {
        let schedule = journal.schedule
        let pattern: String
        switch schedule.mode {
        case .anyDay: pattern = "Any day"
        case .rotatingShifts: pattern = "\(schedule.workDays) work / \(schedule.restDays) rest"
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
        let candidate = FeedbackDraft(type: feedbackType, email: feedbackEmail, message: feedbackMessage)
        do {
            settings.feedbackDraft = try candidate.validatedForSaving()
            feedbackError = nil
            feedbackStatus = settingsFailure == nil ? "Saving draft…" : "Draft could not be saved. Your edits remain in this window."
            persistSettings(savedDraftRevision: feedbackRevision)
            return nil
        } catch {
            feedbackStatus = nil
            feedbackError = error.localizedDescription
            return error.localizedDescription.hasPrefix("Enter a valid email") ? .email : .message
        }
    }

    func startFocus() {
        guard canStart else { return } // Revalidate raw editing text, not only last valid persisted values.
        do { applyTimerChange(try timer.start(configuration: journal.configuration, at: clock.now())) }
        catch { return } // Validation prevents mutation; inline field errors explain invalid inputs.
    }
    func pauseTimer() { guard !isTerminating else { return }; applyTimerChange(timer.pause(at: clock.now())) }
    func resumeTimer() { guard !isTerminating else { return }; applyTimerChange(timer.resume(at: clock.now())) }
    func restartTimer() { guard !isTerminating else { return }; applyTimerChange(timer.restart(at: clock.now())) }
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

    func flushPersistence() async { await persistence.flush() }

    /// Seal at the Quit request, drain all queued transactions and their results,
    /// then let AppKit terminate. A crash can restore only the last committed seal.
    func prepareForTermination() async {
        guard !isTerminating else { await flushPersistence(); return }
        isTerminating = true
        applyTimerChange(timer.pause(at: clock.now()))
        ticker?.cancel(); ticker = nil
        persistSettings()
        await flushPersistence()
    }

    private func applyTimerChange(_ records: [SessionRecord]) {
        journal.records.append(contentsOf: records)
        journal.activeCheckpoint = timer.activeCheckpoint
        persistJournal()
        updateTicker()
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
                    : "Draft could not be saved. Your edits remain in this window."
            }
        }
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
