import Foundation
import Testing
import DeepWorkCore
@testable import DeepWorkApp

extension NativeApplicationTests {
@Suite(.serialized) @MainActor struct SlackClientTests {
    private let date = Date(timeIntervalSince1970: 1_000_000)
    private let account = SlackAccount(workspaceID: "T1", userID: "U1", workspaceName: "Fixture", userName: "tester")

    @Test func testF027UnconfiguredBuildDoesNotOpenAuthenticationOrSendNetworkRequests() async throws {
        let auth = FixtureSlackAuthentication()
        let transport = FixtureSlackTransport([])
        let client = NativeSlackClient(clientID: "", authentication: auth, transport: transport, credentials: FixtureSlackVault())
        #expect(!client.isConfigured)
        await #expect(throws: SlackClientError.notConfigured) { try await client.connect() }
        #expect(auth.requests.isEmpty)
        #expect(await transport.requests.isEmpty)
        #expect(try await client.loadAccount() == nil)
    }

    @Test func testF027ConnectUsesPKCEValidatesIdentityAndAtomicallyStoresUserCredentials() async throws {
        let transport = FixtureSlackTransport([oauthResponse(), identityResponse()])
        let auth = FixtureSlackAuthentication()
        let vault = FixtureSlackVault()
        let now = date
        let client = NativeSlackClient(clientID: "123.456", authentication: auth, transport: transport, credentials: vault, now: { now })
        #expect(client.isConfigured)
        #expect(try await client.connect() == account)
        let requests = await transport.requests
        #expect(requests.count == 2)
        let exchange = String(decoding: try #require(requests.first?.httpBody), as: UTF8.self)
        #expect(exchange.contains("code_verifier="))
        #expect(exchange.contains("code=fixture-code"))
        #expect(!exchange.contains("client_secret"))
        #expect(requests[1].value(forHTTPHeaderField: "Authorization") == "Bearer xoxe.xoxp-fixture-access")
        let data = try #require(await vault.data)
        let stored = try JSONDecoder().decode(SlackStoredCredentials.self, from: data)
        #expect(stored.account == account)
        #expect(stored.expiresAt == date.addingTimeInterval(43_200))
        #expect(stored.refreshToken == "xoxe-fixture-refresh")
        #expect(await vault.saves == 1)
        #expect(try await client.loadAccount() == account)
    }

    @Test func testF027DeniedOrForgedAuthorizationNeverExchangesCodeOrStoresCredentials() async throws {
        for kind in [FixtureSlackAuthentication.Callback.denied, .forged] {
            let auth = FixtureSlackAuthentication(callback: kind)
            let transport = FixtureSlackTransport([])
            let vault = FixtureSlackVault()
            let client = NativeSlackClient(clientID: "123.456", authentication: auth, transport: transport, credentials: vault)
            await #expect(throws: kind == .denied ? SlackClientError.cancelled : .invalidResponse) { try await client.connect() }
            #expect(await transport.requests.isEmpty)
            #expect(await vault.data == nil)
        }
    }

    @Test func testF027MissingScopesMalformedTokensOrDifferentIdentityCannotConnect() async throws {
        let cases: [(SlackHTTPResponse, SlackHTTPResponse?, SlackClientError)] = [
            (oauthResponse(scope: "users.profile:read"), nil, .missingScopes),
            (oauthResponse(access: "xoxe.xoxb-fixture-access"), nil, .invalidResponse),
            (oauthResponse(refresh: ""), nil, .invalidResponse),
            (oauthResponse(lifetime: 0), nil, .invalidResponse),
            (oauthResponse(), identityResponse(userID: "OTHER"), .invalidResponse),
            (response("{\"ok\":true}"), nil, .invalidResponse)
        ]
        for (oauth, identity, error) in cases {
            let transport = FixtureSlackTransport([oauth] + (identity.map { [$0] } ?? []))
            let vault = FixtureSlackVault()
            let client = NativeSlackClient(clientID: "123.456", authentication: FixtureSlackAuthentication(), transport: transport, credentials: vault)
            await #expect(throws: error) { try await client.connect() }
            #expect(await vault.data == nil)
        }
    }

    @Test func testF027KeychainFailureNeverReportsConnectedAndRetainsOldStoredPayload() async throws {
        let original = try credentialsData()
        let vault = FixtureSlackVault(data: original, failingSaves: 1)
        let client = NativeSlackClient(clientID: "123.456", authentication: FixtureSlackAuthentication(),
            transport: FixtureSlackTransport([oauthResponse(), identityResponse()]), credentials: vault)
        await #expect(throws: SlackClientError.keychainFailure) { try await client.connect() }
        #expect(await vault.data == original)
    }

    @Test func testF027PendingRestorationRejectsDifferentAccountBeforeReplacingKeychain() async throws {
        let original = try credentialsData()
        let vault = FixtureSlackVault(data: original)
        let client = NativeSlackClient(clientID: "123.456", authentication: FixtureSlackAuthentication(),
            transport: FixtureSlackTransport([oauthResponse(), identityResponse()]), credentials: vault)
        let expected = SlackAccount(workspaceID: "ORIGINAL", userID: "U1", workspaceName: "Original", userName: "tester")
        await #expect(throws: SlackClientError.differentAccount) { try await client.connect(expectedAccount: expected) }
        #expect(await vault.data == original)
        #expect(await vault.saves == 0)
    }

    @Test func testF027PendingRestorationAcceptsSameIdentityWithRenamedWorkspace() async throws {
        let vault = FixtureSlackVault()
        let client = NativeSlackClient(clientID: "123.456", authentication: FixtureSlackAuthentication(),
            transport: FixtureSlackTransport([oauthResponse(), identityResponse()]), credentials: vault)
        let expected = SlackAccount(workspaceID: "T1", userID: "U1", workspaceName: "Old name", userName: "Old name")
        #expect(try await client.connect(expectedAccount: expected) == account)
        #expect(await vault.saves == 1)
    }

    @Test func testF028GetAndSetUseExactProfileAndNoTokenInURL() async throws {
        let transport = FixtureSlackTransport([profileResponse(), profileResponse()])
        let client = try client(transport: transport)
        #expect(try await client.profile() == .focus)
        try await client.setProfile(.focus)
        let requests = await transport.requests
        #expect(requests.map { $0.url?.path } == ["/api/users.profile.get", "/api/users.profile.set"])
        #expect(requests.allSatisfy { $0.url?.query == nil })
        let payload = try JSONSerialization.jsonObject(with: #require(requests[1].httpBody)) as? [String: [String: Any]]
        #expect(payload?["profile"]?["status_text"] as? String == "Deep WORK, DND")
        #expect(payload?["profile"]?["status_emoji"] as? String == ":x:")
        #expect(payload?["profile"]?["status_expiration"] as? Int == 0)
        #expect(requests.allSatisfy { $0.timeoutInterval == 15 })
    }

    @Test func testF028MissingProfileFieldsAndUnconfirmedSetFailWithoutSuccess() async throws {
        let missing = response("{\"ok\":true,\"profile\":{\"status_text\":\"\",\"status_emoji\":\"\"}}")
        let client = try client(transport: FixtureSlackTransport([missing, profileResponse(text: "Changed elsewhere")]))
        await #expect(throws: SlackClientError.invalidResponse) { try await client.profile() }
        await #expect(throws: SlackClientError.invalidResponse) { try await client.setProfile(.focus) }
    }

    @Test func testF028RefreshUsesNewestTokenAndCommitsBeforeProfileRequest() async throws {
        let vault = FixtureSlackVault(data: try credentialsData(expiresAt: date))
        let transport = FixtureSlackTransport([refreshResponse(), profileResponse(), profileResponse()])
        let client = try client(transport: transport, vault: vault)
        _ = try await client.profile()
        _ = try await client.profile()
        let requests = await transport.requests
        #expect(requests.count == 3)
        let form = String(decoding: try #require(requests[0].httpBody), as: UTF8.self)
        #expect(form.contains("grant_type=refresh_token"))
        #expect(form.contains("refresh_token=xoxe-fixture-refresh"))
        #expect(!form.contains("client_secret"))
        #expect(!form.contains("code_verifier"))
        #expect(requests[1].value(forHTTPHeaderField: "Authorization") == "Bearer xoxe.xoxp-new-access")
        let stored = try JSONDecoder().decode(SlackStoredCredentials.self, from: #require(await vault.data))
        #expect(stored.refreshToken == "xoxe-new-refresh-token")
        #expect(await vault.saves == 1)
    }

    @Test func testF028FailedRotatedCredentialCommitRetriesCommitWithoutReusingConsumedRefresh() async throws {
        let vault = FixtureSlackVault(data: try credentialsData(expiresAt: date), failingSaves: 1)
        let transport = FixtureSlackTransport([refreshResponse(), profileResponse()])
        let client = try client(transport: transport, vault: vault)
        await #expect(throws: SlackClientError.keychainFailure) { try await client.profile() }
        #expect(await transport.requests.count == 1)
        _ = try await client.profile()
        #expect(await transport.requests.count == 2)
        #expect(await vault.saves == 2)
        let data = try #require(await vault.data)
        #expect(try JSONDecoder().decode(SlackStoredCredentials.self, from: data).refreshToken == "xoxe-new-refresh-token")
    }

    @Test func testF028QuitFlushRetainsUncommittedRotationAfterFailureAndRetriesWithoutNetwork() async throws {
        let original = try credentialsData(expiresAt: date)
        let vault = FixtureSlackVault(data: original, failingSaves: 2)
        let transport = FixtureSlackTransport([refreshResponse()])
        let client = try client(transport: transport, vault: vault)
        await #expect(throws: SlackClientError.keychainFailure) { try await client.profile() }
        #expect(await transport.requests.count == 1)
        #expect(await vault.data == original)
        await #expect(throws: SlackClientError.keychainFailure) { try await client.flushCredentials() }
        #expect(await vault.data == original)
        #expect(await transport.requests.count == 1)
        try await client.flushCredentials()
        let data = try #require(await vault.data)
        #expect(try JSONDecoder().decode(SlackStoredCredentials.self, from: data).refreshToken == "xoxe-new-refresh-token")
        #expect(await vault.saves == 3)
        #expect(await transport.requests.count == 1)
        try await client.flushCredentials()
        #expect(await vault.saves == 3)
    }

    @Test func testF027QuitWithoutPendingCredentialsDoesNotReadKeychainOrUseNetwork() async throws {
        let vault = FixtureSlackVault(data: Data("unreadable existing item".utf8))
        let transport = FixtureSlackTransport([])
        let client = NativeSlackClient(clientID: nil, authentication: FixtureSlackAuthentication(), transport: transport, credentials: vault)
        try await client.flushCredentials()
        #expect(await vault.loads == 0)
        #expect(await vault.saves == 0)
        #expect(await transport.requests.isEmpty)
    }

    @Test func testF029ExpiredRefreshOrRevokedGrantRequiresReconnectAndPreservesVault() async throws {
        for code in ["invalid_refresh_token", "invalid_auth", "token_revoked", "token_expired", "invalid_grant"] {
            let original = try credentialsData(expiresAt: date)
            let vault = FixtureSlackVault(data: original)
            let transport = FixtureSlackTransport([response("{\"ok\":false,\"error\":\"\(code)\"}")])
            let client = try client(transport: transport, vault: vault)
            await #expect(throws: SlackClientError.reconnectRequired) { try await client.profile() }
            #expect(await vault.data == original)
        }
    }

    @Test func testF029RateLimitHonorsRetryAfterWithoutImmediateNetworkRetry() async throws {
        let transport = FixtureSlackTransport([SlackHTTPResponse(data: Data(), statusCode: 429, retryAfter: "45")])
        let client = try client(transport: transport)
        await #expect(throws: SlackClientError.rateLimited(45)) { try await client.profile() }
        await #expect(throws: SlackClientError.rateLimited(45)) { try await client.profile() }
        #expect(await transport.requests.count == 1)
    }

    @Test func testF029MalformedRetryAfterUsesBoundedDefaultAndServerErrorsAreRedacted() async throws {
        for header in [nil, "not-seconds", "-1", "nan"] as [String?] {
            let client = try client(transport: FixtureSlackTransport([SlackHTTPResponse(data: Data(), statusCode: 429, retryAfter: header)]))
            await #expect(throws: SlackClientError.rateLimited(60)) { try await client.profile() }
        }
        for status in [301, 401, 500] {
            let client = try client(transport: FixtureSlackTransport([SlackHTTPResponse(data: Data("private diagnostic".utf8), statusCode: status, retryAfter: nil)]))
            await #expect(throws: SlackClientError.serviceUnavailable) { try await client.profile() }
        }
        #expect(!SlackClientError.serviceUnavailable.localizedDescription.contains("private"))
    }

    @Test func testF029OfflineMalformedAndAPIErrorBodiesNeverMasqueradeAsSuccess() async throws {
        let offline = try client(transport: FixtureSlackTransport([]))
        await #expect(throws: SlackClientError.networkFailure) { try await offline.profile() }
        for json in ["not json", "{}", "{\"ok\":true,\"profile\":null}", "{\"ok\":true,\"profile\":{\"status_text\":\"\",\"status_emoji\":\"\",\"status_expiration\":-1}}"] {
            let malformed = try client(transport: FixtureSlackTransport([response(json)]))
            await #expect(throws: SlackClientError.invalidResponse) { try await malformed.profile() }
        }
        let denied = try client(transport: FixtureSlackTransport([response("{\"ok\":false,\"error\":\"missing_scope\"}")]))
        await #expect(throws: SlackClientError.missingScopes) { try await denied.profile() }
        let transport = FixtureSlackTransport([response("{\"ok\":false,\"error\":\"ratelimited\"}")])
        let limited = try client(transport: transport)
        await #expect(throws: SlackClientError.rateLimited(60)) { try await limited.profile() }
        await #expect(throws: SlackClientError.rateLimited(60)) { try await limited.profile() }
        #expect(await transport.requests.count == 1)
    }

    @Test func testF027DisconnectDeletesOnlyAfterVaultSuccessAndMalformedCredentialsAreNotOverwritten() async throws {
        let data = try credentialsData()
        let vault = FixtureSlackVault(data: data)
        let client = try client(transport: FixtureSlackTransport([]), vault: vault)
        #expect(try await client.loadAccount() == account)
        await vault.setFailDelete(true)
        await #expect(throws: SlackClientError.keychainFailure) { try await client.disconnect() }
        #expect(try await client.loadAccount() == account)
        await vault.setFailDelete(false)
        try await client.disconnect()
        #expect(try await client.loadAccount() == nil)
        #expect(await vault.data == nil)
        let malformed = FixtureSlackVault(data: Data("unreadable".utf8))
        let damaged = try self.client(transport: FixtureSlackTransport([]), vault: malformed)
        await #expect(throws: SlackClientError.reconnectRequired) { try await damaged.loadAccount() }
        #expect(await malformed.data == Data("unreadable".utf8))
    }

    @Test func testF027ConcurrentAuthorizationIsRejectedAndQuitCancellationFinishesOnce() async throws {
        let auth = FixtureSlackAuthentication(callback: .wait)
        let transport = FixtureSlackTransport([])
        let client = NativeSlackClient(clientID: "123.456", authentication: auth, transport: transport, credentials: FixtureSlackVault())
        let pending = Task { try await client.connect() }
        while auth.requests.isEmpty { await Task.yield() }
        await #expect(throws: SlackClientError.authorizationInProgress) { try await client.connect() }
        client.cancelAuthorization()
        await #expect(throws: SlackClientError.cancelled) { try await pending.value }
        #expect(auth.cancellations == 1)
        #expect(await transport.requests.isEmpty)
    }

    @Test func testF027NativeKeychainUsesAnIsolatedItemForAtomicReplacementAndDeletion() async throws {
        let vault = KeychainSlackCredentialStore(service: "app.deepwork.mac.tests.\(UUID().uuidString)")
        #expect(try await vault.load() == nil)
        do {
            try await vault.save(Data("nonsecret fixture 1".utf8))
            #expect(try await vault.load() == Data("nonsecret fixture 1".utf8))
            try await vault.save(Data("nonsecret fixture 2".utf8))
            #expect(try await vault.load() == Data("nonsecret fixture 2".utf8))
            try await vault.delete()
            #expect(try await vault.load() == nil)
            try await vault.delete()
        } catch {
            try? await vault.delete()
            throw error
        }
    }

    private func client(transport: FixtureSlackTransport, vault: FixtureSlackVault? = nil) throws -> NativeSlackClient {
        let now = date
        return NativeSlackClient(clientID: "123.456", authentication: FixtureSlackAuthentication(), transport: transport,
            credentials: try vault ?? FixtureSlackVault(data: credentialsData()), now: { now })
    }

    private func credentialsData(expiresAt: Date? = nil) throws -> Data {
        try JSONEncoder().encode(SlackStoredCredentials(version: 1, clientID: "123.456", account: account,
            accessToken: "xoxe.xoxp-fixture-access", refreshToken: "xoxe-fixture-refresh",
            expiresAt: expiresAt ?? date.addingTimeInterval(43_200), scopes: SlackAuthorizationRequest.requiredScopes))
    }

    private func response(_ json: String) -> SlackHTTPResponse { SlackHTTPResponse(data: Data(json.utf8), statusCode: 200, retryAfter: nil) }
    private func oauthResponse(scope: String = "users.profile:read,users.profile:write", access: String = "xoxe.xoxp-fixture-access",
        refresh: String = "xoxe-fixture-refresh", lifetime: Int = 43_200) -> SlackHTTPResponse {
        response("{\"ok\":true,\"authed_user\":{\"id\":\"U1\",\"access_token\":\"\(access)\",\"refresh_token\":\"\(refresh)\",\"expires_in\":\(lifetime),\"token_type\":\"user\",\"scope\":\"\(scope)\"},\"team\":{\"id\":\"T1\",\"name\":\"Fixture\"}}")
    }
    private func identityResponse(userID: String = "U1") -> SlackHTTPResponse {
        response("{\"ok\":true,\"user_id\":\"\(userID)\",\"team_id\":\"T1\",\"team\":\"Fixture\",\"user\":\"tester\"}")
    }
    private func refreshResponse() -> SlackHTTPResponse {
        response("{\"ok\":true,\"access_token\":\"xoxe.xoxp-new-access\",\"refresh_token\":\"xoxe-new-refresh-token\",\"expires_in\":43200,\"token_type\":\"user\",\"scope\":\"users.profile:read,users.profile:write\"}")
    }
    private func profileResponse(text: String = "Deep WORK, DND") -> SlackHTTPResponse {
        response("{\"ok\":true,\"profile\":{\"status_text\":\"\(text)\",\"status_emoji\":\":x:\",\"status_expiration\":0}}")
    }
}
}

@MainActor private final class FixtureSlackAuthentication: SlackAuthenticating {
    enum Callback { case success, denied, forged, wait }
    let callback: Callback
    var requests: [URL] = []
    var cancellations = 0
    private var continuation: CheckedContinuation<URL, Error>?
    init(callback: Callback = .success) { self.callback = callback }
    func authorize(url: URL, callbackScheme: String) async throws -> URL {
        requests.append(url)
        if callback == .wait { return try await withCheckedThrowingContinuation { continuation = $0 } }
        let state = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "state" }?.value ?? ""
        let result = callback == .denied ? "error=access_denied" : "code=fixture-code"
        return try #require(URL(string: "\(SlackAuthorizationRequest.callback)?state=\(callback == .forged ? "forged" : state)&\(result)"))
    }
    func cancel() {
        cancellations += 1
        let pending = continuation
        continuation = nil
        pending?.resume(throwing: SlackClientError.cancelled)
    }
}

private actor FixtureSlackTransport: SlackHTTPTransport {
    var requests: [URLRequest] = []
    var responses: [SlackHTTPResponse]
    init(_ responses: [SlackHTTPResponse]) { self.responses = responses }
    func send(_ request: URLRequest) async throws -> SlackHTTPResponse {
        requests.append(request)
        guard !responses.isEmpty else { throw URLError(.notConnectedToInternet) }
        return responses.removeFirst()
    }
}

private actor FixtureSlackVault: SlackCredentialStoring {
    var data: Data?
    var saves = 0
    var loads = 0
    private var failingSaves: Int
    private var failDelete = false
    init(data: Data? = nil, failingSaves: Int = 0) { self.data = data; self.failingSaves = failingSaves }
    func load() -> Data? { loads += 1; return data }
    func save(_ data: Data) throws {
        saves += 1
        if failingSaves > 0 { failingSaves -= 1; throw SlackClientError.keychainFailure }
        self.data = data
    }
    func delete() throws {
        if failDelete { throw SlackClientError.keychainFailure }
        data = nil
    }
    func setFailDelete(_ fail: Bool) { failDelete = fail }
}
