import AppKit

extension NSImage {
    /// The menu bar icon: an ant's head facing north, with two bent antennae and two eyes cut out.
    /// A template image, so the menu bar tints it for light, dark, and highlighted states.
    @MainActor static let antHead: NSImage = {
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: true) { _ in // grid: ok menu bar icon canvas, not layout
            NSColor.black.set()
            let head = NSBezierPath(ovalIn: NSRect(x: 4.5, y: 6.5, width: 9, height: 10)) // grid: ok glyph drawing
            head.windingRule = .evenOdd
            head.append(NSBezierPath(ovalIn: NSRect(x: 5.6, y: 10, width: 2, height: 2.4))) // grid: ok glyph drawing
            head.append(NSBezierPath(ovalIn: NSRect(x: 10.4, y: 10, width: 2, height: 2.4))) // grid: ok glyph drawing
            head.fill()
            for side in [-1.0, 1.0] {
                let antenna = NSBezierPath()
                antenna.move(to: NSPoint(x: 9 + side * 2, y: 7.5))
                antenna.line(to: NSPoint(x: 9 + side * 5, y: 4.5))
                antenna.line(to: NSPoint(x: 9 + side * 4.6, y: 1))
                antenna.lineWidth = 1.6
                antenna.lineCapStyle = .round
                antenna.lineJoinStyle = .round
                antenna.stroke()
            }
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "AntHill"
        return image
    }()
}
