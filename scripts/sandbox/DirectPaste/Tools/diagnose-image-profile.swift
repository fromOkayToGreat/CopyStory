import AppKit
import ImageIO
let root = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
let input = try Data(contentsOf: root.appendingPathComponent("srgb-tagged.png"))
func describe(_ label: String, _ data: Data) throws {
    guard let rep = NSBitmapImageRep(data: data) else { fatalError(label) }
    let profile = rep.colorSpace.iccProfileData
    let source = CGImageSourceCreateWithData(data as CFData, nil)!
    let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil)! as NSDictionary
    print("\(label): colorSpace=\(rep.colorSpace.localizedName ?? "unknown"), ICC bytes=\(profile?.count ?? 0), properties=\(props)")
    if let profile { try profile.write(to: root.appendingPathComponent(label + ".icc")) }
}
try describe("input", input)
let image = NSImage(data: input)!
let originalRep = image.representations.compactMap { $0 as? NSBitmapImageRep }.first!
try describe("direct-export", originalRep.representation(using: .png, properties: [:])!)
let storage = NSTextStorage(string: "fixture")
let a = NSTextAttachment(); a.image = image
storage.insert(NSAttributedString(attachment: a), at: storage.length)
let stored = storage.attribute(.attachment, at: 7, effectiveRange: nil) as! NSTextAttachment
print("stored image is original: \(stored.image === image)")
let tiff = stored.image!.tiffRepresentation!
try tiff.write(to: root.appendingPathComponent("stage.tiff")); try describe("tiff", tiff)
let bitmap = NSBitmapImageRep(data: tiff)!
let png = bitmap.representation(using: .png, properties: [:])!
try png.write(to: root.appendingPathComponent("stage.png")); try describe("png", png)
