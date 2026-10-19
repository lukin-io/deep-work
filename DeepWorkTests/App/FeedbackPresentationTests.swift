import AppKit
import SwiftUI
import Testing
import DeepWorkCore
@testable import DeepWorkApp

extension NativeApplicationTests {
@Suite(.serialized)
@MainActor
struct FeedbackPresentationTests {
    @Test func testS012_S015_S017_S018EmailReturnValidatesAndMovesFocusBeforeSavingExactlyOnce() async throws {
        let fixture = try makeFixture()
        defer { fixture.close() }
        await fixture.model.flushPersistence()
        fixture.model.feedbackEmail = "bad"
        fixture.model.feedbackMessage = "x"
        let email = try await emailField(in: fixture.host)
        let message = try await messageField(in: fixture.host)
        try await wait(in: fixture.host) { email.stringValue == "bad" && message.string == "x" }
        try #require(fixture.window.makeFirstResponder(email))
        let editor = try #require(email.currentEditor() as? NSTextView)
        let delegate = try #require(email.delegate)
        #expect(delegate.control?(email, textView: editor, doCommandBy: #selector(NSResponder.insertNewline(_:))) == true)
        try await wait(in: fixture.host) { fixture.model.feedbackError == FeedbackValidationError.email.localizedDescription }
        #expect(fixture.window.firstResponder === editor)
        #expect(fixture.model.pendingSettingsWrites == 0)

        // Reproduce the compiled-app regression: clearing an invalid email and
        // pressing Return must validate the now-optional blank address, then
        // focus the invalid message through the production Settings action.
        editor.selectAll(nil)
        editor.insertText("", replacementRange: editor.selectedRange())
        try await wait(in: fixture.host) { fixture.model.feedbackEmail.isEmpty && editor.string.isEmpty }
        #expect(delegate.control?(email, textView: editor, doCommandBy: #selector(NSResponder.insertNewline(_:))) == true)
        try await wait(in: fixture.host) { fixture.window.firstResponder === message }
        #expect(fixture.model.feedbackError == FeedbackValidationError.message.localizedDescription)
        message.selectAll(nil)
        message.insertText("  Saved by Return  ", replacementRange: message.selectedRange())
        try await wait(in: fixture.host) { fixture.model.feedbackMessage == "  Saved by Return  " }

        try #require(fixture.window.makeFirstResponder(email))
        let currentEditor = try #require(email.currentEditor() as? NSTextView)
        #expect(delegate.control?(email, textView: currentEditor, doCommandBy: #selector(NSResponder.insertTab(_:))) == false)
        try #require(fixture.window.makeFirstResponder(message))
        #expect(fixture.model.pendingSettingsWrites == 0, "Leaving the email field must never save the draft")
        #expect(SettingsStore(directory: fixture.directory).load().value.feedbackDraft == .empty)
        try #require(fixture.window.makeFirstResponder(email))
        let submittedEditor = try #require(email.currentEditor() as? NSTextView)
        #expect(delegate.control?(email, textView: submittedEditor, doCommandBy: #selector(NSResponder.insertNewline(_:))) == true)
        #expect(fixture.model.pendingSettingsWrites == 1, "One Return must enqueue only one explicit draft save")
        try #require(fixture.window.makeFirstResponder(message))
        await fixture.model.flushPersistence()
        #expect(fixture.model.feedbackError == nil)
        #expect(fixture.model.feedbackStatus == "Draft saved on this device. Nothing has been sent.")
        try #require(fixture.window.makeFirstResponder(email))
        try #require(fixture.window.makeFirstResponder(message))
        #expect(fixture.model.feedbackStatus == "Draft saved on this device. Nothing has been sent.",
                "Unchanged focus transitions must preserve Save acknowledgement and status")
        #expect(SettingsStore(directory: fixture.directory).load().value.feedbackDraft.message == "Saved by Return")
        #expect(email.accessibilityIdentifier() == "dw-feedback-email")
        #expect(email.accessibilityLabel() == "Email (optional)")
        #expect(email.placeholderString == "you@example.com")
    }

    @Test func testS012_S015_S016NativeEditorsRetainEditsAndEnforceUserInputLimits() async throws {
        let fixture = try makeFixture()
        defer { fixture.close() }
        let email = try await emailField(in: fixture.host)
        let message = try await messageField(in: fixture.host)
        #expect(email.isEditable && email.isEnabled && message.isEditable)

        email.stringValue = String(repeating: "x", count: 255)
        email.delegate?.controlTextDidChange?(Notification(name: NSControl.textDidChangeNotification, object: email))
        try await wait(in: fixture.host) { fixture.model.feedbackEmail.utf16.count == 254 && email.stringValue.utf16.count == 254 }
        #expect(email.stringValue.utf16.count == 254)

        message.string = String(repeating: "😀", count: 2501)
        message.didChangeText()
        let limitedMessage = String(repeating: "😀", count: 2500)
        // AppModel updates before SwiftUI renders the capped binding back into
        // AppKit. Wait for both boundaries before exercising native range edits.
        try await wait(in: fixture.host) {
            fixture.model.feedbackMessage == limitedMessage && message.string == limitedMessage
        }
        #expect(message.string == String(repeating: "😀", count: 2500))
        let delegate = try #require(message.delegate)
        #expect(delegate.textView?(message, shouldChangeTextIn: NSRange(location: 5000, length: 0), replacementString: "a") == false)
        #expect(delegate.textView?(message, shouldChangeTextIn: NSRange(location: 4998, length: 2), replacementString: "😀") == true)
        #expect(delegate.textView?(message, shouldChangeTextIn: NSRange(location: 0, length: 5000), replacementString: nil) == true)
        message.insertText("a", replacementRange: NSRange(location: 5000, length: 0))
        #expect(message.string.utf16.count == 5000)
        await fixture.model.flushPersistence()
        #expect(SettingsStore(directory: fixture.directory).load().value.feedbackDraft == .empty)

    }

    @Test func testS015NativeEmailBoundaryRetainsUndoAndDisabledState() async throws {
        prepareNativeTestApplication()
        let state = EnabledEditorState()
        state.text = String(repeating: "a", count: 253)
        let host = NSHostingView(rootView: EnabledEmailHarness(state: state))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 400, height: 100),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = host
        window.orderFront(nil)
        defer { window.orderOut(nil) }
        let field = try await emailField(in: host)
        try await wait(in: host) { field.stringValue == state.text }
        try #require(window.makeFirstResponder(field))
        let editor = try #require(field.currentEditor() as? NSTextView)
        let undo = try #require(editor.undoManager)
        undo.removeAllActions()
        editor.insertText("b", replacementRange: NSRange(location: 253, length: 0))
        try await wait(in: host) { state.text.utf16.count == 254 }
        editor.insertText("c", replacementRange: NSRange(location: 254, length: 0))
        try await wait(in: host) { editor.string.utf16.count == 254 && state.text == editor.string }
        #expect(editor.string == String(repeating: "a", count: 253) + "b")
        #expect(undo.canUndo)
        undo.undo()
        try await wait(in: host) { state.text == String(repeating: "a", count: 253) && editor.string == state.text }
        undo.redo()
        try await wait(in: host) { state.text.utf16.count == 254 && editor.string == state.text }

        state.disabled = true
        try await wait(in: host) { !field.isEditable && !field.isEnabled }
        #expect(field.stringValue == state.text)
        state.disabled = false
        try await wait(in: host) { field.isEditable && field.isEnabled }
        #expect(field.stringValue == state.text)
    }

    @Test func testS012_S016NativeMessageReturnInsertsNewlineWithoutSavingAndRetainsNativeUndo() async throws {
        let fixture = try makeFixture()
        defer { fixture.close() }
        fixture.model.feedbackMessage = "An unsaved message"
        let message = try await messageField(in: fixture.host)
        try await wait(in: fixture.host) { message.string == "An unsaved message" }
        try #require(fixture.window.makeFirstResponder(message))
        message.setSelectedRange(NSRange(location: message.string.utf16.count, length: 0))
        message.insertNewline(nil)
        try await wait(in: fixture.host) { fixture.model.feedbackMessage == "An unsaved message\n" }
        #expect(message.allowsUndo && !message.isRichText && !message.importsGraphics)
        let undo = try #require(message.undoManager)
        #expect(undo.canUndo)
        undo.undo()
        try await wait(in: fixture.host) { fixture.model.feedbackMessage == "An unsaved message" }
        #expect(undo.canRedo)
        undo.redo()
        try await wait(in: fixture.host) { fixture.model.feedbackMessage == "An unsaved message\n" }
        #expect(message.accessibilityLabel() == "Your feedback")
        #expect(message.accessibilityIdentifier() == "dw-feedback-message")
        await fixture.model.flushPersistence()
        #expect(SettingsStore(directory: fixture.directory).load().value.feedbackDraft == .empty)
        #expect(fixture.model.feedbackStatus == nil)
    }

    @Test func testS019NativeSelectionAdapterSelectsFullUnicodeMessage() async throws {
        prepareNativeTestApplication()
        let selection = FeedbackPresentation()
        let message = "A multiline 😀 message\nwith a second line."
        let host = NSHostingView(rootView: SelectionHarness(message: message, presentation: selection))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 400, height: 160), styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = host
        window.makeKeyAndOrderFront(nil)
        defer { window.orderOut(nil) }
        try await wait(in: host) { !nativeViews(NSTextView.self, in: host).isEmpty }
        let editor = try #require(nativeViews(NSTextView.self, in: host).first)
        try await wait(in: host) { editor.string == message }
        try #require(window.makeFirstResponder(editor))
        try await Task.sleep(for: .milliseconds(100))
        selection.selectMessage()
        try await wait(in: host) { editor.selectedRange() == NSRange(location: 0, length: message.utf16.count) }
        #expect(window.firstResponder === editor)
        #expect(editor.string == message)

        // An unrelated report/status redraw must not steal the user's newly
        // selected control. Only a fresh copy-failure request selects again.
        let otherField = NSTextField(frame: NSRect(x: 0, y: 0, width: 100, height: 24))
        host.addSubview(otherField)
        try #require(window.makeFirstResponder(otherField))
        let otherEditor = try #require(otherField.currentEditor())
        let updated = message + " More text."
        host.rootView = SelectionHarness(message: updated, presentation: selection)
        try await wait(in: host) { editor.string == updated }
        #expect(window.firstResponder === otherEditor)
        // Regression: a message validation request from the email field must
        // move the real responder even though the editor is hosted by SwiftUI.
        let priorSelection = editor.selectedRange()
        selection.focusMessage()
        try await wait(in: host) { window.firstResponder === editor }
        #expect(editor.selectedRange() == priorSelection)
        try #require(window.makeFirstResponder(otherField))
        selection.selectMessage()
        try await wait(in: host) { editor.selectedRange() == NSRange(location: 0, length: updated.utf16.count) }
        #expect(window.firstResponder === editor)
    }

    @Test func testS001_S015_S016NativeFieldGeometryFitsNarrowSettingsInLightAndDarkAppearances() async throws {
        for width in [272.0, 512.0] {
            for appearance in [NSAppearance.Name.aqua, .darkAqua] {
                let fixture = try makeFixture(width: width)
                defer { fixture.close() }
                fixture.window.appearance = NSAppearance(named: appearance)
                fixture.model.feedbackEmail = String(repeating: "a", count: 245) + "@test.com"
                let email = try await emailField(in: fixture.host)
                let message = try await messageField(in: fixture.host)
                try await wait(in: fixture.host) { email.stringValue.utf16.count == 254 }
                for view in [email as NSView, (message.enclosingScrollView as NSView?) ?? message] {
                    let frame = view.convert(view.bounds, to: fixture.host)
                    #expect(frame.width > 80)
                    #expect(frame.minX >= -0.5 && frame.maxX <= fixture.host.bounds.width + 0.5)
                }
                #expect(message.enclosingScrollView?.hasVerticalScroller == true)
                #expect(message.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == appearance)
                await fixture.model.flushPersistence()
            }
        }
    }

    @Test func testS016_S021DisabledEditorRejectsTypingWhileQuitDrainsAndReenablesWithoutLosingText() async throws {
        prepareNativeTestApplication()
        let state = EnabledEditorState()
        let host = NSHostingView(rootView: EnabledEditorHarness(state: state))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 400, height: 160),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = host
        window.orderFront(nil)
        defer { window.orderOut(nil) }
        let editor = try await messageField(in: host)
        try await wait(in: host) { editor.string == state.text && editor.isEditable }
        try #require(window.makeFirstResponder(editor))
        editor.setSelectedRange(NSRange(location: state.text.utf16.count, length: 0))
        state.disabled = true
        try await wait(in: host) { !editor.isEditable }
        let key = try #require(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
                                               windowNumber: window.windowNumber, context: nil, characters: "z",
                                               charactersIgnoringModifiers: "z", isARepeat: false, keyCode: 6))
        editor.keyDown(with: key)
        #expect(state.text == "Recoverable feedback" && editor.string == state.text)
        #expect(editor.isSelectable, "Read-only selection remains available without changing the draft")

        state.disabled = false
        try await wait(in: host) { editor.isEditable }
        editor.insertText("z", replacementRange: NSRange(location: state.text.utf16.count, length: 0))
        try await wait(in: host) { state.text == "Recoverable feedbackz" && editor.string == state.text }
    }

    private final class EnabledEditorState: ObservableObject {
        @Published var text = "Recoverable feedback"
        @Published var disabled = false
    }

    private struct EnabledEditorHarness: View {
        @ObservedObject var state: EnabledEditorState
        var body: some View {
            FeedbackMessageEditor(text: $state.text, focusRequest: 0, selectionRequest: 0, accessibilityHint: "Required")
                .disabled(state.disabled)
        }
    }

    private struct EnabledEmailHarness: View {
        @ObservedObject var state: EnabledEditorState
        var body: some View {
            FeedbackEmailField(text: Binding(get: { state.text }, set: {
                state.text = FeedbackPresentation.limitedInput($0, utf16Limit: 254)
            }), focusRequest: 0, accessibilityHint: "Optional", onSubmit: {})
                .disabled(state.disabled)
        }
    }

    private struct SelectionHarness: View {
        let message: String
        @ObservedObject var presentation: FeedbackPresentation
        var body: some View {
            FeedbackMessageEditor(text: .constant(message), focusRequest: presentation.focusRequest,
                                  selectionRequest: presentation.selectionRequest, accessibilityHint: "Required")
        }
    }

    private struct Fixture {
        let directory: URL
        let model: AppModel
        let window: NSWindow
        let host: NSHostingView<SettingsView>

        @MainActor func close() {
            window.orderOut(nil)
            try? FileManager.default.removeItem(at: directory)
        }
    }

    private func makeFixture(width: Double = 512) throws -> Fixture {
        prepareNativeTestApplication()
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("DeepWorkFeedbackUI-\(UUID())")
        let model = AppModel(journalStore: JournalStore(directory: directory), settingsStore: SettingsStore(directory: directory),
                             clock: TestTimerClock(), automaticRefresh: false)
        model.selectedTab = .settings
        let host = NSHostingView(rootView: SettingsView(model: model))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: width, height: 780), styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = host
        window.makeKeyAndOrderFront(nil)
        return Fixture(directory: directory, model: model, window: window, host: host)
    }

    private func emailField(in host: NSView) async throws -> NSTextField {
        try await wait(in: host) { nativeViews(NSTextField.self, in: host).contains { $0.isEditable } }
        return try #require(nativeViews(NSTextField.self, in: host).first { $0.isEditable })
    }

    private func messageField(in host: NSView) async throws -> NSTextView {
        try await wait(in: host) { nativeViews(NSTextView.self, in: host).contains { !$0.isFieldEditor } }
        return try #require(nativeViews(NSTextView.self, in: host).first { !$0.isFieldEditor })
    }

    private func nativeViews<ViewType: NSView>(_ type: ViewType.Type, in view: NSView) -> [ViewType] {
        let current = (view as? ViewType).map { [$0] } ?? []
        return current + view.subviews.flatMap { nativeViews(type, in: $0) }
    }

    private func wait(in host: NSView, sourceLocation: SourceLocation = #_sourceLocation, condition: () -> Bool) async throws {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: .seconds(3))
        while clock.now < deadline {
            host.layoutSubtreeIfNeeded()
            if condition() { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        try #require(condition(), "Native feedback controls did not reflect the expected state", sourceLocation: sourceLocation)
    }
}
}
