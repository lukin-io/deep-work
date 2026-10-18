import AppKit
import SwiftUI
import Testing
@testable import DeepWorkApp

extension NativeApplicationTests {
@Suite(.serialized)
@MainActor
struct FocusPresentationTests {
    @Test(arguments: [false, true])
    func testF015NativeProgressControlUsesExplicitMotionPolicy(_ reduceMotion: Bool) async throws {
        prepareNativeTestApplication()
        let progress = FocusProgressView(fraction: 0.374, reduceMotion: reduceMotion)
        #expect((progress.animation == nil) == reduceMotion)
        let host = NSHostingView(rootView: progress.padding(20).frame(width: 320, height: 80))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 320, height: 80),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = host
        window.orderFront(nil)
        defer { window.orderOut(nil) }
        let partialControl = try await progressIndicator(in: host, showing: 0.374)
        let partialPixels = try renderedPixels(in: partialControl)
        host.rootView = FocusProgressView(fraction: 1, reduceMotion: reduceMotion)
            .padding(20).frame(width: 320, height: 80)
        let completedControl = try await progressIndicator(in: host, showing: 1)
        let completedPixels = try renderedPixels(in: completedControl)
        if let partialPixels, let completedPixels {
            // Equal nonempty snapshots are a failure, never a capability check.
            #expect(partialPixels != completedPixels)
            print("F-015: native progress pixels are nontransparent and change from partial to complete (reduceMotion=\(reduceMotion)).")
        } else {
            #expect((partialPixels == nil) == (completedPixels == nil))
            print("F-015: native layer snapshot is unavailable/fully transparent on this runner (reduceMotion=\(reduceMotion)); control state passed, pixel appearance is unverified here. See recorded UI-16 acceptance.")
        }

        // Mandatory evidence is the production view's real AppKit progress
        // control, including both input values and the explicit motion policy.
        // ImageRenderer substitutes placeholders for AppKit-backed controls;
        // hosting-view bitmap caches can omit layer-composited content. Core
        // Animation capture is supplementary only when pixels actually exist.
        // This does not change or verify macOS preferences or animated timing.
        // External visual/AX acceptance (dw-progress, Time remaining, timer
        // values, and distinct leaf identifiers) is UI-16 in VERIFICATION.md.
    }

    @Test func testF015ProgressClampsInvalidFractionsBeforeRendering() {
        for fraction in [-0.5, -Double.infinity, Double.infinity, Double.nan] {
            #expect(FocusProgressView(fraction: fraction, reduceMotion: true).fraction == 0)
        }
        #expect(FocusProgressView(fraction: 1.5, reduceMotion: false).fraction == 1)
        #expect(FocusProgressView(fraction: 0.5, reduceMotion: false).fraction == 0.5)
    }

    private func progressIndicator(in host: NSView, showing expectedValue: Double) async throws -> NSProgressIndicator {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: .seconds(3))
        // Synchronize with SwiftUI's observable native value, not an assumed
        // animation duration or the runner's rendering speed.
        while clock.now < deadline {
            host.layoutSubtreeIfNeeded()
            if let control = findProgressIndicator(in: host), abs(control.doubleValue - expectedValue) < 0.000_001 {
                #expect(!control.isIndeterminate)
                #expect(control.style == .bar)
                #expect(control.minValue == 0 && control.maxValue == 1)
                #expect(!control.isHiddenOrHasHiddenAncestor)
                #expect(control.window?.isVisible == true)
                #expect(control.bounds.width > 0 && control.bounds.height > 0)
                control.displayIfNeeded()
                return control
            }
            try await Task.sleep(for: .milliseconds(10))
        }
        let control = try #require(findProgressIndicator(in: host), "Expected the production view to create a native progress control")
        try #require(abs(control.doubleValue - expectedValue) < 0.000_001,
                     "Native progress control did not receive the new fraction before the deadline")
        return control
    }

    private func findProgressIndicator(in view: NSView) -> NSProgressIndicator? {
        if let control = view as? NSProgressIndicator { return control }
        return view.subviews.lazy.compactMap { self.findProgressIndicator(in: $0) }.first
    }

    private func renderedPixels(in control: NSProgressIndicator) throws -> Data? {
        guard let layer = control.layer else { return nil }
        layer.displayIfNeeded()
        let width = Int(ceil(control.bounds.width))
        let height = Int(ceil(control.bounds.height))
        let bytesPerRow = width * 4
        let context = try #require(CGContext(data: nil, width: width, height: height,
                                            bitsPerComponent: 8, bytesPerRow: bytesPerRow,
                                            space: CGColorSpaceCreateDeviceRGB(),
                                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue |
                                                CGBitmapInfo.byteOrder32Big.rawValue))
        context.clear(CGRect(x: 0, y: 0, width: width, height: height))
        // Apple's model-layer renderer ignores in-flight animations and avoids
        // the SwiftUI hosting view's unsupported bitmap caching path.
        layer.render(in: context)
        let bytes = try #require(context.data).assumingMemoryBound(to: UInt8.self)
        let count = bytesPerRow * height
        guard stride(from: 3, to: count, by: 4).contains(where: { bytes[$0] > 0 }) else { return nil }
        return Data(bytes: bytes, count: count)
    }
}
}
