import AppKit
import Foundation
import Testing
import DeepWorkCore
@testable import DeepWorkApp

extension NativeApplicationTests {
@Suite(.serialized, .timeLimit(.minutes(1)))
@MainActor
struct LoginItemIntegrationTests {
    private func directory() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("DeepWorkLogin-\(UUID())")
    }

    private func model(_ directory: URL, service: (any LoginItemServicing)? = nil,
                       clock: TestTimerClock? = nil) -> AppModel {
        AppModel(journalStore: JournalStore(directory: directory), settingsStore: SettingsStore(directory: directory),
                 clock: clock ?? TestTimerClock(), automaticRefresh: false, feedbackClipboard: RecordingFeedbackClipboard(),
                 loginItemService: service)
    }

    @Test func testS003_S005StoredTrueNeverRegistersAndObservedOffReplacesStalePreference() async {
        let directory = directory(); defer { try? FileManager.default.removeItem(at: directory) }
        #expect(SettingsStore(directory: directory).save(SettingsDocument(launchAtLogin: true)) == nil)
        let service = IntegrationLoginItemService(status: .notRegistered)
        let app = model(directory, service: service)
        await app.flushPersistence()
        #expect(app.loginItemStatus == .notRegistered && !app.launchAtLoginRequested)
        #expect(!app.settings.launchAtLogin)
        #expect(!SettingsStore(directory: directory).load().value.launchAtLogin)
        #expect(service.requests.isEmpty)
    }

    @Test func testS003_S005ObservedEnabledSupersedesAbsentPreferenceWithoutRegistration() async {
        let directory = directory(); defer { try? FileManager.default.removeItem(at: directory) }
        let service = IntegrationLoginItemService(status: .enabled)
        let app = model(directory, service: service)
        await app.flushPersistence()
        #expect(app.loginItemStatus == .enabled && app.launchAtLoginRequested)
        #expect(app.settings.launchAtLogin && SettingsStore(directory: directory).load().value.launchAtLogin)
        #expect(service.requests.isEmpty && app.canChangeLoginItem)
    }

    @Test func testS003_S005MissingServiceIsUnavailableWithoutChangingStoredPreference() async {
        let directory = directory(); defer { try? FileManager.default.removeItem(at: directory) }
        #expect(SettingsStore(directory: directory).save(SettingsDocument(launchAtLogin: true)) == nil)
        let app = model(directory)
        await app.setLaunchAtLogin(false)
        app.refreshLoginItemStatus(); app.openLoginItemSettings()
        await app.flushPersistence()
        #expect(app.loginItemStatus == nil && !app.canChangeLoginItem)
        #expect(!app.launchAtLoginRequested && !app.showsLoginItemSettingsAction)
        #expect(app.loginItemStatusMessage.contains("unavailable"))
        #expect(app.settings.launchAtLogin && SettingsStore(directory: directory).load().value.launchAtLogin)
    }

    @Test func testS003_S005_AC26EnableDisablePersistsObservedStateWithoutSavingEditedFeedback() async {
        let directory = directory(); defer { try? FileManager.default.removeItem(at: directory) }
        let savedDraft = FeedbackDraft(type: .idea, email: "saved@example.com", message: "Explicitly saved draft A")
        #expect(SettingsStore(directory: directory).save(SettingsDocument(feedbackDraft: savedDraft)) == nil)
        let service = IntegrationLoginItemService(status: .notRegistered)
        let app = model(directory, service: service)
        app.feedbackType = .problem; app.feedbackEmail = "edited@example.com"; app.feedbackMessage = "Unsaved draft B"
        #expect(app.copyFeedback() == .copy)
        let feedbackStatus = app.feedbackStatus
        for enabled in [true, false] {
            await app.setLaunchAtLogin(enabled)
            await app.flushPersistence()
            let stored = SettingsStore(directory: directory).load()
            #expect(stored.failure == nil && stored.value.launchAtLogin == enabled)
            #expect(stored.value.feedbackDraft == savedDraft)
            #expect(app.feedbackType == .problem && app.feedbackEmail == "edited@example.com")
            #expect(app.feedbackMessage == "Unsaved draft B" && app.feedbackStatus == feedbackStatus)
            #expect(app.feedbackError == nil && app.loginItemError == nil)
        }
        #expect(service.requests == [true, false])
        let restored = model(directory, service: service)
        #expect(restored.feedbackMessage == savedDraft.message && restored.feedbackEmail == savedDraft.email)
        #expect(restored.feedbackType == .idea && !restored.settings.launchAtLogin)
        await restored.flushPersistence()
    }

    @Test func testS003_S005PendingApprovalShowsRequestedOnButPersistsActualDisabledAndCanUnregister() async {
        let directory = directory(); defer { try? FileManager.default.removeItem(at: directory) }
        let service = IntegrationLoginItemService(status: .notRegistered)
        service.resultingStatus = .requiresApproval
        let app = model(directory, service: service)
        await app.setLaunchAtLogin(true); await app.flushPersistence()
        #expect(app.launchAtLoginRequested && !app.settings.launchAtLogin)
        #expect(app.loginItemStatusMessage.contains("Approval required"))
        #expect(app.showsLoginItemSettingsAction && app.canChangeLoginItem)
        #expect(!SettingsStore(directory: directory).load().value.launchAtLogin)
        app.openLoginItemSettings()
        #expect(service.settingsRequests == 1 && service.requests == [true])
        service.resultingStatus = .notRegistered
        await app.setLaunchAtLogin(false); await app.flushPersistence()
        #expect(!app.launchAtLoginRequested && app.loginItemStatus == .notRegistered)
        #expect(service.requests == [true, false])
    }

    @Test func testS003_S005SettingsEntryRefreshesExternallyRevokedConsentAndRetainsEdits() async {
        let directory = directory(); defer { try? FileManager.default.removeItem(at: directory) }
        let service = IntegrationLoginItemService(status: .enabled)
        let app = model(directory, service: service)
        app.feedbackMessage = "Preserve unsaved text"
        service.status = .requiresApproval
        app.selectedTab = .settings
        await app.flushPersistence()
        #expect(app.loginItemStatus == .requiresApproval && app.launchAtLoginRequested)
        #expect(!app.settings.launchAtLogin && app.feedbackMessage == "Preserve unsaved text")
        #expect(service.requests.isEmpty)
        service.status = .enabled
        app.selectedTab = .journal; app.selectedTab = .settings
        await app.flushPersistence()
        #expect(app.settings.launchAtLogin && app.loginItemStatus == .enabled)
        #expect(SettingsStore(directory: directory).load().value.feedbackDraft == .empty)
    }

    @Test func testS003_S005NativeActivationNotificationRefreshesExternalState() async {
        prepareNativeTestApplication()
        let directory = directory(); defer { try? FileManager.default.removeItem(at: directory) }
        let service = IntegrationLoginItemService(status: .enabled)
        let app = model(directory, service: service)
        service.status = .notRegistered
        NotificationCenter.default.post(name: NSApplication.didBecomeActiveNotification, object: NSApplication.shared)
        await waitUntil { app.loginItemStatus == .notRegistered }
        await app.flushPersistence()
        #expect(!app.settings.launchAtLogin && service.requests.isEmpty)
        #expect(!SettingsStore(directory: directory).load().value.launchAtLogin)
    }

    @Test func testS003_S005RegistrationFailureRetainsActualStateAndEditedFeedbackThenRetrySucceeds() async {
        let directory = directory(); defer { try? FileManager.default.removeItem(at: directory) }
        let service = IntegrationLoginItemService(status: .notRegistered)
        service.failure = .denied
        let app = model(directory, service: service)
        app.feedbackEmail = "invalid"; app.feedbackMessage = "Unsaved failure recovery text"
        #expect(app.saveFeedbackDraft() == .email)
        await app.setLaunchAtLogin(true); await app.flushPersistence()
        #expect(!app.launchAtLoginRequested && !app.settings.launchAtLogin)
        #expect(app.loginItemError == "Launch at Login could not be changed. Test registration denied.")
        #expect(app.feedbackEmail == "invalid" && app.feedbackMessage == "Unsaved failure recovery text")
        #expect(app.feedbackError == FeedbackValidationError.email.localizedDescription)
        #expect(SettingsStore(directory: directory).load().value.feedbackDraft == .empty)
        #expect(app.canChangeLoginItem && app.showsLoginItemSettingsAction)
        service.failure = nil
        await app.setLaunchAtLogin(true); await app.flushPersistence()
        #expect(app.loginItemError == nil && app.settings.launchAtLogin)
        #expect(service.requests == [true, true])
    }

    @Test func testS003_S005UnregisterErrorKeepsSwitchOnAndObservesStatusChangedWithError() async {
        let directory = directory(); defer { try? FileManager.default.removeItem(at: directory) }
        let service = IntegrationLoginItemService(status: .enabled)
        service.failure = .denied
        let app = model(directory, service: service)
        await app.setLaunchAtLogin(false); await app.flushPersistence()
        #expect(app.launchAtLoginRequested && app.settings.launchAtLogin && app.loginItemError != nil)
        service.resultingStatus = .notRegistered
        await app.setLaunchAtLogin(false); await app.flushPersistence()
        #expect(!app.launchAtLoginRequested && !app.settings.launchAtLogin && app.loginItemError != nil)
        #expect(!SettingsStore(directory: directory).load().value.launchAtLogin)
        service.status = .enabled
        app.refreshLoginItemStatus()
        #expect(app.loginItemError == nil && app.settings.launchAtLogin)
        await app.flushPersistence()
    }

    @Test func testS003_S005UnavailableAndUnknownStatusesHaveActionableCopyWithoutSuccess() async {
        for status: LoginItemStatus in [.notFound, .unknown] {
            let directory = directory(); defer { try? FileManager.default.removeItem(at: directory) }
            let service = IntegrationLoginItemService(status: status)
            let app = model(directory, service: service)
            await app.flushPersistence()
            #expect(!app.launchAtLoginRequested && !app.settings.launchAtLogin)
            #expect(app.showsLoginItemSettingsAction)
            #expect(status == .notFound ? app.loginItemStatusMessage.contains("Applications")
                    : app.loginItemStatusMessage.contains("could not determine"))
            app.openLoginItemSettings()
            #expect(service.settingsRequests == 1 && service.requests.isEmpty)
        }
    }

    @Test func testS003_S005NotFoundOffersRegistrationRetryInsteadOfClaimingFeatureUnavailable() async {
        let directory = directory(); defer { try? FileManager.default.removeItem(at: directory) }
        let service = IntegrationLoginItemService(status: .notFound)
        let app = model(directory, service: service)
        #expect(app.canChangeLoginItem && !app.launchAtLoginRequested)
        #expect(app.loginItemStatusMessage == "macOS could not find this login item. Try enabling Launch at Login again. Keep Deep Work in Applications.")
        await app.setLaunchAtLogin(true); await app.flushPersistence()
        #expect(service.requests == [true] && app.loginItemStatus == .enabled)
        #expect(app.launchAtLoginRequested && app.loginItemError == nil)
        #expect(app.loginItemStatusMessage == "Deep Work will open when you log in to your Mac.")
        #expect(SettingsStore(directory: directory).load().value.launchAtLogin)
    }

    @Test func testS003_AC26SlowRequestKeepsTimerRunningAndRejectsOverlappingControlActions() async {
        let directory = directory(); defer { try? FileManager.default.removeItem(at: directory) }
        let service = IntegrationLoginItemService(status: .notRegistered)
        service.suspendChange = true
        let clock = TestTimerClock(); let app = model(directory, service: service, clock: clock)
        app.focusSelection.wrappedValue = .preset(60); app.breakSelection.wrappedValue = .preset(10)
        app.startFocus()
        let request = Task { @MainActor in await app.setLaunchAtLogin(true) }
        await service.waitUntilStarted()
        #expect(app.isChangingLoginItem && !app.canChangeLoginItem)
        #expect(app.loginItemStatusMessage == "Updating Launch at Login…")
        clock.advance(17); app.refreshTimer()
        #expect(!app.timer.isPaused && app.timer.liveRecord?.focusedSeconds == 17)
        app.openLoginItemSettings()
        await app.setLaunchAtLogin(false)
        #expect(service.requests == [true] && service.settingsRequests == 0)
        service.finishChange()
        await request.value; await app.flushPersistence()
        #expect(!app.isChangingLoginItem && app.canChangeLoginItem)
        #expect(app.settings.launchAtLogin && !app.timer.isPaused)
        #expect(JournalStore(directory: directory).load().value.activeCheckpoint?.remainingSeconds == 3583)
    }

    @Test func testS003_AC26FlushWaitsForPendingNativeResultAndItsSQLiteWrite() async {
        let directory = directory(); defer { try? FileManager.default.removeItem(at: directory) }
        let service = IntegrationLoginItemService(status: .notRegistered)
        service.suspendChange = true
        let app = model(directory, service: service)
        await app.flushPersistence()
        let request = Task { @MainActor in await app.setLaunchAtLogin(true) }
        await service.waitUntilStarted()
        var flushed = false
        let flush = Task { @MainActor in await app.flushPersistence(); flushed = true }
        await Task.yield()
        #expect(!flushed && !SettingsStore(directory: directory).load().value.launchAtLogin)
        service.finishChange()
        await request.value; await flush.value
        #expect(flushed && SettingsStore(directory: directory).load().value.launchAtLogin)
    }

    @Test func testS003_S018_AC26LateLoginCompletionPreservesDraftExplicitlySavedDuringRequest() async {
        let directory = directory(); defer { try? FileManager.default.removeItem(at: directory) }
        let service = IntegrationLoginItemService(status: .notRegistered)
        service.suspendChange = true
        let app = model(directory, service: service)
        let request = Task { @MainActor in await app.setLaunchAtLogin(true) }
        await service.waitUntilStarted()
        app.feedbackMessage = "New explicitly saved draft during registration"
        #expect(app.saveFeedbackDraft() == nil)
        app.feedbackMessage = "Later unsaved changes"
        service.finishChange()
        await request.value; await app.flushPersistence()
        let stored = SettingsStore(directory: directory).load().value
        #expect(stored.launchAtLogin)
        #expect(stored.feedbackDraft.message == "New explicitly saved draft during registration")
        #expect(app.feedbackMessage == "Later unsaved changes")
    }

    @Test func testS003_AC26QuitSealsTimerThenWaitsForLateLoginResultWithoutImplicitDraftSave() async {
        let directory = directory(); defer { try? FileManager.default.removeItem(at: directory) }
        let service = IntegrationLoginItemService(status: .notRegistered)
        service.suspendChange = true
        let clock = TestTimerClock(); let app = model(directory, service: service, clock: clock)
        app.feedbackMessage = "Edited but never explicitly saved"
        app.focusSelection.wrappedValue = .preset(60); app.breakSelection.wrappedValue = .preset(10)
        app.startFocus(); clock.advance(17)
        let request = Task { @MainActor in await app.setLaunchAtLogin(true) }
        await service.waitUntilStarted()
        var quitFinished = false
        let quit = Task { @MainActor in let result = await app.prepareForTermination(); quitFinished = true; return result }
        await waitUntil { app.isTerminating }
        #expect(app.timer.isPaused && !quitFinished)
        await app.setLaunchAtLogin(false); app.openLoginItemSettings()
        #expect(service.requests == [true] && service.settingsRequests == 0)
        clock.advance(90)
        service.finishChange()
        await request.value
        #expect(await quit.value)
        #expect(quitFinished && app.settings.launchAtLogin)
        let settings = SettingsStore(directory: directory).load().value
        let journal = JournalStore(directory: directory).load().value
        #expect(settings.launchAtLogin && settings.feedbackDraft == .empty)
        #expect(journal.activeCheckpoint?.remainingSeconds == 3583)
        #expect(app.feedbackMessage == "Edited but never explicitly saved")
    }

    @Test func testS003_S021StorageFailureDoesNotMisreportSuccessfulNativeRegistration() async throws {
        let directory = directory(); defer { try? FileManager.default.removeItem(at: directory) }
        try Data("unwritable directory".utf8).write(to: directory)
        let service = IntegrationLoginItemService(status: .notRegistered)
        let app = model(directory, service: service)
        app.feedbackMessage = "Retain text even when SQLite fails"
        await app.setLaunchAtLogin(true); await app.flushPersistence()
        #expect(app.settings.launchAtLogin && app.launchAtLoginRequested)
        #expect(app.loginItemError == nil && app.settingsFailure != nil)
        #expect(app.settingsStorageMessage.contains("could not be saved"))
        #expect(app.feedbackMessage == "Retain text even when SQLite fails")
        #expect(!(await app.prepareForTermination()))
        #expect(!app.isTerminating && app.canChangeLoginItem)
    }

    @Test func testS003CancellationBeforeRequestAndCompletedQuitDoNotChangeOSState() async {
        let directory = directory(); defer { try? FileManager.default.removeItem(at: directory) }
        let service = IntegrationLoginItemService(status: .notRegistered)
        let app = model(directory, service: service)
        let request = Task { @MainActor in await app.setLaunchAtLogin(true) }
        request.cancel(); await request.value
        #expect(service.requests.isEmpty && !app.isChangingLoginItem)
        #expect(await app.prepareForTermination())
        service.status = .enabled
        app.refreshLoginItemStatus(); app.openLoginItemSettings()
        await app.setLaunchAtLogin(true)
        #expect(service.requests.isEmpty && service.settingsRequests == 0)
        #expect(!app.canChangeLoginItem && app.loginItemStatus == .notRegistered)
    }

    private func waitUntil(_ condition: () -> Bool) async {
        for _ in 0..<1000 {
            if condition() { return }
            await Task.yield()
        }
        #expect(condition())
    }
}
}

@MainActor
private final class IntegrationLoginItemService: LoginItemServicing {
    var status: LoginItemStatus
    var resultingStatus: LoginItemStatus?
    var failure: IntegrationLoginItemFailure?
    var suspendChange = false
    private(set) var requests: [Bool] = []
    private(set) var settingsRequests = 0
    private var startedWaiter: CheckedContinuation<Void, Never>?
    private var changeContinuation: CheckedContinuation<Void, Never>?

    init(status: LoginItemStatus) { self.status = status }

    func setEnabled(_ enabled: Bool) async throws -> LoginItemStatus {
        requests.append(enabled)
        if suspendChange {
            await withCheckedContinuation { continuation in
                changeContinuation = continuation
                startedWaiter?.resume(); startedWaiter = nil
            }
        } else {
            startedWaiter?.resume(); startedWaiter = nil
        }
        if let resultingStatus { status = resultingStatus }
        else if failure == nil { status = enabled ? .enabled : .notRegistered }
        if let failure { throw failure }
        return status
    }

    func openSystemSettings() { settingsRequests += 1 }

    func waitUntilStarted() async {
        if !requests.isEmpty { return }
        await withCheckedContinuation { startedWaiter = $0 }
    }

    func finishChange() {
        changeContinuation?.resume(); changeContinuation = nil
    }
}

private enum IntegrationLoginItemFailure: LocalizedError {
    case denied
    var errorDescription: String? { "Test registration denied." }
}
