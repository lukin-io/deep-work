import AppKit
import Foundation
import Testing
import DeepWorkCore
@testable import DeepWorkApp

@MainActor
final class RecordingFeedbackClipboard: FeedbackCopying {
    var copied: [String] = []
    var fails = false
    func copy(_ text: String) throws {
        if fails { throw FeedbackClipboardError.unavailable }
        copied.append(text)
    }
}

extension NativeApplicationTests {
@Suite(.serialized)
@MainActor
struct FeedbackIntegrationTests {
    private func directory() -> URL { FileManager.default.temporaryDirectory.appendingPathComponent("DeepWorkFeedback-\(UUID())") }
    private func app(_ directory: URL, clipboard: any FeedbackCopying) -> AppModel {
        AppModel(journalStore: JournalStore(directory: directory), settingsStore: SettingsStore(directory: directory),
                 automaticRefresh: false, feedbackClipboard: clipboard)
    }

    @Test func testS012_S018_S019_S020_AC25SaveACopyBAndRelaunchRestoresOnlyA() async throws {
        let directory = directory(); defer { try? FileManager.default.removeItem(at: directory) }
        let pasteboard = NSPasteboard.withUniqueName(); defer { pasteboard.releaseGlobally() }
        #expect(SettingsStore(directory: directory).save(SettingsDocument(launchAtLogin: true)) == nil)
        let model = app(directory, clipboard: FeedbackClipboard(pasteboard: pasteboard))
        #expect(model.feedbackStatus == nil)
        model.feedbackType = .idea; model.feedbackEmail = " one@example.com "; model.feedbackMessage = " Saved draft A "
        #expect(model.saveFeedbackDraft() == nil)
        await model.flushPersistence()
        #expect(model.feedbackStatus == "Draft saved on this device. Nothing has been sent.")
        #expect(model.settings.launchAtLogin)
        model.feedbackType = .problem; model.feedbackEmail = " two@example.com "; model.feedbackMessage = " Edited draft B\nwith details "
        #expect(model.feedbackStatus == nil)
        model.selectedTab = .journal; model.selectedTab = .settings
        #expect(model.copyFeedback() == .copy)
        #expect(pasteboard.string(forType: .string) == "Deep Work feedback\nType: Problem report\nEmail: two@example.com\n\nEdited draft B\nwith details")
        #expect(model.feedbackStatus == "Feedback copied. Nothing has been sent.")
        #expect(model.settings.feedbackDraft.message == "Saved draft A")
        #expect(model.feedbackMessage == " Edited draft B\nwith details ")
        #expect(await model.prepareForTermination())
        let restored = app(directory, clipboard: RecordingFeedbackClipboard())
        #expect(restored.feedbackMessage == "Saved draft A" && restored.feedbackType == .idea)
        #expect(restored.feedbackEmail == "one@example.com" && restored.settings.launchAtLogin)
        #expect(restored.feedbackStatus == "Your saved draft is ready.")
        restored.feedbackMessage = "Replacement draft C"; _ = restored.saveFeedbackDraft()
        await restored.flushPersistence()
        #expect(SettingsStore(directory: directory).load().value.feedbackDraft.message == "Replacement draft C")
        #expect(SettingsStore(directory: directory).load().value.launchAtLogin)
    }

    @Test func testS015_S017_AC24ValidationPriorityAndCorrectedRetryDoNotTouchClipboard() async throws {
        let directory = directory(); defer { try? FileManager.default.removeItem(at: directory) }
        let clipboard = RecordingFeedbackClipboard(); let model = app(directory, clipboard: clipboard)
        model.feedbackEmail = "invalid"; model.feedbackMessage = "bad"
        #expect(model.copyFeedback() == .email && model.saveFeedbackDraft() == .email)
        #expect(model.feedbackError == "Enter a valid email address, or leave it blank.")
        #expect(model.feedbackStatus == nil && clipboard.copied.isEmpty)
        model.feedbackEmail = ""
        #expect(model.feedbackError == nil)
        #expect(model.copyFeedback() == .message && model.saveFeedbackDraft() == .message)
        #expect(model.feedbackError == "Write a message between 5 and 5,000 characters.")
        model.feedbackMessage = " hello "
        #expect(model.copyFeedback() == .copy && model.feedbackError == nil)
        #expect(clipboard.copied == ["Deep Work feedback\nType: General feedback\n\nhello"])
        #expect(model.settings.feedbackDraft == .empty)
        model.feedbackType = .idea
        #expect(model.feedbackStatus == nil)
        await model.flushPersistence()
        #expect(SettingsStore(directory: directory).load().value.feedbackDraft == .empty)
    }

    @Test func testS018_S019_S020PendingSaveCannotOverwriteNewerCopyOrValidationResult() async throws {
        let directory = directory(); defer { try? FileManager.default.removeItem(at: directory) }
        let clipboard = RecordingFeedbackClipboard(); let model = app(directory, clipboard: clipboard)
        await model.flushPersistence()
        model.feedbackMessage = "Explicitly saved draft"
        _ = model.saveFeedbackDraft()
        // Do not yield MainActor: the SQLite worker's acknowledgment is pending.
        #expect(model.pendingSettingsWrites > 0)
        #expect(model.copyFeedback() == .copy)
        await model.flushPersistence()
        #expect(model.feedbackStatus == "Feedback copied. Nothing has been sent.")
        #expect(SettingsStore(directory: directory).load().value.feedbackDraft.message == "Explicitly saved draft")
        _ = model.saveFeedbackDraft()
        model.feedbackEmail = "invalid"
        #expect(model.copyFeedback() == .email)
        await model.flushPersistence()
        #expect(model.feedbackStatus == nil && model.feedbackError == FeedbackValidationError.email.localizedDescription)
    }

    @Test func testS018_S019_S021_AC27FailedSQLiteKeepsCopyAvailableAndExactFailureText() async throws {
        let directory = directory(); defer { try? FileManager.default.removeItem(at: directory) }
        try Data("not a directory".utf8).write(to: directory)
        let clipboard = RecordingFeedbackClipboard(); let model = app(directory, clipboard: clipboard)
        model.feedbackMessage = "Keep this edited message"
        _ = model.saveFeedbackDraft(); await model.flushPersistence()
        #expect(model.feedbackStatus == "Draft could not be saved. Use Copy Feedback to keep it.")
        #expect(model.copyFeedback() == .copy)
        #expect(clipboard.copied.count == 1 && clipboard.copied[0].hasSuffix("Keep this edited message"))
        #expect(model.settingsFailure != nil && model.journalFailure != nil)
        #expect(model.feedbackMessage == "Keep this edited message")
        #expect(!(await model.prepareForTermination()))
    }

    @Test func testS019_S020ClipboardFailureRequestsSelectionAndRetryPreservesSavedDraft() async throws {
        let directory = directory(); defer { try? FileManager.default.removeItem(at: directory) }
        let clipboard = RecordingFeedbackClipboard(); let model = app(directory, clipboard: clipboard)
        model.feedbackMessage = "Unsaved message to recover"
        clipboard.fails = true
        #expect(model.copyFeedback() == .selectMessage)
        #expect(model.feedbackStatus == "Copy is unavailable. Select and copy your message.")
        #expect(model.feedbackError == nil && model.feedbackMessage == "Unsaved message to recover")
        clipboard.fails = false
        #expect(model.copyFeedback() == .copy)
        #expect(model.feedbackStatus == "Feedback copied. Nothing has been sent.")
        await model.flushPersistence()
        #expect(SettingsStore(directory: directory).load().value.feedbackDraft == .empty)
    }

    @Test func testS016_S019ProgrammaticOverlongInputFailsAndQuitPreventsActions() async throws {
        let directory = directory(); defer { try? FileManager.default.removeItem(at: directory) }
        let clipboard = RecordingFeedbackClipboard(); let model = app(directory, clipboard: clipboard)
        model.feedbackMessage = String(repeating: "a", count: 5001)
        #expect(model.copyFeedback() == .message)
        model.feedbackMessage = String(repeating: "😀", count: 2500)
        #expect(model.copyFeedback() == .copy)
        #expect(clipboard.copied.count == 1)
        #expect(await model.prepareForTermination())
        #expect(model.copyFeedback() == nil && model.saveFeedbackDraft() == nil)
        #expect(clipboard.copied.count == 1 && model.settings.feedbackDraft == .empty)
    }
}
}
