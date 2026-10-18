import Foundation

public enum DurationSelection: Codable, Equatable, Hashable, Sendable {
    case unselected
    case preset(Int)
    case custom
}

/// Setup preferences remain separate from a running pair's duration snapshot.
public struct FocusConfiguration: Codable, Equatable, Sendable {
    public var focusSelection: DurationSelection
    public var breakSelection: DurationSelection
    public var customFocusMinutes: Int
    public var customBreakMinutes: Int
    public var repeats: Bool

    public init(focusSelection: DurationSelection = .unselected,
                breakSelection: DurationSelection = .unselected,
                customFocusMinutes: Int = 75, customBreakMinutes: Int = 15,
                repeats: Bool = true) {
        self.focusSelection = focusSelection
        self.breakSelection = breakSelection
        self.customFocusMinutes = customFocusMinutes
        self.customBreakMinutes = customBreakMinutes
        self.repeats = repeats
    }

    public var resolvedFocusMinutes: Int? {
        resolve(focusSelection, custom: customFocusMinutes, presets: [60, 90])
    }
    public var resolvedBreakMinutes: Int? {
        resolve(breakSelection, custom: customBreakMinutes, presets: [10, 20])
    }
    public var canStart: Bool { resolvedFocusMinutes != nil && resolvedBreakMinutes != nil }

    public func validate() throws {
        try require((1...480).contains(customFocusMinutes), "Custom focus minutes must be between 1 and 480.")
        try require((1...480).contains(customBreakMinutes), "Custom break minutes must be between 1 and 480.")
        if case .preset(let value) = focusSelection {
            try require([60, 90].contains(value), "The focus preset is unsupported.")
        }
        if case .preset(let value) = breakSelection {
            try require([10, 20].contains(value), "The break preset is unsupported.")
        }
    }

    private func resolve(_ selection: DurationSelection, custom: Int, presets: [Int]) -> Int? {
        switch selection {
        case .unselected: return nil
        case .preset(let minutes): return presets.contains(minutes) ? minutes : nil
        case .custom: return (1...480).contains(custom) ? custom : nil
        }
    }
}
