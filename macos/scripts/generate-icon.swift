import AppKit

// Native rendering of the existing Bento vector geometry; macOS palette only.
let output = CommandLine.arguments[1]
let size = 1024
let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size,
    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
    colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
NSColor.clear.setFill()
NSRect(x: 0, y: 0, width: size, height: size).fill(using: .copy)
func color(_ hex: UInt32, alpha: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: CGFloat((hex >> 16) & 255) / 255,
        green: CGFloat((hex >> 8) & 255) / 255, blue: CGFloat(hex & 255) / 255, alpha: alpha)
}
let outer = NSBezierPath(roundedRect: NSRect(x: 56, y: 56, width: 912, height: 912), xRadius: 218, yRadius: 218)
NSGradient(starting: color(0x38A4FF), ending: color(0x0055CF))!.draw(in: outer, angle: -65)
NSColor.white.withAlphaComponent(0.25).setStroke()
outer.lineWidth = 3; outer.stroke()
for rect in [NSRect(x: 226, y: 234, width: 244, height: 556),
             NSRect(x: 510, y: 234, width: 288, height: 242),
             NSRect(x: 510, y: 516, width: 288, height: 274)] {
    let native = NSRect(x: rect.minX, y: 1024 - rect.maxY, width: rect.width, height: rect.height)
    color(0x003B80, alpha: 0.14).setFill()
    NSBezierPath(roundedRect: native.offsetBy(dx: 0, dy: -10), xRadius: 44, yRadius: 44).fill()
    let pane = NSBezierPath(roundedRect: native, xRadius: 44, yRadius: 44)
    NSGradient(starting: .white, ending: color(0xE2F0FF))!.draw(in: pane, angle: -90)
}
NSGraphicsContext.restoreGraphicsState()
try bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: output))
