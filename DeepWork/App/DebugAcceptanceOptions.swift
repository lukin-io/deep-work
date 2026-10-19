#if DEBUG
import AppKit

/// Opt-in fixtures for compiled-app acceptance. Requires an explicit data-directory override.
struct DebugAcceptanceOptions {
    let appearance: NSAppearance.Name?
    let rejectsClipboardWrites: Bool
    let windowWidth: CGFloat?

    init(environment: [String: String] = ProcessInfo.processInfo.environment) {
        guard let directory = environment["DEEP_WORK_DATA_DIR"], !directory.isEmpty else {
            appearance = nil
            rejectsClipboardWrites = false
            windowWidth = nil
            return
        }
        switch environment["DEEP_WORK_APPEARANCE"] {
        case "light": appearance = .aqua
        case "dark": appearance = .darkAqua
        default: appearance = nil
        }
        rejectsClipboardWrites = environment["DEEP_WORK_CLIPBOARD_FAILURE"] == "1"
        if let raw = environment["DEEP_WORK_WINDOW_WIDTH"], let width = Int(raw), (320...1600).contains(width) {
            windowWidth = CGFloat(width)
        } else { windowWidth = nil }
    }

    @MainActor var clipboard: (any FeedbackCopying)? {
        rejectsClipboardWrites ? FeedbackClipboard(write: { _ in false }) : nil
    }
}
#endif
