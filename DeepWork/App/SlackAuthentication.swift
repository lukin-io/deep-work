import AppKit
import AuthenticationServices
import CryptoKit
import Foundation
import Security

@MainActor
protocol SlackAuthenticating {
    func authorize(url: URL, callbackScheme: String) async throws -> URL
    func cancel()
}

/// The verifier never leaves memory except in the TLS code exchange. A callback
/// is accepted only for this attempt, exact endpoint and cryptographic state.
struct SlackAuthorizationRequest: Sendable {
    static let callback = "app.deepwork.mac://slack/oauth"
    static let callbackScheme = "app.deepwork.mac"
    static let requiredScopes: Set<String> = ["users.profile:read", "users.profile:write"]
    let verifier: String
    let state: String
    let url: URL

    init(clientID: String, randomBytes: (Int) throws -> Data = Self.secureRandomBytes) throws {
        let verifierBytes = try randomBytes(32)
        let stateBytes = try randomBytes(32)
        guard verifierBytes.count == 32, stateBytes.count == 32 else { throw SlackClientError.invalidResponse }
        verifier = Self.base64URL(verifierBytes)
        state = Self.base64URL(stateBytes)
        let challenge = Self.base64URL(Data(SHA256.hash(data: Data(verifier.utf8))))
        var components = URLComponents(string: "https://slack.com/oauth/v2/authorize")
        components?.queryItems = [
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "scope", value: ""),
            URLQueryItem(name: "user_scope", value: Self.requiredScopes.sorted().joined(separator: ",")),
            URLQueryItem(name: "redirect_uri", value: Self.callback),
            URLQueryItem(name: "state", value: state),
            URLQueryItem(name: "code_challenge", value: challenge),
            URLQueryItem(name: "code_challenge_method", value: "S256")
        ]
        guard let url = components?.url else { throw SlackClientError.invalidResponse }
        self.url = url
    }

    func authorizationCode(from callback: URL) throws -> String {
        guard let components = URLComponents(url: callback, resolvingAgainstBaseURL: false),
              components.scheme == Self.callbackScheme,
              components.host == "slack", components.path == "/oauth",
              components.port == nil, components.user == nil, components.password == nil,
              components.fragment == nil else { throw SlackClientError.invalidResponse }
        let items = components.queryItems ?? []
        func single(_ name: String) -> String? {
            let matching = items.filter { $0.name == name }
            return matching.count == 1 ? matching.first?.value : nil
        }
        guard single("state") == state else { throw SlackClientError.invalidResponse }
        if items.contains(where: { $0.name == "error" }) {
            guard single("error") == "access_denied", !items.contains(where: { $0.name == "code" }) else {
                throw SlackClientError.invalidResponse
            }
            throw SlackClientError.cancelled
        }
        guard let code = single("code"), !code.isEmpty, code.utf8.count <= 4096,
              !code.unicodeScalars.contains(where: { CharacterSet.whitespacesAndNewlines.contains($0) || CharacterSet.controlCharacters.contains($0) }) else {
            throw SlackClientError.invalidResponse
        }
        return code
    }

    static func base64URL(_ data: Data) -> String {
        data.base64EncodedString().replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
    }

    static func secureRandomBytes(_ count: Int) throws -> Data {
        var bytes = [UInt8](repeating: 0, count: count)
        guard SecRandomCopyBytes(kSecRandomDefault, count, &bytes) == errSecSuccess else {
            throw SlackClientError.serviceUnavailable
        }
        return Data(bytes)
    }
}

@MainActor
final class NativeSlackAuthentication: NSObject, SlackAuthenticating, ASWebAuthenticationPresentationContextProviding {
    private var session: ASWebAuthenticationSession?
    private var continuation: CheckedContinuation<URL, Error>?
    private var attempt: UUID?

    func authorize(url: URL, callbackScheme: String) async throws -> URL {
        guard continuation == nil else { throw SlackClientError.authorizationInProgress }
        try Task.checkCancellation()
        let id = UUID()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                self.attempt = id
                self.continuation = continuation
                let session = ASWebAuthenticationSession(url: url, callbackURLScheme: callbackScheme) { [weak self] url, error in
                    Task { @MainActor in
                        guard let self, self.attempt == id else { return }
                        if let url { self.finish(.success(url)) }
                        else if (error as? ASWebAuthenticationSessionError)?.code == .canceledLogin {
                            self.finish(.failure(SlackClientError.cancelled))
                        } else { self.finish(.failure(SlackClientError.serviceUnavailable)) }
                    }
                }
                session.presentationContextProvider = self
                self.session = session
                if !session.start() { self.finish(.failure(SlackClientError.serviceUnavailable)) }
            }
        } onCancel: {
            Task { @MainActor [weak self] in
                guard self?.attempt == id else { return }
                self?.cancel()
            }
        }
    }

    func cancel() {
        session?.cancel()
        finish(.failure(SlackClientError.cancelled))
    }

    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        NSApplication.shared.keyWindow ?? NSApplication.shared.mainWindow ?? ASPresentationAnchor()
    }

    private func finish(_ result: Result<URL, Error>) {
        let completion = continuation
        continuation = nil
        attempt = nil
        session = nil
        completion?.resume(with: result)
    }
}
