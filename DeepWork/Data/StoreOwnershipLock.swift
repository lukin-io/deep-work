import Darwin
import Foundation

public enum StoreOwnershipError: Error, Equatable, LocalizedError, Sendable {
    case alreadyOwned
    case unavailable(String)

    public var errorDescription: String? {
        switch self {
        case .alreadyOwned:
            return "Deep Work is already open for this data directory. Use the existing app, or quit it before opening another copy."
        case .unavailable(let reason):
            return "Deep Work could not establish exclusive access to its data. \(reason)"
        }
    }
}

/// A process-lifetime advisory lock for the app-owned data directory. Acquire
/// before loading/creating stores, and retain until the final writes finish.
/// SQLite still supplies transaction integrity; this prevents two app models
/// in different processes from independently replacing the same live session.
public final class StoreOwnershipLock {
    public static let filename = "DeepWork.owner.lock"
    private let descriptor: Int32

    public init(directory: URL) throws {
        guard directory.isFileURL else {
            throw StoreOwnershipError.unavailable("The data directory must be a local file URL.")
        }
        let directory = directory.standardizedFileURL.resolvingSymlinksInPath()
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                                                    attributes: [.posixPermissions: 0o700])
        } catch {
            throw StoreOwnershipError.unavailable(error.localizedDescription)
        }

        let url = directory.appendingPathComponent(Self.filename)
        // Do not follow an unexpected lock-file symlink, or let launched child
        // processes retain ownership after this app exits.
        let opened = url.withUnsafeFileSystemRepresentation { path in
            path.map { Darwin.open($0, O_RDWR | O_CREAT | O_CLOEXEC | O_NOFOLLOW, 0o600) } ?? -1
        }
        guard opened >= 0 else { throw Self.systemFailure(errno) }

        var details = stat()
        guard fstat(opened, &details) == 0 else {
            let error = Self.systemFailure(errno)
            Darwin.close(opened)
            throw error
        }
        guard (details.st_mode & S_IFMT) == S_IFREG else {
            Darwin.close(opened)
            throw StoreOwnershipError.unavailable("The ownership lock is not a regular file.")
        }
        guard flock(opened, LOCK_EX | LOCK_NB) == 0 else {
            let code = errno
            Darwin.close(opened)
            if code == EWOULDBLOCK { throw StoreOwnershipError.alreadyOwned }
            throw Self.systemFailure(code)
        }
        guard fchmod(opened, details.st_mode & 0o600) == 0 else {
            let error = Self.systemFailure(errno)
            Darwin.close(opened)
            throw error
        }
        descriptor = opened
    }

    deinit {
        // Never unlink the lock file: a third process could otherwise lock a
        // different inode while a second process still holds the original.
        Darwin.close(descriptor)
    }

    private static func systemFailure(_ code: Int32) -> StoreOwnershipError {
        .unavailable(String(cString: strerror(code)))
    }
}
