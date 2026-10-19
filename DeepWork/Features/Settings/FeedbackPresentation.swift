import SwiftUI

/// Selection belongs to the editor; all feedback content remains in AppModel.
@MainActor
final class FeedbackPresentation: ObservableObject {
    @Published private(set) var emailFocusRequest = 0
    @Published private(set) var focusRequest = 0
    @Published private(set) var selectionRequest = 0

    func focusEmail() { emailFocusRequest += 1 }
    func focusMessage() { focusRequest += 1 }
    func selectMessage() { selectionRequest += 1 }

    /// Match the approved UTF-16 input limits without introducing an unpaired
    /// surrogate. Programmatically supplied values still face model validation.
    static func limitedInput(_ text: String, utf16Limit: Int) -> String {
        guard text.utf16.count > utf16Limit else { return text }
        var units = 0
        var end = text.unicodeScalars.startIndex
        for scalar in text.unicodeScalars {
            let count = scalar.value > 0xFFFF ? 2 : 1
            guard units + count <= utf16Limit else { break }
            units += count
            end = text.unicodeScalars.index(after: end)
        }
        return String(text[..<end])
    }
}
