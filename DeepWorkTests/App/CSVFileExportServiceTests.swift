import AppKit
import Foundation
import Testing
import UniformTypeIdentifiers
@testable import DeepWorkApp

extension NativeApplicationTests {
@Suite(.serialized, .timeLimit(.minutes(1)))
@MainActor
struct CSVFileExportServiceTests {
    private let bytes = Data([0xEF, 0xBB, 0xBF]) + Data("\"Data\",\"Schedule\"\r\n\"Journal\",\"Focus, \"\"quiet\"\" 🧠\"".utf8)

    private func directory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("DeepWorkCSV-\(UUID())")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false,
                                                attributes: [.posixPermissions: 0o700])
        return url
    }

    @Test func testJ050_S009NativePanelUsesCSVTypeAndSuggestedFilename() {
        prepareNativeTestApplication()
        let filename = "deep-work-example-2026-10-19-to-2026-10-20.csv"
        let panel = NativeCSVSaveDestinationChooser.makePanel(suggestedFilename: filename)
        #expect(panel.title == "Export CSV" && panel.prompt == "Save")
        #expect(panel.nameFieldStringValue == filename)
        #expect(panel.allowedContentTypes == [.commaSeparatedText])
        #expect(!panel.allowsOtherFileTypes && panel.canCreateDirectories)
        #expect(!panel.isExtensionHidden)
        #expect(!panel.isVisible) // Configuration does not open a modal UI in the hostless test.
    }

    @Test func testJ048_S009_AC23NativeResponseRequiresOKAndAFileDestination() throws {
        let file = URL(fileURLWithPath: "/unused-report.csv")
        #expect(try NativeCSVSaveDestinationChooser.destination(response: .OK, selectedURL: file) == file)
        #expect(try NativeCSVSaveDestinationChooser.destination(response: .cancel, selectedURL: file) == nil)
        #expect(try NativeCSVSaveDestinationChooser.destination(response: .cancel, selectedURL: nil) == nil)
        #expect(try NativeCSVSaveDestinationChooser.destination(response: .abort, selectedURL: file) == nil)
        #expect(throws: (any Error).self) {
            try NativeCSVSaveDestinationChooser.destination(response: .OK, selectedURL: nil)
        }
        let remote = try #require(URL(string: "https://example.invalid/report.csv"))
        #expect(throws: (any Error).self) {
            try NativeCSVSaveDestinationChooser.destination(response: .OK, selectedURL: remote)
        }
    }

    @Test func testJ048_S009_AC23CancelNeverWrites() async {
        let chooser = FixtureCSVSaveDestinationChooser(selectedURL: nil)
        let writer = RecordingCSVFileWriter()
        let service = NativeCSVFileExportService(destinationChooser: chooser, writer: writer)
        #expect(await service.save(data: bytes, suggestedFilename: "report.csv") == .cancelled)
        #expect(chooser.filenames == ["report.csv"])
        #expect(await writer.writes.isEmpty)
    }

    @Test func testJ048_S011_AC23DestinationFailureNeverWritesOrReportsSuccess() async {
        let chooser = FixtureCSVSaveDestinationChooser(selectedURL: nil, failure: FixtureCSVFailure.selection)
        let writer = RecordingCSVFileWriter()
        let service = NativeCSVFileExportService(destinationChooser: chooser, writer: writer)
        let result = await service.save(data: bytes, suggestedFilename: "report.csv")
        #expect(result == .failed("Test destination unavailable."))
        #expect(await writer.writes.isEmpty)
    }

    @Test func testJ048_S009NonFileDestinationNeverReachesWriter() async throws {
        let remote = try #require(URL(string: "https://example.invalid/report.csv"))
        let chooser = FixtureCSVSaveDestinationChooser(selectedURL: remote)
        let writer = RecordingCSVFileWriter()
        let result = await NativeCSVFileExportService(destinationChooser: chooser, writer: writer)
            .save(data: bytes, suggestedFilename: "report.csv")
        #expect(result == .failed("Choose a file destination and try again."))
        #expect(await writer.writes.isEmpty)
    }

    @Test func testJ048_J049_S010_AC23ActualDiskSavePreservesEveryByte() async throws {
        let directory = try directory(); defer { try? FileManager.default.removeItem(at: directory) }
        let destination = directory.appendingPathComponent("report.csv")
        let chooser = FixtureCSVSaveDestinationChooser(selectedURL: destination)
        let result = await NativeCSVFileExportService(destinationChooser: chooser)
            .save(data: bytes, suggestedFilename: "report.csv")
        #expect(result == .saved(destination))
        #expect(try Data(contentsOf: destination) == bytes)
        #expect(try FileManager.default.contentsOfDirectory(atPath: directory.path) == ["report.csv"])
    }

    @Test func testJ048_S010_AC23ActualDiskReplacementLeavesOnlyCompleteNewBytes() async throws {
        let directory = try directory(); defer { try? FileManager.default.removeItem(at: directory) }
        let destination = directory.appendingPathComponent("report.csv")
        try Data("longer old data must not remain after replacing this CSV".utf8).write(to: destination)
        let chooser = FixtureCSVSaveDestinationChooser(selectedURL: destination)
        let result = await NativeCSVFileExportService(destinationChooser: chooser)
            .save(data: bytes, suggestedFilename: "report.csv")
        #expect(result == .saved(destination))
        #expect(try Data(contentsOf: destination) == bytes)
        #expect(try FileManager.default.contentsOfDirectory(atPath: directory.path) == ["report.csv"])
    }

    @Test func testJ048_S011_AC23ActualWriteFailurePreservesExistingDirectoryContents() async throws {
        let directory = try directory(); defer { try? FileManager.default.removeItem(at: directory) }
        let existingFile = directory.appendingPathComponent("keep.csv")
        let original = Data("previous report".utf8)
        try original.write(to: existingFile)
        let chooser = FixtureCSVSaveDestinationChooser(selectedURL: directory)
        let result = await NativeCSVFileExportService(destinationChooser: chooser)
            .save(data: bytes, suggestedFilename: "report.csv")
        guard case let .failed(message) = result else {
            Issue.record("Writing to an existing directory must fail, not report a saved file")
            return
        }
        #expect(!message.isEmpty)
        #expect(try Data(contentsOf: existingFile) == original)
        #expect(try FileManager.default.contentsOfDirectory(atPath: directory.path) == ["keep.csv"])
    }

    @Test func testJ048_S011_AC23UnavailableParentDoesNotCreateOrClaimFile() async throws {
        let directory = try directory(); defer { try? FileManager.default.removeItem(at: directory) }
        let destination = directory.appendingPathComponent("missing/report.csv")
        let chooser = FixtureCSVSaveDestinationChooser(selectedURL: destination)
        let result = await NativeCSVFileExportService(destinationChooser: chooser)
            .save(data: bytes, suggestedFilename: "report.csv")
        guard case .failed = result else { Issue.record("Missing parent must produce a write failure"); return }
        #expect(!FileManager.default.fileExists(atPath: destination.path))
        #expect(try FileManager.default.contentsOfDirectory(atPath: directory.path).isEmpty)
    }

    @Test func testJ048_S011_AC23FailedAtomicReplacementPreservesExistingFile() async throws {
        let directory = try directory()
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
            try? FileManager.default.removeItem(at: directory)
        }
        let destination = directory.appendingPathComponent("report.csv")
        let original = Data("original report must survive a failed replacement".utf8)
        try original.write(to: destination)
        // The file itself remains writable. A non-atomic truncating write could
        // overwrite it, but atomic replacement needs a writable parent folder.
        try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: directory.path)
        let chooser = FixtureCSVSaveDestinationChooser(selectedURL: destination)
        let result = await NativeCSVFileExportService(destinationChooser: chooser)
            .save(data: bytes, suggestedFilename: "report.csv")
        guard case .failed = result else { Issue.record("Read-only parent must reject atomic replacement"); return }
        #expect(try Data(contentsOf: destination) == original)
        #expect(try FileManager.default.contentsOfDirectory(atPath: directory.path) == ["report.csv"])
    }

    @Test func testJ048_S011_AC23SuccessWaitsForWriteWithoutBlockingMainActor() async {
        let destination = URL(fileURLWithPath: "/unused-report.csv")
        let chooser = FixtureCSVSaveDestinationChooser(selectedURL: destination)
        let writer = SuspendedCSVFileWriter()
        let service = NativeCSVFileExportService(destinationChooser: chooser, writer: writer)
        var completed = false
        let task = Task { @MainActor in
            let result = await service.save(data: bytes, suggestedFilename: "report.csv")
            completed = true
            return result
        }
        await writer.waitUntilStarted()
        #expect(!completed)
        #expect(await writer.receivedData == bytes)
        await writer.finish()
        #expect(await task.value == .saved(destination))
        #expect(completed)
    }

    @Test func testJ048_S009CancelledTaskBeforeSelectionDoesNotOpenPanelOrWrite() async {
        let chooser = FixtureCSVSaveDestinationChooser(selectedURL: URL(fileURLWithPath: "/unused-report.csv"))
        let writer = RecordingCSVFileWriter()
        let service = NativeCSVFileExportService(destinationChooser: chooser, writer: writer)
        let task = Task { @MainActor in await service.save(data: bytes, suggestedFilename: "report.csv") }
        task.cancel()
        #expect(await task.value == .cancelled)
        #expect(chooser.filenames.isEmpty)
        #expect(await writer.writes.isEmpty)
    }

    @Test func testJ048_S009CancelledTaskAfterSelectionDoesNotWrite() async {
        let chooser = FixtureCSVSaveDestinationChooser(selectedURL: URL(fileURLWithPath: "/unused-report.csv"),
                                                       cancelOnSelection: true)
        let writer = RecordingCSVFileWriter()
        let service = NativeCSVFileExportService(destinationChooser: chooser, writer: writer)
        let task = Task { @MainActor in await service.save(data: bytes, suggestedFilename: "report.csv") }
        #expect(await task.value == .cancelled)
        #expect(chooser.filenames == ["report.csv"])
        #expect(await writer.writes.isEmpty)
    }

    @Test func testJ048_S011WriteAlreadyCompletedIsNotMisreportedAsCancellation() async {
        let destination = URL(fileURLWithPath: "/unused-report.csv")
        let chooser = FixtureCSVSaveDestinationChooser(selectedURL: destination)
        let writer = SuspendedCSVFileWriter()
        let service = NativeCSVFileExportService(destinationChooser: chooser, writer: writer)
        let task = Task { @MainActor in await service.save(data: bytes, suggestedFilename: "report.csv") }
        await writer.waitUntilStarted()
        task.cancel()
        await writer.finish()
        #expect(await task.value == .saved(destination))
    }

    @Test func testJ048_S009QuitWithoutPendingExportReturnsImmediatelyAndAllowsNextSave() async {
        let destination = URL(fileURLWithPath: "/unused-report.csv")
        let chooser = FixtureCSVSaveDestinationChooser(selectedURL: destination)
        let service = NativeCSVFileExportService(destinationChooser: chooser, writer: RecordingCSVFileWriter())
        #expect(await service.prepareForTermination() == nil)
        #expect(await service.save(data: bytes, suggestedFilename: "report.csv") == .saved(destination))
        #expect(await service.prepareForTermination() == nil)
    }

    @Test func testJ048_S011QuitDrainsAcceptedWriteAndReturnsItsActualOutcome() async {
        for shouldFail in [false, true] {
            let destination = URL(fileURLWithPath: "/unused-report.csv")
            let chooser = FixtureCSVSaveDestinationChooser(selectedURL: destination)
            let writer = SuspendedCSVFileWriter()
            let service = NativeCSVFileExportService(destinationChooser: chooser, writer: writer)
            let saving = Task { @MainActor in await service.save(data: bytes, suggestedFilename: "report.csv") }
            await writer.waitUntilStarted()
            var finishedQuitPreparation = false
            let quitting = Task { @MainActor in
                let result = await service.prepareForTermination()
                finishedQuitPreparation = true
                return result
            }
            for _ in 0..<20 { await Task.yield() }
            #expect(!finishedQuitPreparation)
            await writer.finish(failure: shouldFail ? .write : nil)
            let expected = shouldFail ? CSVFileExportResult.failed("Test file write failed.") : .saved(destination)
            #expect(await saving.value == expected)
            #expect(await quitting.value == expected)
            #expect(finishedQuitPreparation)
        }
    }

    @Test func testJ048_S009QuitCancelsDestinationSelectionWithoutWaitingOrWriting() async {
        let chooser = SuspendedCSVSaveDestinationChooser()
        let writer = RecordingCSVFileWriter()
        let service = NativeCSVFileExportService(destinationChooser: chooser, writer: writer)
        let saving = Task { @MainActor in await service.save(data: bytes, suggestedFilename: "report.csv") }
        await chooser.waitUntilChoosing()
        #expect(await service.prepareForTermination() == nil)
        #expect(chooser.cancellations == 1)
        chooser.finish(nil) // Also completes safely if the cancellation regression fails.
        #expect(await saving.value == .cancelled)
        #expect(await writer.writes.isEmpty)
    }

    @Test func testJ048_S009LateDestinationAfterQuitCannotStartWriteAndRetryCanSave() async {
        let destination = URL(fileURLWithPath: "/unused-report.csv")
        let chooser = SuspendedCSVSaveDestinationChooser(resumeOnCancel: false)
        let writer = RecordingCSVFileWriter()
        let service = NativeCSVFileExportService(destinationChooser: chooser, writer: writer)
        let saving = Task { @MainActor in await service.save(data: bytes, suggestedFilename: "report.csv") }
        await chooser.waitUntilChoosing()
        #expect(await service.prepareForTermination() == nil)
        #expect(chooser.cancellations == 1)
        chooser.finish(destination)
        #expect(await saving.value == .cancelled)
        #expect(await writer.writes.isEmpty)

        let retry = Task { @MainActor in await service.save(data: bytes, suggestedFilename: "retry.csv") }
        await chooser.waitUntilChoosing()
        chooser.finish(destination)
        #expect(await retry.value == .saved(destination))
        #expect(await writer.writes.count == 1)
    }
}
}

@MainActor
private final class FixtureCSVSaveDestinationChooser: CSVSaveDestinationChoosing {
    let selectedURL: URL?
    let failure: (any Error)?
    let cancelOnSelection: Bool
    var filenames: [String] = []

    init(selectedURL: URL?, failure: (any Error)? = nil, cancelOnSelection: Bool = false) {
        self.selectedURL = selectedURL; self.failure = failure; self.cancelOnSelection = cancelOnSelection
    }

    func chooseDestination(suggestedFilename: String) async throws -> URL? {
        filenames.append(suggestedFilename)
        if let failure { throw failure }
        if cancelOnSelection { withUnsafeCurrentTask { $0?.cancel() } }
        return selectedURL
    }
}

private enum FixtureCSVFailure: LocalizedError {
    case selection
    case write
    var errorDescription: String? {
        switch self {
        case .selection: return "Test destination unavailable."
        case .write: return "Test file write failed."
        }
    }
}

@MainActor
private final class SuspendedCSVSaveDestinationChooser: CSVSaveDestinationChoosing {
    private let resumeOnCancel: Bool
    private var completion: CheckedContinuation<URL?, Never>?
    private(set) var cancellations = 0

    init(resumeOnCancel: Bool = true) { self.resumeOnCancel = resumeOnCancel }

    func chooseDestination(suggestedFilename: String) async throws -> URL? {
        await withCheckedContinuation { completion = $0 }
    }

    func waitUntilChoosing() async {
        while completion == nil { await Task.yield() }
    }

    func cancelPendingSelection() {
        cancellations += 1
        if resumeOnCancel { finish(nil) }
    }

    func finish(_ destination: URL?) { completion?.resume(returning: destination); completion = nil }
}

private actor RecordingCSVFileWriter: CSVFileWriting {
    var writes: [Data] = []
    func write(_ data: Data, to destination: URL) { writes.append(data) }
}

private actor SuspendedCSVFileWriter: CSVFileWriting {
    var receivedData: Data?
    private var startedWaiter: CheckedContinuation<Void, Never>?
    private var completion: CheckedContinuation<Void, Never>?
    private var failure: FixtureCSVFailure?

    func write(_ data: Data, to destination: URL) async throws {
        receivedData = data
        await withCheckedContinuation { continuation in
            completion = continuation
            startedWaiter?.resume(); startedWaiter = nil
        }
        if let failure { throw failure }
    }

    func waitUntilStarted() async {
        if completion != nil { return }
        await withCheckedContinuation { startedWaiter = $0 }
    }

    func finish(failure: FixtureCSVFailure? = nil) {
        self.failure = failure
        completion?.resume(); completion = nil
    }
}
