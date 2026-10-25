// Compile with StatusItemIcon.swift and this file copied to main.swift.
// Offscreen only: does not create NSApplication, windows or a status item.
import AppKit

func bitmap(width: Int, height: Int) -> NSBitmapImageRep {
    NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height,
                     bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                     isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0,
                     bitsPerPixel: 0)!
}

func raster(_ image: NSImage, scale: Int) -> NSBitmapImageRep {
    let rep = bitmap(width: 18 * scale, height: 18 * scale)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    NSAffineTransform().withScale(CGFloat(scale))
    image.draw(in: NSRect(x: 0, y: 0, width: 18, height: 18))
    NSGraphicsContext.restoreGraphicsState()
    return rep
}

extension NSAffineTransform {
    func withScale(_ scale: CGFloat) { scaleX(by: scale, yBy: scale); concat() }
}

let output = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
let mark = StatusItemIcon.makeImage()
precondition(mark.isTemplate && mark.size == NSSize(width: 18, height: 18))
precondition(mark.accessibilityDescription == "CopyStory clipboard history")
var rasters: [NSBitmapImageRep] = []
for scale in [1, 2] {
    let rep = raster(mark, scale: scale)
    var occupied = 0
    for y in 0..<rep.pixelsHigh {
        for x in 0..<rep.pixelsWide {
            let c = rep.colorAt(x: x, y: y)!.usingColorSpace(.deviceRGB)!
            if c.alphaComponent > 0.1 { occupied += 1 }
            precondition(abs(c.redComponent - c.greenComponent) < 0.01)
            precondition(abs(c.greenComponent - c.blueComponent) < 0.01)
        }
    }
    precondition(occupied > 60 * scale * scale && occupied < 220 * scale * scale)
    // No background tile; four canvas corners remain transparent.
    for (x, y) in [(0, 0), (rep.pixelsWide-1, 0), (0, rep.pixelsHigh-1),
                   (rep.pixelsWide-1, rep.pixelsHigh-1)] {
        precondition(rep.colorAt(x: x, y: y)!.alphaComponent == 0)
    }
    try rep.representation(using: .png, properties: [:])!
        .write(to: output.appendingPathComponent("status-icon-\(scale)x.png"))
    rasters.append(rep)
    print("\(scale)x: \(rep.pixelsWide)×\(rep.pixelsHigh), \(occupied) occupied pixels; template/alpha/monochrome checks passed")
}

let canvas = bitmap(width: 800, height: 320)
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: canvas)
NSColor(calibratedWhite: 0.96, alpha: 1).setFill()
NSRect(x: 0, y: 0, width: 800, height: 320).fill()
func label(_ text: String, _ x: CGFloat, _ y: CGFloat, color: NSColor = .black, size: CGFloat = 13) {
    (text as NSString).draw(at: NSPoint(x: x, y: y),
        withAttributes: [.font: NSFont.systemFont(ofSize: size), .foregroundColor: color])
}
label("CopyStory • menu-bar line art", 24, 284, size: 20)
label("Offscreen rendering • 18 pt canvas • same vector paths at each scale", 24, 258, size: 12)
for (row, dark) in [false, true].enumerated() {
    let y: CGFloat = row == 0 ? 145 : 30
    let fg: NSColor = dark ? .white : .black
    NSColor(calibratedWhite: dark ? 0.13 : 0.90, alpha: 1).setFill()
    NSRect(x: 24, y: y, width: 752, height: 95).fill()
    label(dark ? "Dark" : "Light", 40, y+39, color: fg)
    for (index, rep) in rasters.enumerated() {
        let img = NSImage(size: NSSize(width: rep.pixelsWide, height: rep.pixelsHigh))
        img.addRepresentation(rep)
        // Explicit synthetic tint preview. Runtime tint is owned by AppKit.
        let tinted = NSImage(size: img.size, flipped: false) { rect in
            img.draw(in: rect)
            fg.setFill(); rect.fill(using: .sourceIn)
            return true
        }
        let x: CGFloat = index == 0 ? 150 : 320
        tinted.draw(in: NSRect(x: x, y: y+42, width: 18, height: 18))
        label(index == 0 ? "1× • 18 px" : "2× • 36 px at 18 pt", x-20, y+15, color: fg, size: 11)
        NSGraphicsContext.current?.imageInterpolation = .none
        tinted.draw(in: NSRect(x: x+75, y: y+26, width: 54, height: 54))
        NSGraphicsContext.current?.imageInterpolation = .default
    }
    label("3× pixel inspection", 555, y+42, color: fg, size: 12)
}
NSGraphicsContext.restoreGraphicsState()
try canvas.representation(using: .png, properties: [:])!
    .write(to: output.appendingPathComponent("CopyStory-menu-bar-preview.png"))
