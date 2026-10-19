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
        #expect(throws: FeedbackValidationError.email) {
            try FeedbackDraft(email: "bad", message: "").validatedForSaving()
        }
    }

    @Test func testS014_S015_S016_S019ClipboardPayloadUsesMappedTypesOptionalEmailAndTrimmedText() throws {
        let names: [(FeedbackType, String)] = [(.idea, "Suggestion"), (.problem, "Problem report"), (.general, "General feedback")]
        for (type, name) in names {
            for email in ["", " \tperson@example.com\n"] {
                let draft = FeedbackDraft(type: type, email: email, message: " \u{FEFF}hello 😀\nsecond line\n ")
                let emailLine = email.isEmpty ? "" : "\nEmail: person@example.com"
                #expect(try draft.validatedClipboardText() == "Deep Work feedback\nType: \(name)\(emailLine)\n\nhello 😀\nsecond line")
                #expect(draft.message.hasPrefix(" \u{FEFF}"), "Preparing feedback must not mutate unsaved form edits")
            }
        }
        #expect(try FeedbackDraft(email: " \t\n", message: "hello").validatedClipboardText()
            == "Deep Work feedback\nType: General feedback\n\nhello")
    }

    @Test func testS017_S019ClipboardUsesSameValidationAndErrorPriorityAsSaving() {
        for draft in [FeedbackDraft(email: "bad", message: ""), FeedbackDraft(email: "bad", message: "hello")] {
            #expect(throws: FeedbackValidationError.email) { try draft.validatedClipboardText() }
        }
        for message in ["", "  ", "😀😀", String(repeating: "a", count: 5001)] {
            #expect(throws: FeedbackValidationError.message) { try FeedbackDraft(message: message).validatedClipboardText() }
        }
        #expect(FeedbackValidationError.email.localizedDescription == "Enter a valid email address, or leave it blank.")
        #expect(FeedbackValidationError.message.localizedDescription == "Write a message between 5 and 5,000 characters.")
    }

    @Test func testUnknownFeedbackTypeFallsBackWithoutChangingSavedText() throws {
        for typeField in [#""type":"future","#, #""type":null,"#, ""] {
            let bytes = Data("{\"version\":1,\"launchAtLogin\":false,\"feedbackDraft\":{\(typeField)\"email\":\"\",\"message\":\"hello\"}}".utf8)
            let settings = try JSONDecoder().decode(SettingsDocument.self, from: bytes)
            try settings.validate()
            #expect(settings.feedbackDraft.type == .general)
            #expect(settings.feedbackDraft.message == "hello")
        }
    }
}
