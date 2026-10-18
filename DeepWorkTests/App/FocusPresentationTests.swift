import AppKit
import SwiftUI
import Testing
@testable import DeepWorkApp

extension NativeApplicationTests {
@Suite(.serialized)
@MainActor
struct FocusPresentationTests {
    @Test(arguments: [false, true])
    func testF015NativeProgressRenderingUsesExplicitMotionPolicy(_ reduceMotion: Bool) async throws {
        prepareNativeTestApplication()
        let progress = FocusProgressView(fraction: 0.374, reduceMotion: reduceMotion)
        #expect((progress.animation == nil) == reduceMotion)
        let host = NSHostingView(rootView: progress.padding(20).frame(width: 320, height: 80))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 320, height: 80),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = host
        window.orderFront(nil)
        defer { window.orderOut(nil) }
        try await Task.sleep(nanoseconds: 100_000_000)
        let partialPixels = try renderedPixels(in: host)
        host.rootView = FocusProgressView(fraction: 1, reduceMotion: reduceMotion)
            .padding(20).frame(width: 320, height: 80)
        try await Task.sleep(nanoseconds: 300_000_000)
        let completedPixels = try renderedPixels(in: host)
        #expect(partialPixels != completedPixels)

        // This tests the production component's explicit preference input and
        // actual native pixels. It does not change or verify macOS settings.
        // In this hostless Swift Testing runner NSHostingView returns no AX
        // children, even after supported application initialization. Public
        // external AX acceptance for dw-progress, Time remaining, timer values,
        // and distinct leaf identifiers is recorded as UI-16 in VERIFICATION.md.
    }

    @Test func testF015ProgressClampsInvalidFractionsBeforeRendering() {
        for fraction in [-0.5, -Double.infinity, Double.infinity, Double.nan] {
            #expect(FocusProgressView(fraction: fraction, reduceMotion: true).fraction == 0)
        }
        #expect(FocusProgressView(fraction: 1.5, reduceMotion: false).fraction == 1)
        #expect(FocusProgressView(fraction: 0.5, reduceMotion: false).fraction == 0.5)
    }

    private func renderedPixels<Content: View>(in host: NSHostingView<Content>) throws -> Data {
        host.layoutSubtreeIfNeeded()
        let image = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: image)
        #expect(image.pixelsWide > 0 && image.pixelsHigh > 0)
        let pixels = try #require(image.bitmapData)
        return Data(bytes: pixels, count: image.bytesPerRow * image.pixelsHigh)
    }
}
}
