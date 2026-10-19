import Foundation
import ServiceManagement

/// A saved preference cannot establish whether macOS will launch the app.
/// Requires approval also covers consent revoked in System Settings.
enum LoginItemStatus: Equatable, Sendable {
    case notRegistered
    case enabled
    case requiresApproval
    case notFound
    case unknown

    var isEnabled: Bool { self == .enabled }

    init(_ status: SMAppService.Status) {
        switch status {
        case .notRegistered: self = .notRegistered
        case .enabled: self = .enabled
        case .requiresApproval: self = .requiresApproval
        case .notFound: self = .notFound
        @unknown default: self = .unknown
        }
    }
}

@MainActor
protocol LoginItemServicing {
    var status: LoginItemStatus { get }
    func setEnabled(_ enabled: Bool) async throws -> LoginItemStatus
    func openSystemSettings()
}

/// The boundary is injectable so tests never change the person's login items.
@MainActor
protocol LoginItemPlatformOperating {
    var status: LoginItemStatus { get }
    func register() async throws
    func unregister() async throws
    func openSystemSettings()
}

@MainActor
final class NativeLoginItemService: LoginItemServicing {
    private let platform: any LoginItemPlatformOperating
    private var isChanging = false

    init(platform: (any LoginItemPlatformOperating)? = nil) {
        self.platform = platform ?? NativeLoginItemPlatform()
    }

    var status: LoginItemStatus { platform.status }

    func setEnabled(_ enabled: Bool) async throws -> LoginItemStatus {
        try Task.checkCancellation()
        guard !isChanging else { throw LoginItemServiceError.operationInProgress }
        let previousStatus = status
        // Registering an approved or pending service again is an error. A
        // revoked consent must be restored by the person in System Settings.
        if enabled && (previousStatus == .enabled || previousStatus == .requiresApproval) {
            return previousStatus
        }
        if !enabled && previousStatus == .notRegistered { return previousStatus }

        isChanging = true
        defer { isChanging = false }
        if enabled {
            try await platform.register()
        } else {
            try await platform.unregister()
        }
        // Once requested, observe the result even if the caller was cancelled.
        // Neither a request nor an error proves the operating system's state.
        return status
    }

    func openSystemSettings() { platform.openSystemSettings() }
}

enum LoginItemServiceError: LocalizedError, Equatable {
    case operationInProgress

    var errorDescription: String? {
        "A Launch at Login change is still in progress. Try again when it finishes."
    }
}

@MainActor
private final class NativeLoginItemPlatform: LoginItemPlatformOperating {
    var status: LoginItemStatus { LoginItemStatus(SMAppService.mainApp.status) }

    func register() async throws {
        // Registration is a synchronous native API. Do not block UI or timer
        // refreshes while ServiceManagement processes the request. Construct
        // the native object on that queue rather than transfer it across actors.
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    try SMAppService.mainApp.register()
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    func unregister() async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
            SMAppService.mainApp.unregister { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }
    }

    func openSystemSettings() { SMAppService.openSystemSettingsLoginItems() }
}
