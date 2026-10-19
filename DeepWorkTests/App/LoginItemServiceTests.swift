import Foundation
import ServiceManagement
import Testing
@testable import DeepWorkApp

extension NativeApplicationTests {
@Suite(.serialized, .timeLimit(.minutes(1)))
@MainActor
struct LoginItemServiceTests {
    @Test func testS003_S005MapsAllNativeStatesWithoutTreatingApprovalAsEnabled() {
        #expect(LoginItemStatus(.notRegistered) == .notRegistered)
        #expect(LoginItemStatus(.enabled) == .enabled)
        #expect(LoginItemStatus(.requiresApproval) == .requiresApproval)
        #expect(LoginItemStatus(.notFound) == .notFound)
        #expect(LoginItemStatus.enabled.isEnabled)
        for status: LoginItemStatus in [.notRegistered, .requiresApproval, .notFound, .unknown] {
            #expect(!status.isEnabled)
        }
    }

    @Test func testS003_S005UnknownFutureNativeStateDoesNotClaimEnabled() throws {
        let unknown = try #require(SMAppService.Status(rawValue: 999))
        #expect(LoginItemStatus(unknown) == .unknown)
        #expect(!LoginItemStatus(unknown).isEnabled)
    }

    @Test func testS003_S005ReadOnlyNativeStatusSmokeDoesNotRequestRegistration() {
        // This reads the hostless test process's real status only. It does not
        // register, unregister, launch Settings, or prove actual login behavior.
        let service = NativeLoginItemService()
        #expect(service.status == LoginItemStatus(SMAppService.mainApp.status))
    }

    @Test func testS003_AC26RegisterReturnsObservedEnabledState() async throws {
        for initialStatus: LoginItemStatus in [.notRegistered, .notFound] {
            let platform = FixtureLoginItemPlatform(status: initialStatus)
            platform.resultingStatus = .enabled
            let service = NativeLoginItemService(platform: platform)
            #expect(try await service.setEnabled(true) == .enabled)
            #expect(platform.registerCalls == 1)
            #expect(platform.unregisterCalls == 0)
            #expect(service.status == .enabled)
        }
    }

    @Test func testS003_S005RegistrationNeedingApprovalDoesNotClaimEnabled() async throws {
        let platform = FixtureLoginItemPlatform(status: .notRegistered)
        platform.resultingStatus = .requiresApproval
        let service = NativeLoginItemService(platform: platform)
        #expect(try await service.setEnabled(true) == .requiresApproval)
        #expect(!service.status.isEnabled)
        #expect(platform.registerCalls == 1)
        #expect(platform.settingsCalls == 0)
    }

    @Test func testS003_S005CompletedRequestWithoutRegistrationNeverFabricatesSuccess() async throws {
        let platform = FixtureLoginItemPlatform(status: .notRegistered)
        let service = NativeLoginItemService(platform: platform)
        #expect(try await service.setEnabled(true) == .notRegistered)
        #expect(!service.status.isEnabled)
        #expect(platform.registerCalls == 1)
    }

    @Test func testS003_S005AlreadyEnabledOrAwaitingApprovalDoesNotRegisterAgain() async throws {
        for status: LoginItemStatus in [.enabled, .requiresApproval] {
            let platform = FixtureLoginItemPlatform(status: status)
            let service = NativeLoginItemService(platform: platform)
            #expect(try await service.setEnabled(true) == status)
            #expect(platform.registerCalls == 0 && platform.unregisterCalls == 0)
            #expect(platform.settingsCalls == 0)
        }
    }

    @Test func testS003_AC26DisableUnregistersEnabledAndPendingApprovalServices() async throws {
        for status: LoginItemStatus in [.enabled, .requiresApproval] {
            let platform = FixtureLoginItemPlatform(status: status)
            platform.resultingStatus = .notRegistered
            let service = NativeLoginItemService(platform: platform)
            #expect(try await service.setEnabled(false) == .notRegistered)
            #expect(platform.unregisterCalls == 1 && platform.registerCalls == 0)
        }
    }

    @Test func testS003AlreadyUnregisteredDoesNotRequestRemovalAgain() async throws {
        let platform = FixtureLoginItemPlatform(status: .notRegistered)
        let service = NativeLoginItemService(platform: platform)
        #expect(try await service.setEnabled(false) == .notRegistered)
        #expect(platform.unregisterCalls == 0 && platform.registerCalls == 0)
    }

    @Test func testS003_S005ExternalRevocationAndRestorationAreReadWithoutMutation() {
        let platform = FixtureLoginItemPlatform(status: .enabled)
        let service = NativeLoginItemService(platform: platform)
        #expect(service.status == .enabled)
        platform.status = .requiresApproval
        #expect(service.status == .requiresApproval && !service.status.isEnabled)
        platform.status = .notRegistered
        #expect(service.status == .notRegistered)
        platform.status = .enabled
        #expect(service.status.isEnabled)
        #expect(platform.registerCalls == 0 && platform.unregisterCalls == 0)
    }

    @Test func testS003_S005UnavailableOrUnknownServiceStatusIsPreservedAfterRequest() async throws {
        for status: LoginItemStatus in [.notFound, .unknown] {
            let platform = FixtureLoginItemPlatform(status: status)
            let service = NativeLoginItemService(platform: platform)
            #expect(try await service.setEnabled(true) == status)
            #expect(try await service.setEnabled(false) == status)
            #expect(!service.status.isEnabled)
            #expect(platform.registerCalls == 1 && platform.unregisterCalls == 1)
        }
    }

    @Test func testS003_S005RegistrationErrorIsPreservedAndRetryCanSucceed() async throws {
        let platform = FixtureLoginItemPlatform(status: .notRegistered)
        platform.failure = .registration
        let service = NativeLoginItemService(platform: platform)
        await #expect(throws: FixtureLoginItemFailure.registration) { try await service.setEnabled(true) }
        #expect(service.status == .notRegistered)
        platform.failure = nil
        platform.resultingStatus = .enabled
        #expect(try await service.setEnabled(true) == .enabled)
        #expect(platform.registerCalls == 2)
    }

    @Test func testS003_S005UnregisterFailureKeepsActualEnabledStateAndAllowsRetry() async throws {
        let platform = FixtureLoginItemPlatform(status: .enabled)
        platform.failure = .removal
        let service = NativeLoginItemService(platform: platform)
        await #expect(throws: FixtureLoginItemFailure.removal) { try await service.setEnabled(false) }
        #expect(service.status == .enabled)
        platform.failure = nil
        platform.resultingStatus = .notRegistered
        #expect(try await service.setEnabled(false) == .notRegistered)
        #expect(platform.unregisterCalls == 2)
    }

    @Test func testS003_S005ErrorDoesNotMaskAnObservedSystemStateChange() async {
        let platform = FixtureLoginItemPlatform(status: .notRegistered)
        platform.failure = .registration
        platform.resultingStatus = .requiresApproval
        let service = NativeLoginItemService(platform: platform)
        await #expect(throws: FixtureLoginItemFailure.registration) { try await service.setEnabled(true) }
        #expect(service.status == .requiresApproval)
    }

    @Test func testS003_S005OpenSettingsIsExplicitAndDoesNotChangeRegistration() {
        let platform = FixtureLoginItemPlatform(status: .requiresApproval)
        let service = NativeLoginItemService(platform: platform)
        service.openSystemSettings()
        #expect(platform.settingsCalls == 1)
        #expect(platform.registerCalls == 0 && platform.unregisterCalls == 0)
        #expect(service.status == .requiresApproval)
    }

    @Test func testS003_AC26SuspendedRegistrationKeepsMainActorAvailableAndRejectsOverlap() async throws {
        let platform = FixtureLoginItemPlatform(status: .notRegistered)
        platform.suspendChange = true
        platform.resultingStatus = .enabled
        let service = NativeLoginItemService(platform: platform)
        var finished = false
        let request = Task { @MainActor in
            let status = try await service.setEnabled(true)
            finished = true
            return status
        }
        await platform.waitUntilStarted()
        #expect(!finished && service.status == .notRegistered)
        await #expect(throws: LoginItemServiceError.operationInProgress) {
            try await service.setEnabled(false)
        }
        #expect(platform.unregisterCalls == 0)
        platform.finishChange()
        #expect(try await request.value == .enabled)
        #expect(finished)
    }

    @Test func testS003_AC26UnregisterWaitsForNativeCompletionBeforeReturningObservedStatus() async throws {
        let platform = FixtureLoginItemPlatform(status: .enabled)
        platform.suspendChange = true
        platform.resultingStatus = .notRegistered
        let service = NativeLoginItemService(platform: platform)
        let request = Task { @MainActor in try await service.setEnabled(false) }
        await platform.waitUntilStarted()
        #expect(service.status == .enabled)
        platform.finishChange()
        #expect(try await request.value == .notRegistered)
    }

    @Test func testS003CancelledRequestBeforeStartDoesNotChangeLoginItems() async {
        let platform = FixtureLoginItemPlatform(status: .notRegistered)
        let service = NativeLoginItemService(platform: platform)
        let request = Task { @MainActor in try await service.setEnabled(true) }
        request.cancel()
        await #expect(throws: CancellationError.self) { try await request.value }
        #expect(platform.registerCalls == 0 && platform.unregisterCalls == 0)
    }

    @Test func testS003CancellationAfterRequestStillReturnsTheActualRegistrationResult() async throws {
        let platform = FixtureLoginItemPlatform(status: .notRegistered)
        platform.suspendChange = true
        platform.resultingStatus = .enabled
        let service = NativeLoginItemService(platform: platform)
        let request = Task { @MainActor in try await service.setEnabled(true) }
        await platform.waitUntilStarted()
        request.cancel()
        platform.finishChange()
        #expect(try await request.value == .enabled)
        #expect(service.status == .enabled && platform.registerCalls == 1)
    }
}
}

private enum FixtureLoginItemFailure: Error, Equatable {
    case registration
    case removal
}

@MainActor
private final class FixtureLoginItemPlatform: LoginItemPlatformOperating {
    var status: LoginItemStatus
    var resultingStatus: LoginItemStatus?
    var failure: FixtureLoginItemFailure?
    var suspendChange = false
    private(set) var registerCalls = 0
    private(set) var unregisterCalls = 0
    private(set) var settingsCalls = 0
    private var startedWaiter: CheckedContinuation<Void, Never>?
    private var changeContinuation: CheckedContinuation<Void, Never>?

    init(status: LoginItemStatus) { self.status = status }

    func register() async throws {
        registerCalls += 1
        try await change()
    }

    func unregister() async throws {
        unregisterCalls += 1
        try await change()
    }

    func openSystemSettings() { settingsCalls += 1 }

    func waitUntilStarted() async {
        if registerCalls > 0 || unregisterCalls > 0 { return }
        await withCheckedContinuation { startedWaiter = $0 }
    }

    func finishChange() {
        changeContinuation?.resume()
        changeContinuation = nil
    }

    private func change() async throws {
        if suspendChange {
            await withCheckedContinuation { continuation in
                changeContinuation = continuation
                startedWaiter?.resume()
                startedWaiter = nil
            }
        } else {
            startedWaiter?.resume()
            startedWaiter = nil
        }
        if let resultingStatus { status = resultingStatus }
        if let failure { throw failure }
    }
}
