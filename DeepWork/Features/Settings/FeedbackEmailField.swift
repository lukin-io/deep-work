import AppKit
import SwiftUI

/// Preserve native single-line editing while giving Return an explicit Save
/// Draft action, including when the optional address has just been cleared.
struct FeedbackEmailField: NSViewRepresentable {
    @Environment(\.isEnabled) private var isEnabled
    @Binding var text: String
    let focusRequest: Int
    let accessibilityHint: String
    let onSubmit: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSTextField {
        let field = NSTextField(string: "")
        field.placeholderString = "you@example.com"
        field.bezelStyle = .roundedBezel
        field.font = .systemFont(ofSize: 12)
        field.formatter = InputLengthFormatter()
        field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        field.setContentHuggingPriority(.defaultLow, for: .horizontal)
        field.setAccessibilityLabel("Email (optional)")
        field.setAccessibilityIdentifier("dw-feedback-email")
        field.delegate = context.coordinator
        return field
    }

    func updateNSView(_ field: NSTextField, context: Context) {
        context.coordinator.parent = self
        field.isEnabled = isEnabled
        field.isEditable = isEnabled
        let displayedText = field.currentEditor()?.string ?? field.stringValue
        if displayedText != text { field.stringValue = text }
        field.setAccessibilityHelp(accessibilityHint)
        if focusRequest != context.coordinator.handledFocusRequest {
            context.coordinator.handledFocusRequest = focusRequest
            if field.window?.firstResponder !== field.currentEditor() {
                field.window?.makeFirstResponder(field)
            }
        }
    }

    @MainActor
    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: FeedbackEmailField
        var handledFocusRequest: Int
        private weak var editingField: NSTextField?

        init(_ parent: FeedbackEmailField) {
            self.parent = parent
            handledFocusRequest = parent.focusRequest
        }

        func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSTextField else { return }
            synchronize(field.currentEditor()?.string ?? field.stringValue)
        }

        func controlTextDidBeginEditing(_ notification: Notification) {
            guard let field = notification.object as? NSTextField,
                  let editor = field.currentEditor() as? NSTextView else { return }
            editor.allowsUndo = true
            editingField = field
            stopObservingUndo()
            if let undo = editor.undoManager {
                NotificationCenter.default.addObserver(self, selector: #selector(undoOrRedo(_:)),
                                                       name: .NSUndoManagerDidUndoChange, object: undo)
                NotificationCenter.default.addObserver(self, selector: #selector(undoOrRedo(_:)),
                                                       name: .NSUndoManagerDidRedoChange, object: undo)
            }
        }

        func controlTextDidEndEditing(_ notification: Notification) {
            if let field = notification.object as? NSTextField { synchronize(field.stringValue) }
            stopObservingUndo()
            editingField = nil
        }

        @objc private func undoOrRedo(_ notification: Notification) {
            // The shared field editor updates its storage during Undo without
            // necessarily sending controlTextDidChange. Read only our active
            // editor and leave AppKit's shared delegate/storage ownership alone.
            guard let editor = editingField?.currentEditor() as? NSTextView else { return }
            synchronize(editor.string)
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            guard commandSelector == #selector(NSResponder.insertNewline(_:)) else { return false }
            synchronize(textView.string)
            parent.onSubmit()
            return true
        }

        private func synchronize(_ value: String) {
            if parent.text != value { parent.text = value }
        }

        private func stopObservingUndo() {
            // NSTextField also registers its delegate for editing notifications.
            // Remove only our observers, preserving that native registration.
            NotificationCenter.default.removeObserver(self, name: .NSUndoManagerDidUndoChange, object: nil)
            NotificationCenter.default.removeObserver(self, name: .NSUndoManagerDidRedoChange, object: nil)
        }
    }

    /// Validate native edits before changing the field editor, so a rejected
    /// paste or key does not require rewriting storage and clearing Undo.
    private final class InputLengthFormatter: Formatter {
        override func string(for obj: Any?) -> String? { obj as? String }

        override func getObjectValue(_ obj: AutoreleasingUnsafeMutablePointer<AnyObject?>?, for string: String,
                                     errorDescription error: AutoreleasingUnsafeMutablePointer<NSString?>?) -> Bool {
            obj?.pointee = string as NSString
            return true
        }

        override func isPartialStringValid(_ partialStringPtr: AutoreleasingUnsafeMutablePointer<NSString>,
                                          proposedSelectedRange proposedSelRangePtr: NSRangePointer?,
                                          originalString origString: String, originalSelectedRange origSelRange: NSRange,
                                          errorDescription error: AutoreleasingUnsafeMutablePointer<NSString?>?) -> Bool {
            partialStringPtr.pointee.length <= 254
        }
    }
}
