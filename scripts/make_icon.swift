// Renders the app icon (rounded-square coral gradient + prompt glyph)
// into an .iconset directory. Run: swift scripts/make_icon.swift <output.iconset>
import AppKit

let args = CommandLine.arguments
guard args.count > 1 else {
    print("usage: swift make_icon.swift <output.iconset>")
    exit(1)
}
let outDir = URL(fileURLWithPath: args[1])
try? FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)

func render(size: CGFloat) -> NSImage {
    let image = NSImage(size: NSSize(width: size, height: size))
    image.lockFocus()

    // macOS icon grid: squircle occupies ~82.4% of the canvas.
    let inset = size * 0.088
    let rect = NSRect(x: inset, y: inset, width: size - inset * 2, height: size - inset * 2)
    let radius = rect.width * 0.225
    let path = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)

    // Subtle drop shadow
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.3)
    shadow.shadowBlurRadius = size * 0.02
    shadow.shadowOffset = NSSize(width: 0, height: -size * 0.008)
    shadow.set()

    // Claude-coral gradient background
    let top = NSColor(calibratedRed: 0.89, green: 0.52, blue: 0.38, alpha: 1)     // #E38561
    let bottom = NSColor(calibratedRed: 0.72, green: 0.33, blue: 0.20, alpha: 1)  // #B85433
    NSGradient(starting: top, ending: bottom)?.draw(in: path, angle: -90)

    NSShadow().set() // clear shadow for foreground

    // Prompt glyph "❯_" in white
    let glyph = "❯_" as NSString
    let font = NSFont.monospacedSystemFont(ofSize: rect.width * 0.42, weight: .bold)
    let attrs: [NSAttributedString.Key: Any] = [
        .font: font,
        .foregroundColor: NSColor.white,
    ]
    let textSize = glyph.size(withAttributes: attrs)
    let textRect = NSRect(
        x: rect.midX - textSize.width / 2,
        y: rect.midY - textSize.height / 2 + rect.height * 0.02,
        width: textSize.width,
        height: textSize.height
    )
    glyph.draw(in: textRect, withAttributes: attrs)

    image.unlockFocus()
    return image
}

func writePNG(_ image: NSImage, pixels: Int, to url: URL) {
    guard let tiff = image.tiffRepresentation,
          let rep = NSBitmapImageRep(data: tiff) else { return }
    rep.size = image.size
    // Re-render at exact pixel size
    let target = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    )!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: target)
    image.draw(in: NSRect(x: 0, y: 0, width: pixels, height: pixels))
    NSGraphicsContext.restoreGraphicsState()
    if let png = target.representation(using: .png, properties: [:]) {
        try? png.write(to: url)
    }
}

for base in [16, 32, 128, 256, 512] {
    let img1 = render(size: CGFloat(base))
    writePNG(img1, pixels: base, to: outDir.appendingPathComponent("icon_\(base)x\(base).png"))
    let img2 = render(size: CGFloat(base * 2))
    writePNG(img2, pixels: base * 2, to: outDir.appendingPathComponent("icon_\(base)x\(base)@2x.png"))
}
print("iconset written to \(outDir.path)")
