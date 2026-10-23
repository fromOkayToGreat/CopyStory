import AppKit

// Offline synthetic fixture check: same attachment insertion/export operations
// as PasteFixture. No pasteboard, event posting, window or permission access.
let root = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
let names = try JSONDecoder().decode([String].self, from: Data(contentsOf: root.appendingPathComponent("cases.json")))
for name in names {
    precondition(!name.contains("/") && !name.contains(".."))
    let data = try Data(contentsOf: root.appendingPathComponent(name + ".png"))
    guard let image = NSImage(data: data) else { fatalError("Invalid synthetic PNG: \(name)") }
    let storage = NSTextStorage(string: "synthetic prefix\n")
    let location = storage.length
    let attachment = NSTextAttachment(); attachment.image = image
    storage.insert(NSAttributedString(attachment: attachment), at: location)
    guard let stored = storage.attribute(.attachment, at: location, effectiveRange: nil) as? NSTextAttachment,
          let tiff = stored.image?.tiffRepresentation,
          let bitmap = NSBitmapImageRep(data: tiff),
          let png = bitmap.representation(using: .png, properties: [:]) else {
        fatalError("Cannot export stored attachment: \(name)")
    }
    precondition(storage.length == location + 1)
    try png.write(to: root.appendingPathComponent(name + ".stored.png"))
    print("\(name): \(bitmap.pixelsWide)x\(bitmap.pixelsHigh), one stored attachment")
}
