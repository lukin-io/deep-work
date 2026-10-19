import AppKit
import SwiftUI

/// A plain native editor gives copy failure a reliable, explicit selection
/// target. Content remains a binding to AppModel; only selection is view state.
struct FeedbackMessageEditor: NSViewRepresentable {
    @Environment(\.isEnabled) private var isEnabled
    @Binding var text: String
    let focusRequest: Int
    let selectionRequest: Int
    let accessibilityHint: String

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSTextView.scrollableTextView()
        guard let editor = scroll.documentView as? NSTextView else { return scroll }
        editor.isRichText = false
        editor.importsGraphics = false
        editor.allowsUndo = true
        editor.font = .systemFont(ofSize: 12)
        editor.textContainerInset = NSSize(width: 4, height: 4)
        editor.setAccessibilityLabel("Your feedback")
        editor.setAccessibilityIdentifier("dw-feedback-message")
        editor.delegate = context.coordinator
        editor.textStorage?.delegate = context.coordinator
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let editor = scroll.documentView as? NSTextView else { return }
        context.coordinator.parent = self
        // NSViewRepresentable does not automatically map SwiftUI disabled state
        // into AppKit editing. Quit must freeze edits while its writes drain.
        editor.isEditable = isEnabled
        if editor.string != text {
            let previous = editor.selectedRange()
            context.coordinator.isApplyingModelText = true
            editor.string = text
            context.coordinator.isApplyingModelText = false
            let location = min(previous.location, text.utf16.count)
            let length = min(previous.length, text.utf16.count - location)
            editor.setSelectedRange(NSRange(location: location, length: length))
        }
        editor.setAccessibilityHelp(accessibilityHint)
        if focusRequest != context.coordinator.handledFocusRequest {
            context.coordinator.handledFocusRequest = focusRequest
            editor.window?.makeFirstResponder(editor)
        }
        if selectionRequest != context.coordinator.handledSelectionRequest {
            context.coordinator.handledSelectionRequest = selectionRequest
            editor.window?.makeFirstResponder(editor)
            editor.selectAll(nil)
        }
    }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate, @preconcurrency NSTextStorageDelegate {
        var parent: FeedbackMessageEditor
        var handledFocusRequest: Int
        var handledSelectionRequest: Int
        var isApplyingModelText = false

        init(_ parent: FeedbackMessageEditor) {
            self.parent = parent
            handledFocusRequest = parent.focusRequest
            handledSelectionRequest = parent.selectionRequest
        }

        func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            // This editor is one field in a form. Preserve the native key-view
            // loop instead of inserting a tab and trapping keyboard navigation.
            switch commandSelector {
            case #selector(NSResponder.insertTab(_:)):
                textView.window?.selectNextKeyView(nil)
                return true
            case #selector(NSResponder.insertBacktab(_:)):
                textView.window?.selectPreviousKeyView(nil)
                return true
            default:
                return false
            }
        }

        func textView(_ textView: NSTextView, shouldChangeTextIn affectedCharRange: NSRange,
                      replacementString: String?) -> Bool {
            guard let replacementString else { return true } // Attribute-only change.
            let length = textView.string.utf16.count
            guard affectedCharRange.location >= 0, affectedCharRange.length >= 0,
                  affectedCharRange.location <= length,
                  affectedCharRange.length <= length - affectedCharRange.location else { return false }
            let replacementLength = replacementString.utf16.count
            // Reject an over-limit edit before native Undo records it. Clipping
            // the storage afterwards could invalidate Undo's replacement range.
            return replacementLength <= 5000 && length - affectedCharRange.length <= 5000 - replacementLength
        }

        func textDidChange(_ notification: Notification) {
            guard let editor = notification.object as? NSTextView else { return }
            if !isApplyingModelText && parent.text != editor.string { parent.text = editor.string }
        }

        // Undo/redo can edit the storage without textDidChange. Observe native
        // character edits too, while excluding updates rendered from AppModel.
        func textStorage(_ textStorage: NSTextStorage, didProcessEditing editedMask: NSTextStorageEditActions,
                         range editedRange: NSRange, changeInLength delta: Int) {
            if !isApplyingModelText && editedMask.contains(.editedCharacters) && parent.text != textStorage.string {
                parent.text = textStorage.string
            }
        }

    }
}
