import AppKit
import Foundation
import UniformTypeIdentifiers

enum CSVFileExportResult: Equatable, Sendable {
    case saved(URL)
    case cancelled
    case failed(String)
}

@MainActor
protocol CSVFileExporting {
    func save(data: Data, suggestedFilename: String) async -> CSVFileExportResult
    func prepareForTermination() async -> CSVFileExportResult?
}

extension CSVFileExporting {
    func prepareForTermination() async -> CSVFileExportResult? { nil }
}

@MainActor
protocol CSVSaveDestinationChoosing {
    func chooseDestination(suggestedFilename: String) async throws -> URL?
    func cancelPendingSelection()
}

extension CSVSaveDestinationChoosing {
    func cancelPendingSelection() {}
}

protocol CSVFileWriting: Sendable {
    func write(_ data: Data, to destination: URL) async throws
}

/// Keep the AppKit destination selection on MainActor and the file operation on
/// a separate actor. The caller owns the immutable report snapshot and UI state.
@MainActor
final class NativeCSVFileExportService: CSVFileExporting {
    private let destinationChooser: any CSVSaveDestinationChoosing
    private let writer: any CSVFileWriting
    private var selectionRevision = 0
    private var pendingWrite: Task<CSVFileExportResult, Never>?

    init(destinationChooser: (any CSVSaveDestinationChoosing)? = nil,
         writer: any CSVFileWriting = AtomicCSVFileWriter()) {
        self.destinationChooser = destinationChooser ?? NativeCSVSaveDestinationChooser()
        self.writer = writer
    }

    func save(data: Data, suggestedFilename: String) async -> CSVFileExportResult {
        let revision = selectionRevision
        do {
            try Task.checkCancellation()
            guard let destination = try await destinationChooser.chooseDestination(suggestedFilename: suggestedFilename) else {
                return .cancelled
            }
            try Task.checkCancellation()
            guard revision == selectionRevision else { return .cancelled }
            guard destination.isFileURL else { throw CSVFileExportError.invalidDestination }
            let write = Task { [writer] in
                do {
                    try await writer.write(data, to: destination)
                    return CSVFileExportResult.saved(destination)
                } catch { return .failed(error.localizedDescription) }
            }
            pendingWrite = write
            let result = await write.value
            pendingWrite = nil
            // Once Save was accepted, complete the write even if the caller
            // cancels. Quit waits on the same task and sees its actual result.
            return result
        } catch is CancellationError {
            return .cancelled
        } catch {
            return .failed(error.localizedDescription)
        }
    }

    func prepareForTermination() async -> CSVFileExportResult? {
        // Invalidate only the current destination request. A failed Quit can
        // leave the app open, and a later explicit export must remain usable.
        selectionRevision &+= 1
        destinationChooser.cancelPendingSelection()
        return await pendingWrite?.value
    }
}

@MainActor
final class NativeCSVSaveDestinationChooser: CSVSaveDestinationChoosing {
    private var activePanel: NSSavePanel?

    func chooseDestination(suggestedFilename: String) async throws -> URL? {
        let panel = Self.makePanel(suggestedFilename: suggestedFilename)
        activePanel = panel
        defer { if activePanel === panel { activePanel = nil } }
        let response: NSApplication.ModalResponse = await withCheckedContinuation { continuation in
            if let window = NSApp.mainWindow ?? NSApp.keyWindow {
                panel.beginSheetModal(for: window) { response in continuation.resume(returning: response) }
            } else {
                panel.begin { response in continuation.resume(returning: response) }
            }
        }
        return try Self.destination(response: response, selectedURL: panel.url)
    }

    func cancelPendingSelection() { activePanel?.cancel(nil) }

    static func makePanel(suggestedFilename: String) -> NSSavePanel {
        let panel = NSSavePanel()
        panel.title = "Export CSV"
        panel.prompt = "Save"
        panel.nameFieldStringValue = suggestedFilename
        panel.allowedContentTypes = [.commaSeparatedText]
        panel.allowsOtherFileTypes = false
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false
        return panel
    }

    static func destination(response: NSApplication.ModalResponse, selectedURL: URL?) throws -> URL? {
        guard response == .OK else { return nil }
        guard let selectedURL, selectedURL.isFileURL else { throw CSVFileExportError.invalidDestination }
        return selectedURL
    }
}

/// A failed atomic replacement leaves an existing destination intact. Disk I/O
/// does not run on MainActor and reports success only when Foundation returns.
actor AtomicCSVFileWriter: CSVFileWriting {
    func write(_ data: Data, to destination: URL) throws {
        guard destination.isFileURL else { throw CSVFileExportError.invalidDestination }
        try data.write(to: destination, options: .atomic)
    }
}

private enum CSVFileExportError: LocalizedError {
    case invalidDestination

    var errorDescription: String? {
        "Choose a file destination and try again."
    }
}
