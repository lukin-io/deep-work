import AppKit

enum FeedbackActionFocus: Hashable { case email, message, copy, selectMessage }

@MainActor
protocol FeedbackCopying {
    func copy(_ text: String) throws
}

enum FeedbackClipboardError: Error, LocalizedError, Equatable {
    case unavailable

    var errorDescription: String? { "Copy is unavailable. Select and copy your message." }
}

/// One native pasteboard write, with an injectable operation for the system's
/// rejected-write path. Tests use a named pasteboard, never the user's clipboard.
@MainActor
struct FeedbackClipboard: FeedbackCopying {
    private let write: (String) -> Bool

    init(pasteboard: NSPasteboard = .general) {
        write = { text in
            pasteboard.clearContents()
            return pasteboard.setString(text, forType: .string)
        }
    }

    init(write: @escaping (String) -> Bool) { self.write = write }

    func copy(_ text: String) throws {
        guard write(text) else { throw FeedbackClipboardError.unavailable }
    }
}
