import Foundation

public struct SlackAccount: Codable, Equatable, Sendable {
    public let workspaceID: String
    public let userID: String
    public let workspaceName: String
    public let userName: String

    public init(workspaceID: String, userID: String, workspaceName: String, userName: String) {
        self.workspaceID = workspaceID; self.userID = userID
        self.workspaceName = workspaceName; self.userName = userName
    }

    public func validate() throws {
        try require(!workspaceID.isEmpty && !userID.isEmpty && workspaceID.count <= 256 && userID.count <= 256,
                    "The Slack account identifier is invalid.")
    }

    public func matches(_ other: SlackAccount) -> Bool {
        workspaceID == other.workspaceID && userID == other.userID
    }
}

public struct SlackProfile: Codable, Equatable, Sendable {
    public let text: String
    public let emoji: String
    public let expiration: Int

    public init(text: String, emoji: String, expiration: Int) {
        self.text = text; self.emoji = emoji; self.expiration = expiration
    }

    public static let focus = SlackProfile(text: "Deep WORK, DND", emoji: ":x:", expiration: 0)
    public static let empty = SlackProfile(text: "", emoji: "", expiration: 0)

    public func validate() throws {
        try require(text.utf16.count <= 4096 && emoji.utf16.count <= 256 && expiration >= 0,
                    "The Slack status data is invalid.")
    }

    public func restoring(at date: Date) -> SlackProfile {
        expiration > 0 && Double(expiration) <= date.timeIntervalSince1970 ? .empty : self
    }
}

/// A write-ahead restoration receipt. Persist before changing the remote status.
/// Tokens never belong in this document; they remain in Keychain.
public struct SlackOwnership: Codable, Equatable, Sendable {
    public let account: SlackAccount
    public let cycleID: UUID
    public let previous: SlackProfile
    public let applied: SlackProfile

    public init(account: SlackAccount, cycleID: UUID, previous: SlackProfile, applied: SlackProfile = .focus) {
        self.account = account; self.cycleID = cycleID; self.previous = previous; self.applied = applied
    }
}

public struct SlackDocument: StoredDocument, Equatable {
    public var version: Int
    public var ownership: SlackOwnership?

    public init(version: Int = 1, ownership: SlackOwnership? = nil) {
        self.version = version; self.ownership = ownership
    }

    public func validate() throws {
        guard version == 1 else { throw UnsupportedSchemaVersion(version) }
        if let ownership {
            try ownership.account.validate()
            try ownership.previous.validate()
            try ownership.applied.validate()
            try require(ownership.applied == .focus, "The stored Slack ownership status is unsupported.")
        }
    }
}
