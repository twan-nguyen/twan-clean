#!/usr/bin/env swift
// Draws the Twan Clean app icon at every size macOS needs and writes the
// asset catalog's AppIcon set. Run from the repository root:
//   swift scripts/generate-app-icon.swift
import AppKit

let output = URL(fileURLWithPath: "TwanClean/Resources/Assets.xcassets/AppIcon.appiconset")

/// The icon on a 1024-point canvas, following the macOS grid: an 824-point
/// rounded square centred with a soft shadow, a teal-to-green gradient and a
/// white sparkles symbol.
func drawIcon(in context: CGContext, size: CGFloat) {
    let scale = size / 1024
    context.scaleBy(x: scale, y: scale)

    let tile = CGRect(x: 100, y: 100, width: 824, height: 824)
    let shape = CGPath(roundedRect: tile, cornerWidth: 185, cornerHeight: 185, transform: nil)

    context.saveGState()
    context.setShadow(offset: CGSize(width: 0, height: -10), blur: 28,
                      color: NSColor.black.withAlphaComponent(0.3).cgColor)
    context.addPath(shape)
    context.setFillColor(NSColor.black.cgColor)
    context.fillPath()
    context.restoreGState()

    context.saveGState()
    context.addPath(shape)
    context.clip()
    let colors = [NSColor(srgbRed: 0.10, green: 0.62, blue: 0.70, alpha: 1).cgColor,
                  NSColor(srgbRed: 0.20, green: 0.78, blue: 0.47, alpha: 1).cgColor] as CFArray
    let gradient = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: colors, locations: [0, 1])!
    context.drawLinearGradient(gradient, start: CGPoint(x: 100, y: 924), end: CGPoint(x: 924, y: 100), options: [])
    context.restoreGState()

    let configuration = NSImage.SymbolConfiguration(pointSize: 440, weight: .semibold)
        .applying(NSImage.SymbolConfiguration(paletteColors: [.white]))
    if let symbol = NSImage(systemSymbolName: "sparkles", accessibilityDescription: nil)?
        .withSymbolConfiguration(configuration) {
        let symbolSize = symbol.size
        let origin = CGPoint(x: tile.midX - symbolSize.width / 2, y: tile.midY - symbolSize.height / 2)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
        symbol.draw(in: CGRect(origin: origin, size: symbolSize))
        NSGraphicsContext.restoreGraphicsState()
    }
}

func png(pixels: Int) -> Data {
    let context = CGContext(data: nil, width: pixels, height: pixels, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    drawIcon(in: context, size: CGFloat(pixels))
    let image = NSBitmapImageRep(cgImage: context.makeImage()!)
    return image.representation(using: .png, properties: [:])!
}

var images: [[String: String]] = []
for points in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let name = "icon_\(points)x\(points)\(scale == 2 ? "@2x" : "").png"
        try png(pixels: points * scale).write(to: output.appendingPathComponent(name))
        images.append(["idiom": "mac", "size": "\(points)x\(points)", "scale": "\(scale)x", "filename": name])
    }
}
let contents: [String: Any] = ["images": images, "info": ["author": "xcode", "version": 1]]
let json = try JSONSerialization.data(withJSONObject: contents, options: [.prettyPrinted, .sortedKeys])
try json.write(to: output.appendingPathComponent("Contents.json"))
print("Wrote \(images.count) icon images to \(output.path)")
