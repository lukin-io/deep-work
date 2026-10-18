import Foundation
import SwiftUI
import DeepWorkCore

enum ReportPeriod: String, CaseIterable { case day = "Day", week = "Week", range = "Range" }
enum ExportScope { case all, current }
enum FeedbackField { case email, message }

/// The sole mutable owner of app data; views never create stores or sessions.
@MainActor
final class AppModel: ObservableObject {
    @Published var selectedTab: AppTab = .journal
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
    private let journalStore: JournalPersisting
    private let settingsStore: SettingsPersisting

    init(journalStore: JournalPersisting, settingsStore: SettingsPersisting) {
        self.journalStore = journalStore; self.settingsStore = settingsStore
        let journalLoad = journalStore.load()
        let settingsLoad = settingsStore.load()
        journal = journalLoad.value; settings = settingsLoad.value
        journalFailure = journalLoad.failure; settingsFailure = settingsLoad.failure
        customFocusText = String(journalLoad.value.configuration.customFocusMinutes)
        customBreakText = String(journalLoad.value.configuration.customBreakMinutes)
        feedbackType = settingsLoad.value.feedbackDraft.type
        feedbackEmail = settingsLoad.value.feedbackDraft.email
        feedbackMessage = settingsLoad.value.feedbackDraft.message
        // Prove writes work before displaying "saved" even on a first launch.
        // Stores protect unreadable/unsupported files from fallback writes.
        persistCommittedState()
    }

    static func live() -> AppModel {
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
            return AppModel(journalStore: JournalStore(directory: directory, legacyDirectory: legacyDirectory),
                            settingsStore: SettingsStore(directory: directory, legacyDirectory: legacyDirectory))
        } catch {
            let failure = StoreFailure(operation: .read, fileURL: URL(fileURLWithPath: NSHomeDirectory()),
                                       reason: "Application Support is unavailable: \(error.localizedDescription)")
            return AppModel(journalStore: UnavailableJournalStore(failure: failure), settingsStore: UnavailableSettingsStore(failure: failure))
        }
    }

    var focusSelection: Binding<DurationSelection> {
        Binding(get: { self.journal.configuration.focusSelection }, set: { self.journal.configuration.focusSelection = $0; self.persistJournal() })
    }
    var breakSelection: Binding<DurationSelection> {
        Binding(get: { self.journal.configuration.breakSelection }, set: { self.journal.configuration.breakSelection = $0; self.persistJournal() })
    }
    var repeats: Binding<Bool> {
        Binding(get: { self.journal.configuration.repeats }, set: { self.journal.configuration.repeats = $0; self.persistJournal() })
    }
    var configurationError: String? {
        if journal.configuration.focusSelection == .custom && validMinutes(customFocusText) == nil { return "Enter whole minutes from 1 to 480." }
        if journal.configuration.breakSelection == .custom && validMinutes(customBreakText) == nil { return "Enter whole minutes from 1 to 480." }
        return nil
    }
    var repeatExplanation: String {
        journal.configuration.repeats ? "Deep work, then break. Repeat until unchecked." : "One deep work cycle and one break, then stop."
    }

    var journalStorageMessage: String {
        journalFailure == nil ? "Saved on this device" : "Saving unavailable. Changes last only while the app is open. CSV export is not available yet."
    }
    var settingsStorageMessage: String {
        settingsFailure == nil ? "Settings saved on this device" : "Settings could not be saved. They last only while the app is open."
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
        let candidate = FeedbackDraft(type: feedbackType, email: feedbackEmail, message: feedbackMessage)
        do {
            settings.feedbackDraft = try candidate.validatedForSaving()
            settingsFailure = settingsStore.save(settings) ?? settingsFailure
            feedbackError = nil
            feedbackStatus = settingsFailure == nil
                ? "Draft saved on this device. Nothing has been sent."
                : "Draft could not be saved. Your edits remain in this window."
            return nil
        } catch {
            feedbackStatus = nil
            feedbackError = error.localizedDescription
            return error.localizedDescription.hasPrefix("Enter a valid email") ? .email : .message
        }
    }

    func persistCommittedState() {
        persistJournal()
        settingsFailure = settingsStore.save(settings) ?? settingsFailure
    }
    private func persistJournal() { journalFailure = journalStore.save(journal) ?? journalFailure }
    private func clearFeedbackResult() { feedbackError = nil; feedbackStatus = nil }
    private func updateCustomDuration(isFocus: Bool) {
        guard let minutes = validMinutes(isFocus ? customFocusText : customBreakText) else { return }
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
