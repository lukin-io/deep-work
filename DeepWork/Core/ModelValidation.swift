import Foundation

public struct ModelValidationError: Error, Equatable, LocalizedError, Sendable {
    public let reason: String

    public init(_ reason: String) { self.reason = reason }
    public var errorDescription: String? { reason }
}

public struct UnsupportedSchemaVersion: Error, Equatable, Sendable {
    public let version: Int
    public init(_ version: Int) { self.version = version }
}

/// Validation is repeated at both the read and write boundary, including decoded values.
public protocol StoredDocument: Codable, Sendable {
    func validate() throws
}

func require(_ condition: @autoclosure () -> Bool, _ reason: String) throws {
    guard condition() else { throw ModelValidationError(reason) }
}

func validateTimestamp(_ date: Date) throws {
    // Foundation Date accepts nonfinite and far out-of-calendar values. Keep the
    // native journal in the reference's representable absolute timestamp range.
    let seconds = date.timeIntervalSince1970
    try require(seconds.isFinite && abs(seconds) < 8_640_000_000_000,
                "A stored timestamp is outside the supported range.")
}
