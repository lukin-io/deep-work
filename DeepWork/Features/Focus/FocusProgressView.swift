import SwiftUI

/// The caller supplies the native Reduce Motion preference. Keeping that input
/// explicit also permits native rendering tests without changing macOS settings.
struct FocusProgressView: View {
    let fraction: Double
    let reduceMotion: Bool

    init(fraction: Double, reduceMotion: Bool) {
        self.fraction = fraction.isFinite ? min(1, max(0, fraction)) : 0
        self.reduceMotion = reduceMotion
    }

    var animation: Animation? { reduceMotion ? nil : .linear(duration: 0.2) }

    var body: some View {
        ProgressView(value: fraction).progressViewStyle(.linear)
            .accessibilityLabel("Cycle progress")
            .accessibilityValue("\(Int((fraction * 100).rounded())) percent")
            .accessibilityIdentifier("dw-progress")
            .animation(animation, value: fraction)
    }
}
