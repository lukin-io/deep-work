import Foundation

public enum FeedbackType: String, Codable, CaseIterable, Sendable { case idea, problem, general }

public enum FeedbackValidationError: Error, LocalizedError, Equatable, Sendable {
    case email, message

    public var errorDescription: String? {
        switch self {
        case .email: return "Enter a valid email address, or leave it blank."
        case .message: return "Write a message between 5 and 5,000 characters."
        }
    }
}

public struct FeedbackDraft: Codable, Equatable, Sendable {
    public var type: FeedbackType
    public var email: String
    public var message: String

    public init(type: FeedbackType = .general, email: String = "", message: String = "") {
        self.type = type; self.email = email; self.message = message
    }

    public static let empty = FeedbackDraft()

    private enum CodingKeys: String, CodingKey { case type, email, message }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        // The approved contract falls back to General feedback for an unknown type.
        let rawType = try container.decodeIfPresent(String.self, forKey: .type)
        type = rawType.flatMap(FeedbackType.init(rawValue:)) ?? .general
        email = try container.decode(String.self, forKey: .email)
        message = try container.decode(String.self, forKey: .message)
    }

    /// Counts UTF-16 code units to retain the prototype's emoji/length semantics.
    /// The ASCII email grammar matches the HTML single-address input constraint;
    /// it checks shape only and makes no deliverability claim.
    public func validatedForSaving() throws -> FeedbackDraft {
        let trimmedEmail = email.trimmingCharacters(in: Self.trimCharacters)
        let trimmedMessage = message.trimmingCharacters(in: Self.trimCharacters)
        let emailPattern = #"^[a-zA-Z0-9.!#$%&'*+/=?^_`{|}~-]+@[a-zA-Z0-9](?:[a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?(?:\.[a-zA-Z0-9](?:[a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?)*$"#
        guard email.utf16.count <= 254 && (trimmedEmail.isEmpty || trimmedEmail.range(of: emailPattern, options: .regularExpression) != nil)
        else { throw FeedbackValidationError.email }
        guard trimmedMessage.utf16.count >= 5 && message.utf16.count <= 5000
        else { throw FeedbackValidationError.message }
        return FeedbackDraft(type: type, email: trimmedEmail, message: trimmedMessage)
    }

    /// The same explicit validation applies to Save and Copy. Building a payload
    /// does not mutate the draft or imply persistence or delivery.
    public func validatedClipboardText() throws -> String {
        let draft = try validatedForSaving()
        let typeName: String
        switch draft.type {
        case .idea: typeName = "Suggestion"
        case .problem: typeName = "Problem report"
        case .general: typeName = "General feedback"
        }
        let emailLine = draft.email.isEmpty ? "" : "\nEmail: \(draft.email)"
        return "Deep Work feedback\nType: \(typeName)\(emailLine)\n\n\(draft.message)"
    }

    func validateStored() throws {
        if email.isEmpty && message.isEmpty { return }
        let canonical = try validatedForSaving()
        try require(canonical == self, "Saved feedback must contain the explicitly saved, trimmed values.")
    }

    // ECMAScript TrimString whitespace, including BOM but excluding U+0085.
    private static let trimCharacters = CharacterSet(charactersIn:
        "\u{0009}\u{000A}\u{000B}\u{000C}\u{000D}\u{0020}\u{00A0}\u{1680}\u{2000}\u{2001}\u{2002}\u{2003}\u{2004}\u{2005}\u{2006}\u{2007}\u{2008}\u{2009}\u{200A}\u{2028}\u{2029}\u{202F}\u{205F}\u{3000}\u{FEFF}")
}

/// This Boolean records preference only. ServiceManagement must supply actual
/// login-item registration/approval state when the native service is implemented.
public struct SettingsDocument: StoredDocument, Equatable {
    public var version: Int
    public var launchAtLogin: Bool
    public var feedbackDraft: FeedbackDraft

    public init(version: Int = 1, launchAtLogin: Bool = false, feedbackDraft: FeedbackDraft = .empty) {
        self.version = version; self.launchAtLogin = launchAtLogin; self.feedbackDraft = feedbackDraft
    }

    public func validate() throws {
        guard version == 1 else { throw UnsupportedSchemaVersion(version) }
        try feedbackDraft.validateStored()
    }
}
