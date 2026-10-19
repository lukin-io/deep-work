import AppKit
import Testing
import DeepWorkCore
@testable import DeepWorkApp

extension NativeApplicationTests {
@Suite(.serialized)
@MainActor
struct FeedbackClipboardTests {
    @Test func testS019NativePasteboardContainsExactPayloadAndReplacesPreviousContents() throws {
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        pasteboard.clearContents()
        #expect(pasteboard.setString("previous contents", forType: .string))
        let clipboard = FeedbackClipboard(pasteboard: pasteboard)
        let draft = FeedbackDraft(type: .problem, email: " person@example.com ", message: "  Keep unicode 😀\nand multiple lines. ")
        let text = try draft.validatedClipboardText()
        try clipboard.copy(text)
        #expect(pasteboard.string(forType: .string)
            == "Deep Work feedback\nType: Problem report\nEmail: person@example.com\n\nKeep unicode 😀\nand multiple lines.")
        #expect(pasteboard.pasteboardItems?.count == 1)
    }

    @Test func testS019RejectedNativeWriteThrowsTypedFailureAndNeverClaimsSuccess() {
        var attempts: [String] = []
        let clipboard = FeedbackClipboard(write: { text in attempts.append(text); return false })
        #expect(throws: FeedbackClipboardError.unavailable) { try clipboard.copy("prepared payload") }
        #expect(attempts == ["prepared payload"])
        #expect(FeedbackClipboardError.unavailable.localizedDescription == "Copy is unavailable. Select and copy your message.")
    }

    @Test func testS015_S016TypedInputLimitsUseUTF16AndDoNotSplitSurrogates() {
        #expect(FeedbackPresentation.limitedInput("", utf16Limit: 254).isEmpty)
        #expect(FeedbackPresentation.limitedInput("hello", utf16Limit: 5) == "hello")
        #expect(FeedbackPresentation.limitedInput("hello!", utf16Limit: 5) == "hello")
        #expect(FeedbackPresentation.limitedInput("😀😀a", utf16Limit: 4) == "😀😀")
        #expect(FeedbackPresentation.limitedInput("😀😀", utf16Limit: 3) == "😀")
        #expect(FeedbackPresentation.limitedInput("e\u{301}e\u{301}", utf16Limit: 3) == "e\u{301}e")
        #expect(FeedbackPresentation.limitedInput(String(repeating: "x", count: 255), utf16Limit: 254).utf16.count == 254)
        #expect(FeedbackPresentation.limitedInput(String(repeating: "😀", count: 2501), utf16Limit: 5000).utf16.count == 5000)
    }
}
}
