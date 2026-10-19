#if DEBUG
import AppKit
import Testing
@testable import DeepWorkApp

struct DebugAcceptanceOptionsTests {
    @Test(arguments: [nil, ""] as [String?])
    func testAC29FixturesAreIgnoredWithoutIsolatedData(directory: String?) {
        var environment = ["DEEP_WORK_APPEARANCE": "dark", "DEEP_WORK_CLIPBOARD_FAILURE": "1", "DEEP_WORK_WINDOW_WIDTH": "320"]
        environment["DEEP_WORK_DATA_DIR"] = directory
        let options = DebugAcceptanceOptions(environment: environment)
        #expect(options.appearance == nil)
        #expect(!options.rejectsClipboardWrites)
        #expect(options.windowWidth == nil)
    }

    @Test func testAC29WindowWidthAcceptsOnlyBoundedIntegers() {
        for value in ["320", "696", "1600"] {
            #expect(DebugAcceptanceOptions(environment: ["DEEP_WORK_DATA_DIR": "/tmp/fixture", "DEEP_WORK_WINDOW_WIDTH": value]).windowWidth == CGFloat(Int(value)!))
        }
        for value in ["", "319", "1601", "320.5", "NaN", "-1"] {
            #expect(DebugAcceptanceOptions(environment: ["DEEP_WORK_DATA_DIR": "/tmp/fixture", "DEEP_WORK_WINDOW_WIDTH": value]).windowWidth == nil)
        }
    }

    @Test func testAC29AppearanceUsesOnlySupportedExplicitValues() {
        for (value, expected) in [("light", NSAppearance.Name.aqua), ("dark", .darkAqua)] {
            let options = DebugAcceptanceOptions(environment: ["DEEP_WORK_DATA_DIR": "/tmp/fixture", "DEEP_WORK_APPEARANCE": value])
            #expect(options.appearance == expected)
            #expect(!options.rejectsClipboardWrites)
        }
        for value in ["", "system", "invalid"] {
            let options = DebugAcceptanceOptions(environment: ["DEEP_WORK_DATA_DIR": "/tmp/fixture", "DEEP_WORK_APPEARANCE": value])
            #expect(options.appearance == nil)
        }
    }

    @Test @MainActor func testS019ClipboardFailureIsExplicitAndDoesNotWriteToPasteboard() throws {
        let options = DebugAcceptanceOptions(environment: ["DEEP_WORK_DATA_DIR": "/tmp/fixture", "DEEP_WORK_CLIPBOARD_FAILURE": "1"])
        let clipboard = try #require(options.clipboard)
        #expect(throws: FeedbackClipboardError.self) { try clipboard.copy("A 👩🏽‍💻 feedback message") }
        for value in ["", "0", "true"] {
            let normal = DebugAcceptanceOptions(environment: ["DEEP_WORK_DATA_DIR": "/tmp/fixture", "DEEP_WORK_CLIPBOARD_FAILURE": value])
            #expect(normal.clipboard == nil)
        }
    }
}
#endif
