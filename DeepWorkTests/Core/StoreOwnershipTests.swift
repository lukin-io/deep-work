import Foundation
import Testing
@testable import DeepWorkCore

struct StoreOwnershipTests {
    @Test func F026OnlyOneOwnerUntilReleaseAndLockDoesNotCreateDatabase() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        var owner: StoreOwnershipLock? = try StoreOwnershipLock(directory: directory)
        #expect(owner != nil)
        #expect(throws: StoreOwnershipError.alreadyOwned) { try StoreOwnershipLock(directory: directory) }
        #expect(!FileManager.default.fileExists(atPath: directory.appendingPathComponent(StoreLocation.databaseFilename).path))
        let lockURL = directory.appendingPathComponent(StoreOwnershipLock.filename)
        let permissions = try FileManager.default.attributesOfItem(atPath: lockURL.path)[.posixPermissions] as? NSNumber
        #expect(permissions?.intValue == 0o600)
        owner = nil
        let nextOwner = try StoreOwnershipLock(directory: directory)
        #expect(FileManager.default.fileExists(atPath: lockURL.path))
        _ = withExtendedLifetime(nextOwner) {
            #expect(throws: StoreOwnershipError.alreadyOwned) { try StoreOwnershipLock(directory: directory) }
        }
    }

    @Test func F026DirectoryAliasesCannotAcquireSecondOwner() throws {
        let directory = temporaryDirectory()
        let alias = directory.appendingPathExtension("alias")
        defer {
            try? FileManager.default.removeItem(at: alias)
            try? FileManager.default.removeItem(at: directory)
        }
        let owner = try StoreOwnershipLock(directory: directory)
        try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: directory)
        _ = withExtendedLifetime(owner) {
            #expect(throws: StoreOwnershipError.alreadyOwned) { try StoreOwnershipLock(directory: alias) }
        }
    }

    @Test func F026LockSymlinkAndInvalidDirectoryFailWithoutReplacingData() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let dataURL = directory.appendingPathComponent("preserve.sqlite")
        let original = Data("Existing recoverable data".utf8)
        try original.write(to: dataURL)
        let lockURL = directory.appendingPathComponent(StoreOwnershipLock.filename)
        try FileManager.default.createSymbolicLink(at: lockURL, withDestinationURL: dataURL)
        #expect(throws: StoreOwnershipError.self) { try StoreOwnershipLock(directory: directory) }
        #expect(throws: StoreOwnershipError.self) { try StoreOwnershipLock(directory: dataURL) }
        #expect(try Data(contentsOf: dataURL) == original)
    }

    private func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("DeepWorkOwnershipTests-\(UUID().uuidString)")
    }
}
