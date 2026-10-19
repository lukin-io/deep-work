import Foundation
import CryptoKit
import DeepWorkCore

@MainActor
protocol SlackClientServing {
    var isConfigured: Bool { get }
    func loadAccount() async throws -> SlackAccount?
    func connect() async throws -> SlackAccount
    func connect(expectedAccount: SlackAccount?) async throws -> SlackAccount
    func profile() async throws -> SlackProfile
    func setProfile(_ profile: SlackProfile) async throws
    func disconnect() async throws
    func flushCredentials() async throws
    func cancelAuthorization()
}

extension SlackClientServing {
    func cancelAuthorization() {}
    func flushCredentials() async throws {}
    func connect(expectedAccount: SlackAccount?) async throws -> SlackAccount { try await connect() }
}

enum SlackClientError: Error, LocalizedError, Equatable, Sendable {
    case notConfigured, cancelled, authorizationInProgress, reconnectRequired
    case missingScopes, invalidResponse, networkFailure, serviceUnavailable, keychainFailure, differentAccount
    case rateLimited(TimeInterval)

    var errorDescription: String? {
        switch self {
        case .notConfigured: return "Slack is not configured in this build. Follow the Slack setup guide."
        case .cancelled: return "Slack connection was cancelled."
        case .authorizationInProgress: return "A Slack operation is already in progress."
        case .reconnectRequired: return "Reconnect Slack to authorize status updates."
        case .missingScopes: return "Slack did not grant the required profile permissions. Reconnect after approving both permissions."
        case .invalidResponse: return "Slack returned an unexpected response. Your timer is still available."
        case .networkFailure: return "Slack could not be reached. Check your connection and retry."
        case .serviceUnavailable: return "Slack is unavailable. Try again later."
        case .keychainFailure: return "Slack credentials could not be saved or read in Keychain. Unlock your login keychain and retry."
        case .differentAccount: return "Reconnect the original Slack account so its previous status can be restored."
        case .rateLimited: return "Slack is limiting requests. Wait before retrying."
        }
    }
}

struct SlackHTTPResponse: Sendable {
    let data: Data
    let statusCode: Int
    let retryAfter: String?
}

protocol SlackHTTPTransport: Sendable {
    func send(_ request: URLRequest) async throws -> SlackHTTPResponse
}

struct URLSessionSlackHTTPTransport: SlackHTTPTransport {
    private let session: URLSession

    init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 15
        configuration.timeoutIntervalForResource = 20
        configuration.httpCookieStorage = nil
        configuration.urlCredentialStorage = nil
        configuration.urlCache = nil
        session = URLSession(configuration: configuration, delegate: SlackRedirectRefuser(), delegateQueue: nil)
    }

    func send(_ request: URLRequest) async throws -> SlackHTTPResponse {
        let (data, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse else { throw SlackClientError.invalidResponse }
        return SlackHTTPResponse(data: data, statusCode: response.statusCode,
                                 retryAfter: response.value(forHTTPHeaderField: "Retry-After"))
    }
}

/// Never forward bearer credentials or OAuth form data to a redirect target.
private final class SlackRedirectRefuser: NSObject, URLSessionTaskDelegate, Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
                    completionHandler: @escaping @Sendable (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}

struct SlackStoredCredentials: Codable, Sendable {
    let version: Int
    let clientID: String
    let account: SlackAccount
    let accessToken: String
    let refreshToken: String
    let expiresAt: Date
    let scopes: Set<String>

    func validate() throws {
        guard version == 1, NativeSlackClient.validClientID(clientID),
              !account.workspaceID.isEmpty, !account.userID.isEmpty,
              NativeSlackClient.validAccessToken(accessToken),
              NativeSlackClient.validRefreshToken(refreshToken),
              expiresAt.timeIntervalSince1970.isFinite,
              SlackAuthorizationRequest.requiredScopes.isSubset(of: scopes) else {
            throw SlackClientError.reconnectRequired
        }
    }
}

/// MainActor owns connection state. The coordinator serializes its calls; the
/// guard also rejects accidental reentrancy so a refresh token is used once.
@MainActor
final class NativeSlackClient: SlackClientServing {
    private let clientID: String?
    private let authentication: any SlackAuthenticating
    private let transport: any SlackHTTPTransport
    private let vault: any SlackCredentialStoring
    private let now: @Sendable () -> Date
    private var stored: SlackStoredCredentials?
    private var didLoad = false
    private var isOperating = false
    private var authorizationRevision = 0
    private var retryAfter: Date?

    var isConfigured: Bool { clientID.map(Self.validClientID) ?? false }

    init(clientID: String? = Bundle.main.object(forInfoDictionaryKey: "DeepWorkSlackClientID") as? String,
         authentication: (any SlackAuthenticating)? = nil,
         transport: any SlackHTTPTransport = URLSessionSlackHTTPTransport(),
         credentials: (any SlackCredentialStoring)? = nil,
         now: @escaping @Sendable () -> Date = { Date() }) {
        self.clientID = clientID?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.authentication = authentication ?? NativeSlackAuthentication()
        self.transport = transport
        vault = credentials ?? KeychainSlackCredentialStore(service: Self.defaultCredentialService())
        self.now = now
    }

    func loadAccount() async throws -> SlackAccount? {
        try beginOperation()
        defer { isOperating = false }
        try await loadCredentials()
        return stored?.account
    }

    func connect() async throws -> SlackAccount {
        try await connect(expectedAccount: nil)
    }

    func connect(expectedAccount: SlackAccount?) async throws -> SlackAccount {
        try beginOperation()
        defer { isOperating = false }
        guard isConfigured, let clientID else { throw SlackClientError.notConfigured }
        let revision = authorizationRevision
        let authorization = try SlackAuthorizationRequest(clientID: clientID)
        let callback = try await authentication.authorize(url: authorization.url, callbackScheme: SlackAuthorizationRequest.callbackScheme)
        try checkAuthorization(revision)
        let code = try authorization.authorizationCode(from: callback)
        let response: SlackOAuthResponse = try await request(method: "oauth.v2.access", form: [
            "client_id": clientID, "code": code, "code_verifier": authorization.verifier,
            "redirect_uri": SlackAuthorizationRequest.callback
        ])
        try checkAuthorization(revision)
        guard let user = response.authedUser, let userID = user.id,
              let team = response.team, let workspaceID = team.id,
              let access = user.accessToken, let refresh = user.refreshToken,
              let lifetime = user.expiresIn, let scope = user.scope,
              user.tokenType == nil || user.tokenType == "user" else { throw SlackClientError.invalidResponse }
        let scopes = Self.parseScopes(scope)
        try Self.validateGrant(access: access, refresh: refresh, lifetime: lifetime, scopes: scopes)
        let identity: SlackIdentityResponse = try await request(method: "auth.test", token: access)
        try checkAuthorization(revision)
        guard identity.userID == userID, identity.teamID == workspaceID,
              !userID.isEmpty, !workspaceID.isEmpty else { throw SlackClientError.invalidResponse }
        let account = SlackAccount(workspaceID: workspaceID, userID: userID,
                                   workspaceName: identity.team ?? team.name ?? workspaceID,
                                   userName: identity.user ?? userID)
        if let expectedAccount, !account.matches(expectedAccount) { throw SlackClientError.differentAccount }
        let credentials = SlackStoredCredentials(version: 1, clientID: clientID, account: account,
            accessToken: access, refreshToken: refresh, expiresAt: now().addingTimeInterval(lifetime), scopes: scopes)
        try await persist(credentials)
        // A cancellation during the atomic Keychain write must not silently
        // discard a grant that is already durable. The caller can reconcile it.
        didLoad = true
        return account
    }

    func profile() async throws -> SlackProfile {
        try beginOperation()
        defer { isOperating = false }
        let token = try await accessToken()
        let response: SlackProfileResponse = try await request(method: "users.profile.get", token: token)
        return try response.validatedProfile()
    }

    func setProfile(_ profile: SlackProfile) async throws {
        try beginOperation()
        defer { isOperating = false }
        guard profile.expiration >= 0, profile.text.count <= 100 else { throw SlackClientError.invalidResponse }
        let token = try await accessToken()
        let body = try JSONEncoder().encode(SlackProfileRequest(profile: SlackAPIProfile(profile)))
        let response: SlackProfileResponse = try await request(method: "users.profile.set", token: token, json: body)
        guard try response.validatedProfile() == profile else { throw SlackClientError.invalidResponse }
    }

    func disconnect() async throws {
        try beginOperation()
        defer { isOperating = false }
        do { try await vault.delete() }
        catch { throw SlackClientError.keychainFailure }
        stored = nil
        didLoad = true
        credentialCommitPending = false
    }

    /// Quit drains a rotated pair even when no remote status was acquired.
    /// With no pending commit this performs no Keychain read or network work.
    func flushCredentials() async throws {
        try beginOperation()
        defer { isOperating = false }
        try await commitPendingCredentials()
    }

    func cancelAuthorization() {
        authorizationRevision += 1
        authentication.cancel()
    }

    nonisolated static func validClientID(_ value: String) -> Bool {
        let parts = value.split(separator: ".", omittingEmptySubsequences: false)
        return parts.count == 2 && parts.allSatisfy { !$0.isEmpty && $0.allSatisfy { $0.isASCII && $0.isNumber } }
    }

    nonisolated static func defaultCredentialService(environment: [String: String] = ProcessInfo.processInfo.environment) -> String {
        let canonical = "app.deepwork.mac.slack"
        #if DEBUG
        if let directory = environment["DEEP_WORK_DATA_DIR"], !directory.isEmpty {
            let path = URL(fileURLWithPath: directory, isDirectory: true).standardizedFileURL.path
            let digest = SHA256.hash(data: Data(path.utf8)).map { String(format: "%02x", $0) }.joined()
            return canonical + ".debug." + digest
        }
        #endif
        return canonical
    }

    nonisolated static func validAccessToken(_ value: String) -> Bool {
        value.hasPrefix("xoxe.xoxp-") && validTokenText(value)
    }

    nonisolated static func validRefreshToken(_ value: String) -> Bool {
        value.hasPrefix("xoxe-") && validTokenText(value)
    }

    private nonisolated static func validTokenText(_ value: String) -> Bool {
        value.utf8.count > 12 && value.utf8.count <= 4096 && value.unicodeScalars.allSatisfy {
            $0.isASCII && !CharacterSet.whitespacesAndNewlines.contains($0) && !CharacterSet.controlCharacters.contains($0)
        }
    }

    private func beginOperation() throws {
        try Task.checkCancellation()
        guard !isOperating else { throw SlackClientError.authorizationInProgress }
        isOperating = true
    }

    private func checkAuthorization(_ revision: Int) throws {
        try Task.checkCancellation()
        guard revision == authorizationRevision else { throw SlackClientError.cancelled }
    }

    private func loadCredentials() async throws {
        guard !didLoad else { return }
        let data: Data?
        do { data = try await vault.load() }
        catch { throw SlackClientError.keychainFailure }
        if let data {
            do {
                let decoded = try JSONDecoder().decode(SlackStoredCredentials.self, from: data)
                try decoded.validate()
                stored = decoded
            } catch { throw SlackClientError.reconnectRequired }
        }
        didLoad = true
    }

    private func persist(_ credentials: SlackStoredCredentials) async throws {
        try credentials.validate()
        let data = try JSONEncoder().encode(credentials)
        do { try await vault.save(data) }
        catch { throw SlackClientError.keychainFailure }
        stored = credentials
    }

    private func accessToken() async throws -> String {
        try await loadCredentials()
        guard let current = stored else { throw SlackClientError.reconnectRequired }
        if current.expiresAt.timeIntervalSince(now()) > 60 { return current.accessToken }
        let response: SlackOAuthResponse = try await request(method: "oauth.v2.access", form: [
            "client_id": current.clientID, "grant_type": "refresh_token", "refresh_token": current.refreshToken
        ])
        guard let access = response.accessToken, let refresh = response.refreshToken,
              let lifetime = response.expiresIn, response.tokenType == "user", let scope = response.scope else {
            throw SlackClientError.invalidResponse
        }
        let scopes = Self.parseScopes(scope)
        try Self.validateGrant(access: access, refresh: refresh, lifetime: lifetime, scopes: scopes)
        let refreshed = SlackStoredCredentials(version: 1, clientID: current.clientID, account: current.account,
            accessToken: access, refreshToken: refresh, expiresAt: now().addingTimeInterval(lifetime), scopes: scopes)
        do { try await persist(refreshed) }
        catch {
            // The old refresh token may already be consumed. Retain the fresh
            // pair in memory and retry its Keychain commit before any API use.
            stored = refreshed
            credentialCommitPending = true
            throw error
        }
        return refreshed.accessToken
    }

    private var credentialCommitPending = false

    private func commitPendingCredentials() async throws {
        guard credentialCommitPending, let stored else { return }
        try await persist(stored)
        credentialCommitPending = false
    }

    private func request<Response: Decodable>(method: String, token: String? = nil,
        form: [String: String]? = nil, json: Data? = nil) async throws -> Response {
        try Task.checkCancellation()
        try await commitPendingCredentials()
        if let retryAfter, retryAfter > now() { throw SlackClientError.rateLimited(retryAfter.timeIntervalSince(now())) }
        guard let url = URL(string: "https://slack.com/api/\(method)") else { throw SlackClientError.invalidResponse }
        var request = URLRequest(url: url, timeoutInterval: 15)
        request.httpMethod = "POST"
        request.cachePolicy = .reloadIgnoringLocalCacheData
        if let token { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        if let form {
            let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-._~"))
            request.httpBody = form.keys.sorted().map { key in
                let name = key.addingPercentEncoding(withAllowedCharacters: allowed) ?? ""
                let value = (form[key] ?? "").addingPercentEncoding(withAllowedCharacters: allowed) ?? ""
                return "\(name)=\(value)"
            }.joined(separator: "&").data(using: .utf8)
            request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        } else if let json {
            request.httpBody = json
            request.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
        }
        let response: SlackHTTPResponse
        do { response = try await transport.send(request) }
        catch is CancellationError { throw CancellationError() }
        catch let error as URLError where error.code == .cancelled { throw CancellationError() }
        catch let error as SlackClientError { throw error }
        catch { throw SlackClientError.networkFailure }
        try Task.checkCancellation()
        if response.statusCode == 429 {
            let seconds = response.retryAfter.flatMap(TimeInterval.init).flatMap { $0.isFinite && $0 > 0 ? $0 : nil } ?? 60
            retryAfter = now().addingTimeInterval(seconds)
            throw SlackClientError.rateLimited(seconds)
        }
        guard (200..<300).contains(response.statusCode) else { throw SlackClientError.serviceUnavailable }
        guard response.data.count <= 1_048_576 else { throw SlackClientError.invalidResponse }
        do {
            let envelope = try JSONDecoder().decode(SlackAPIEnvelope.self, from: response.data)
            guard envelope.ok else {
                let error = Self.apiError(envelope.error)
                if case .rateLimited(let seconds) = error { retryAfter = now().addingTimeInterval(seconds) }
                throw error
            }
            return try JSONDecoder().decode(Response.self, from: response.data)
        } catch let error as SlackClientError { throw error }
        catch { throw SlackClientError.invalidResponse }
    }

    private nonisolated static func parseScopes(_ value: String) -> Set<String> {
        Set(value.split(whereSeparator: { $0 == "," || $0 == " " }).map(String.init))
    }

    private nonisolated static func validateGrant(access: String, refresh: String, lifetime: Double, scopes: Set<String>) throws {
        guard validAccessToken(access), validRefreshToken(refresh), lifetime.isFinite, lifetime > 60, lifetime <= 86_400 else {
            throw SlackClientError.invalidResponse
        }
        guard SlackAuthorizationRequest.requiredScopes.isSubset(of: scopes) else { throw SlackClientError.missingScopes }
    }

    private nonisolated static func apiError(_ code: String?) -> SlackClientError {
        switch code {
        case "invalid_auth", "token_expired", "token_revoked", "account_inactive", "invalid_refresh_token", "invalid_grant":
            return .reconnectRequired
        case "missing_scope", "not_allowed_token_type", "no_permission": return .missingScopes
        case "ratelimited": return .rateLimited(60)
        default: return .serviceUnavailable
        }
    }
}

private struct SlackAPIEnvelope: Decodable { let ok: Bool; let error: String? }
private struct SlackOAuthResponse: Decodable {
    let accessToken: String?
    let refreshToken: String?
    let expiresIn: Double?
    let tokenType: String?
    let scope: String?
    let authedUser: User?
    let team: Team?
    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token", refreshToken = "refresh_token", expiresIn = "expires_in"
        case tokenType = "token_type", scope, authedUser = "authed_user", team
    }
    struct User: Decodable {
        let id: String?
        let accessToken: String?
        let refreshToken: String?
        let expiresIn: Double?
        let tokenType: String?
        let scope: String?
        enum CodingKeys: String, CodingKey {
            case id, accessToken = "access_token", refreshToken = "refresh_token", expiresIn = "expires_in"
            case tokenType = "token_type", scope
        }
    }
    struct Team: Decodable { let id: String?; let name: String? }
}
private struct SlackIdentityResponse: Decodable {
    let userID: String?
    let teamID: String?
    let user: String?
    let team: String?
    enum CodingKeys: String, CodingKey { case userID = "user_id", teamID = "team_id", user, team }
}
private struct SlackAPIProfile: Codable {
    let statusText: String
    let statusEmoji: String
    let statusExpiration: Int
    enum CodingKeys: String, CodingKey {
        case statusText = "status_text", statusEmoji = "status_emoji", statusExpiration = "status_expiration"
    }
    init(_ profile: SlackProfile) {
        statusText = profile.text; statusEmoji = profile.emoji; statusExpiration = profile.expiration
    }
}
private struct SlackProfileRequest: Encodable { let profile: SlackAPIProfile }
private struct SlackProfileResponse: Decodable {
    let profile: SlackAPIProfile
    func validatedProfile() throws -> SlackProfile {
        guard profile.statusExpiration >= 0, profile.statusText.count <= 100 else { throw SlackClientError.invalidResponse }
        return SlackProfile(text: profile.statusText, emoji: profile.statusEmoji, expiration: profile.statusExpiration)
    }
}
