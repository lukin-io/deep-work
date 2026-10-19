import Foundation
import CryptoKit
import Testing
@testable import DeepWorkApp

@Suite struct SlackAuthenticationTests {
    @Test func testF027PKCERequestsOnlyUserProfileScopesAndNoSecrets() throws {
        let request = try SlackAuthorizationRequest(clientID: "123.456", randomBytes: { count in Data(repeating: 7, count: count) })
        let components = try #require(URLComponents(url: request.url, resolvingAgainstBaseURL: false))
        let query = Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).map { ($0.name, $0.value ?? "") })
        #expect(components.scheme == "https")
        #expect(components.host == "slack.com")
        #expect(components.path == "/oauth/v2/authorize")
        #expect(query["client_id"] == "123.456")
        #expect(query["scope"] == "")
        #expect(query["user_scope"] == "users.profile:read,users.profile:write")
        #expect(query["redirect_uri"] == SlackAuthorizationRequest.callback)
        #expect(query["code_challenge_method"] == "S256")
        #expect(query["code_challenge"] == SlackAuthorizationRequest.base64URL(Data(SHA256.hash(data: Data(request.verifier.utf8)))))
        #expect(request.verifier.count == 43)
        #expect(query["client_secret"] == nil)
        #expect(query["code_verifier"] == nil)
    }

    @Test func testF027RandomValuesAreIndependentAndRandomFailureStopsAuthorization() throws {
        let first = try SlackAuthorizationRequest(clientID: "123.456")
        let second = try SlackAuthorizationRequest(clientID: "123.456")
        #expect(first.verifier != first.state)
        #expect(first.verifier != second.verifier)
        #expect(first.state != second.state)
        #expect(throws: SlackClientError.serviceUnavailable) {
            try SlackAuthorizationRequest(clientID: "123.456", randomBytes: { _ in throw SlackClientError.serviceUnavailable })
        }
        #expect(throws: SlackClientError.invalidResponse) {
            try SlackAuthorizationRequest(clientID: "123.456", randomBytes: { _ in Data() })
        }
    }

    @Test func testF027CallbackRequiresExactEndpointSingleStateAndCode() throws {
        let request = try SlackAuthorizationRequest(clientID: "123.456")
        let valid = try #require(URL(string: "\(SlackAuthorizationRequest.callback)?state=\(request.state)&code=valid-code"))
        #expect(try request.authorizationCode(from: valid) == "valid-code")
        let invalid = [
            "other://slack/oauth?state=\(request.state)&code=valid",
            "app.deepwork.mac://elsewhere/oauth?state=\(request.state)&code=valid",
            "app.deepwork.mac://slack/wrong?state=\(request.state)&code=valid",
            "app.deepwork.mac://user@slack/oauth?state=\(request.state)&code=valid",
            "app.deepwork.mac://slack:8080/oauth?state=\(request.state)&code=valid",
            "\(SlackAuthorizationRequest.callback)?state=wrong&code=valid",
            "\(SlackAuthorizationRequest.callback)?state=\(request.state)&state=\(request.state)&code=valid",
            "\(SlackAuthorizationRequest.callback)?state=\(request.state)&code=a&code=b",
            "\(SlackAuthorizationRequest.callback)?state=\(request.state)&code=",
            "\(SlackAuthorizationRequest.callback)?state=\(request.state)&code=a%0Ab",
            "\(SlackAuthorizationRequest.callback)?state=\(request.state)&code=valid#fragment",
            "\(SlackAuthorizationRequest.callback)?code=valid"
        ]
        for string in invalid {
            let callback = try #require(URL(string: string))
            #expect(throws: SlackClientError.invalidResponse) { try request.authorizationCode(from: callback) }
        }
    }

    @Test func testF027DenialIsCancellationOnlyWithMatchingStateAndNoCode() throws {
        let request = try SlackAuthorizationRequest(clientID: "123.456")
        let denial = try #require(URL(string: "\(SlackAuthorizationRequest.callback)?state=\(request.state)&error=access_denied"))
        #expect(throws: SlackClientError.cancelled) { try request.authorizationCode(from: denial) }
        for suffix in ["state=wrong&error=access_denied", "state=\(request.state)&error=unexpected", "state=\(request.state)&error=access_denied&code=code"] {
            let callback = try #require(URL(string: "\(SlackAuthorizationRequest.callback)?\(suffix)"))
            #expect(throws: SlackClientError.invalidResponse) { try request.authorizationCode(from: callback) }
        }
    }

    @Test func testF027ClientIDValidationRejectsPlaceholdersAndTokenValidationRejectsBotsAndWhitespace() {
        #expect(NativeSlackClient.validClientID("123.456"))
        for value in ["", "YOUR_CLIENT_ID", "123", "123.", ".456", "123.456.7", " 123.456", "１２３.４５６"] {
            #expect(!NativeSlackClient.validClientID(value))
        }
        #expect(NativeSlackClient.validAccessToken("xoxe.xoxp-fixture-access"))
        #expect(!NativeSlackClient.validAccessToken("xoxe.xoxb-fixture-access"))
        #expect(!NativeSlackClient.validAccessToken("xoxp-long-lived-fixture"))
        #expect(!NativeSlackClient.validAccessToken("xoxe.xoxp-fixture\naccess"))
        #expect(NativeSlackClient.validRefreshToken("xoxe-fixture-refresh"))
        #expect(!NativeSlackClient.validRefreshToken("xoxe-short"))
    }

    @Test func testF027DebugAcceptanceCredentialsAreIsolatedFromPersonalKeychainWithoutGlobalEnvironmentChanges() {
        let canonical = NativeSlackClient.defaultCredentialService(environment: [:])
        #expect(canonical == "app.deepwork.mac.slack")
        #expect(NativeSlackClient.defaultCredentialService(environment: ["DEEP_WORK_DATA_DIR": ""]) == canonical)
        let first = NativeSlackClient.defaultCredentialService(environment: ["DEEP_WORK_DATA_DIR": "/tmp/slack-fixture-a"])
        let same = NativeSlackClient.defaultCredentialService(environment: ["DEEP_WORK_DATA_DIR": "/tmp/other/../slack-fixture-a"])
        let second = NativeSlackClient.defaultCredentialService(environment: ["DEEP_WORK_DATA_DIR": "/tmp/slack-fixture-b"])
        #if DEBUG
        #expect(first != canonical)
        #expect(first == same)
        #expect(first != second)
        #expect(!first.contains("slack-fixture-a"))
        #else
        #expect(first == canonical)
        #expect(same == canonical)
        #expect(second == canonical)
        #endif
    }
}
