#!/usr/bin/env swift
// Native bundle acceptance check; used by build-app.sh and icon regressions.
import AppKit
import Foundation
import ImageIO

struct IconValidationError: Error, CustomStringConvertible {
    let description: String
}

func require(_ condition: @autoclosure () -> Bool, _ message: String) throws {
    guard condition() else { throw IconValidationError(description: message) }
}

func pixelData(_ image: CGImage) throws -> Data {
    guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
          let context = CGContext(data: nil, width: image.width, height: image.height,
                                  bitsPerComponent: 8, bytesPerRow: image.width * 4,
                                  space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
          let bytes = context.data else {
        throw IconValidationError(description: "Cannot decode icon pixels.")
    }
    context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
    return Data(bytes: bytes, count: image.width * image.height * 4)
}

func validateIcon(at bundleURL: URL, against catalogURL: URL) throws {
    let infoURL = bundleURL.appendingPathComponent("Contents/Info.plist")
    let infoData = try Data(contentsOf: infoURL)
    let info = try PropertyListSerialization.propertyList(from: infoData, format: nil) as? [String: Any]
    let iconName = info?["CFBundleIconFile"] as? String
    try require(iconName == "AppIcon.icns" || iconName == "AppIcon", "CFBundleIconFile must name AppIcon.icns.")
    let iconURL = bundleURL.appendingPathComponent("Contents/Resources/AppIcon.icns")
    guard let source = CGImageSourceCreateWithURL(iconURL as CFURL, nil),
          let image = NSImage(contentsOf: iconURL) else {
        throw IconValidationError(description: "The bundle icon is missing or cannot be decoded by macOS.")
    }
    try require(CGImageSourceGetType(source) as String? == "com.apple.icns", "The bundle icon must be an ICNS resource.")

    // Pixel sizes alone cannot distinguish standard 32pt from Retina 16pt.
    // Check the logical point size AppKit will actually select as well.
    let expected = Set([16, 32, 128, 256, 512].flatMap { points in
        ["\(points):\(points)", "\(points):\(points * 2)"]
    })
    var actual = Set<String>()
    for representation in image.representations {
        try require(representation.pixelsWide == representation.pixelsHigh, "Icon representations must be square.")
        try require(representation.size.width == representation.size.height, "Icon point sizes must be square.")
        try require(representation.hasAlpha, "Icon representations must preserve transparency.")
        actual.insert("\(Int(representation.size.width)):\(representation.pixelsWide)")
    }
    try require(image.representations.count == 10 && actual == expected,
                "The icon must include all ten 16–512pt standard and Retina representations.")
    try require(CGImageSourceGetCount(source) == 10, "ImageIO must expose all ten icon representations.")
    for index in 0..<CGImageSourceGetCount(source) {
        try require(CGImageSourceCreateImageAtIndex(source, index, nil) != nil,
                    "Icon representation \(index) cannot be decoded.")
    }

    // Both build paths must ship the approved exports, not merely an arbitrary
    // well-formed icon. Compare every decoded pixel with Xcode's source catalog.
    let catalogData = try Data(contentsOf: catalogURL.appendingPathComponent("Contents.json"))
    let catalog = try JSONSerialization.jsonObject(with: catalogData) as? [String: Any]
    guard let entries = catalog?["images"] as? [[String: String]], entries.count == 10 else {
        throw IconValidationError(description: "AppIcon asset catalog must contain ten image entries.")
    }
    var catalogSlots = Set<String>()
    for entry in entries {
        guard entry["idiom"] == "mac", let size = entry["size"],
              let points = Int(size.components(separatedBy: "x").first ?? ""),
              size == "\(points)x\(points)", let scaleText = entry["scale"],
              let scale = Int(scaleText.dropLast()), scaleText == "\(scale)x",
              let filename = entry["filename"], filename == URL(fileURLWithPath: filename).lastPathComponent,
              let pngSource = CGImageSourceCreateWithURL(catalogURL.appendingPathComponent(filename) as CFURL, nil),
              let png = CGImageSourceCreateImageAtIndex(pngSource, 0, nil) else {
            throw IconValidationError(description: "AppIcon asset catalog contains an invalid image entry.")
        }
        let pixels = points * scale
        try require(png.width == pixels && png.height == pixels, "Asset catalog dimensions do not match its size/scale.")
        catalogSlots.insert("\(points):\(pixels)")
        guard let representation = image.representations.first(where: {
            $0.size.width == CGFloat(points) && $0.pixelsWide == pixels
        }) as? NSBitmapImageRep, let packaged = representation.cgImage else {
            throw IconValidationError(description: "The packaged icon is missing an asset catalog representation.")
        }
        let originalPixels = try pixelData(png)
        let packagedPixels = try pixelData(packaged)
        try require(originalPixels == packagedPixels, "Packaged icon pixels differ from approved asset: \(filename).")
    }
    try require(catalogSlots == expected, "AppIcon asset catalog must cover all ten standard/Retina slots.")
}

do {
    try require(CommandLine.arguments.count == 3, "Usage: verify-app-icon.swift /path/to/Deep Work.app /path/to/AppIcon.appiconset")
    try validateIcon(at: URL(fileURLWithPath: CommandLine.arguments[1]),
                     against: URL(fileURLWithPath: CommandLine.arguments[2]))
    print("Verified app icon: native bundle decoding and all 10 standard/Retina sizes match approved asset pixels.")
} catch {
    FileHandle.standardError.write(Data("App icon validation failed: \(error)\n".utf8))
    exit(1)
}
