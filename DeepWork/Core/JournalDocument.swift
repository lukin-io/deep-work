import Foundation

/// Real history only. Sample/report data belongs to a separate in-memory source
/// and is deliberately absent from this persisted schema.
public struct JournalDocument: StoredDocument, Equatable {
    public var version: Int
    public var records: [SessionRecord]
    public var configuration: FocusConfiguration
    public var schedule: WorkSchedule
    public var activeCheckpoint: ActiveCheckpoint?

    public init(version: Int = 1, records: [SessionRecord] = [],
                configuration: FocusConfiguration = FocusConfiguration(),
                schedule: WorkSchedule = WorkSchedule(), activeCheckpoint: ActiveCheckpoint? = nil) {
        self.version = version; self.records = records
        self.configuration = configuration; self.schedule = schedule
        self.activeCheckpoint = activeCheckpoint
    }

    public func validate() throws {
        guard version == 1 else { throw UnsupportedSchemaVersion(version) }
        try configuration.validate()
        try schedule.validate()
        var identifiers = Set<UUID>()
        for record in records {
            try record.validate()
            try require(identifiers.insert(record.id).inserted, "Journal session identifiers must be unique.")
        }
        try activeCheckpoint?.validate()
        if let liveID = activeCheckpoint?.focusRecord?.id {
            try require(!identifiers.contains(liveID), "The active focus must not duplicate a finalized session.")
        }
    }
}
