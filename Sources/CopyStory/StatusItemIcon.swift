import AppKit

/// The app mark simplified for an 18-point menu-bar canvas.
/// Drawing on demand keeps paths sharp at the display's backing scale;
/// template rendering lets AppKit supply light, dark and selected-state tint.
enum StatusItemIcon {
    static func makeImage() -> NSImage {
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: true) { _ in
            NSColor.black.setStroke()

            let arrow = NSBezierPath()
            arrow.lineWidth = 1.25
            arrow.lineCapStyle = .round
            arrow.lineJoinStyle = .round
            arrow.move(to: NSPoint(x: 2.5, y: 12.2))
            arrow.curve(to: NSPoint(x: 16.9, y: 9),
                        controlPoint1: NSPoint(x: 6.2, y: 20.1),
                        controlPoint2: NSPoint(x: 17.4, y: 17.1))
            arrow.curve(to: NSPoint(x: 2.1, y: 7.6),
                        controlPoint1: NSPoint(x: 16.5, y: -1.5),
                        controlPoint2: NSPoint(x: 4.5, y: -1.1))
            arrow.stroke()

            let head = NSBezierPath()
            head.lineWidth = 1.25
            head.lineCapStyle = .round
            head.lineJoinStyle = .round
            head.move(to: NSPoint(x: 0.9, y: 6.5))
            head.line(to: NSPoint(x: 2.1, y: 8.1))
            head.line(to: NSPoint(x: 3.7, y: 6.7))
            head.stroke()

            // Omit the occluded back edges so the overlapping squares stay
            // legible without a filled tile or dense crossing at small sizes.
            let back = NSBezierPath()
            back.lineWidth = 1.1
            back.lineCapStyle = .round
            back.lineJoinStyle = .round
            back.move(to: NSPoint(x: 7.4, y: 11.7))
            back.line(to: NSPoint(x: 6.3, y: 11.7))
            back.curve(to: NSPoint(x: 5.2, y: 10.6),
                       controlPoint1: NSPoint(x: 5.6, y: 11.7),
                       controlPoint2: NSPoint(x: 5.2, y: 11.3))
            back.line(to: NSPoint(x: 5.2, y: 6.2))
            back.curve(to: NSPoint(x: 6.3, y: 5.1),
                       controlPoint1: NSPoint(x: 5.2, y: 5.5),
                       controlPoint2: NSPoint(x: 5.6, y: 5.1))
            back.line(to: NSPoint(x: 10.7, y: 5.1))
            back.curve(to: NSPoint(x: 11.8, y: 6.2),
                       controlPoint1: NSPoint(x: 11.4, y: 5.1),
                       controlPoint2: NSPoint(x: 11.8, y: 5.5))
            back.line(to: NSPoint(x: 11.8, y: 7.2))
            back.stroke()

            let front = NSBezierPath(roundedRect: NSRect(x: 7.4, y: 7.2, width: 6.6, height: 6.6),
                                     xRadius: 1.1, yRadius: 1.1)
            front.lineWidth = 1.1
            front.stroke()
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "CopyStory clipboard history"
        return image
    }
}
