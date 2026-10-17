import AppKit

// Explicit white artwork keeps the active/disabled state distinct from macOS's
// enabled-button styling; the disabled-looking icon remains clickable.
@MainActor enum BentoStatusIcon {
    private static let outline = make(filled: false)
    private static let filled = make(filled: true)
    static func image(active: Bool) -> NSImage { active ? filled : outline }
    private static func make(filled: Bool) -> NSImage {
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { rect in
            NSColor.white.setFill(); NSColor.white.setStroke()
            if filled {
                for slot in [NSRect(x: 1, y: 2, width: 5.5, height: 14),
                             NSRect(x: 8, y: 2, width: 9, height: 6.25),
                             NSRect(x: 8, y: 9.75, width: 9, height: 6.25)] {
                    NSBezierPath(roundedRect: slot, xRadius: 1.5, yRadius: 1.5).fill()
                }
            } else {
                let border = NSBezierPath(roundedRect: rect.insetBy(dx: 1, dy: 2), xRadius: 2, yRadius: 2)
                border.lineWidth = 1.4; border.stroke()
                let lines = NSBezierPath(); lines.lineWidth = 1.4
                lines.move(to: NSPoint(x: 7, y: 2)); lines.line(to: NSPoint(x: 7, y: 16))
                lines.move(to: NSPoint(x: 7, y: 9)); lines.line(to: NSPoint(x: 17, y: 9)); lines.stroke()
            }
            return true
        }
        image.isTemplate = false
        return image
    }
}
