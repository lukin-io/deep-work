import Foundation
import Testing
@testable import DeepWorkCore

final class FeedbackTests {
    @Test func testEmptyDefaultIsValidStoredStateButCannotBeSavedAsFeedback() throws {
        let settings = SettingsDocument()
        #expect(!(settings.launchAtLogin))
        #expect(settings.feedbackDraft == .empty)
        #expect(settings.feedbackDraft.type == .general)
        try settings.validate()
        #expect(throws: (any Error).self) { try settings.feedbackDraft.validatedForSaving() }
    }

    @Test func testMessageTrimsAndPreservesUTF16MinimumIncludingEmojiAndCombiningMarks() throws {
        let trimmed = try FeedbackDraft(type: .idea, email: " user@example.com ", message: " \u{FEFF}hello\n").validatedForSaving()
        #expect(trimmed == FeedbackDraft(type: .idea, email: "user@example.com", message: "hello"))
        for invalid in ["", "  ", "1234", "😀😀"] {
            #expect(throws: (any Error).self) { try FeedbackDraft(message: invalid).validatedForSaving() }
        }
        for valid in ["12345", "😀😀a", "😀😀😀", "e\u{301}e\u{301}a"] {
            #expect(try FeedbackDraft(message: valid).validatedForSaving().message == valid)
        }
    }

    @Test func testMaximumIsRawUTF16CountBeforeTrimming() throws {
        try FeedbackDraft(message: String(repeating: "a", count: 5000)).validatedForSaving().validateStored()
        try FeedbackDraft(message: String(repeating: "😀", count: 2500)).validatedForSaving().validateStored()
        #expect(throws: (any Error).self) { try FeedbackDraft(message: String(repeating: "a", count: 5001)).validatedForSaving() }
        #expect(throws: (any Error).self) { try FeedbackDraft(message: " " + String(repeating: "a", count: 5000)).validatedForSaving() }
        #expect(throws: (any Error).self) { try FeedbackDraft(message: String(repeating: "😀", count: 2501)).validatedForSaving() }
    }

    @Test func testOptionalEmailGrammarLengthAndErrorPriority() throws {
        for valid in ["", "person@example.com", "first+tag@example.co.uk", "a@localhost"] {
            try FeedbackDraft(email: valid, message: "hello").validatedForSaving().validateStored()
        }
        for invalid in ["hello", "a b@example.com", "a@-example.com", "a@example..com", "a@x.com,b@y.com", "ä@example.com"] {
            #expect(throws: (any Error).self) { try FeedbackDraft(email: invalid, message: "hello").validatedForSaving() }
        }
        let email254 = String(repeating: "a", count: 242) + "@example.com"
        #expect(email254.utf16.count == 254)
        #expect(throws: Never.self) { try FeedbackDraft(email: email254, message: "hello").validatedForSaving() }
        #expect(throws: (any Error).self) { try FeedbackDraft(email: "a" + email254, message: "hello").validatedForSaving() }
        #expect(throws: ModelValidationError("Enter a valid email address, or leave it blank.")) {
            try FeedbackDraft(email: "bad", message: "").validatedForSaving()
        }
    }

    @Test func testUnknownFeedbackTypeFallsBackWithoutChangingSavedText() throws {
        let bytes = Data(#"{"version":1,"launchAtLogin":false,"feedbackDraft":{"type":"future","email":"","message":"hello"}}"#.utf8)
        let settings = try JSONDecoder().decode(SettingsDocument.self, from: bytes)
        try settings.validate()
        #expect(settings.feedbackDraft.type == .general)
        #expect(settings.feedbackDraft.message == "hello")
    }
}
