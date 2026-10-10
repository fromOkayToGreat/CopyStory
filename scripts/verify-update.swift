// Public-key-only verification of Sparkle 2.9+ signed feeds and update archives.
// Signing remains delegated to Sparkle's official tools and the macOS Keychain.
import Foundation
import CryptoKit

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("Signature verification failed: \(message)\n".utf8))
    exit(1)
}
let args = CommandLine.arguments
if !(args.count == 3 || args.count == 4) { fail("Expected public key, file, optional archive signature") }
guard let rawKey = Data(base64Encoded: args[1]), rawKey.count == 32,
      let key = try? Curve25519.Signing.PublicKey(rawRepresentation: rawKey),
      let file = try? Data(contentsOf: URL(fileURLWithPath: args[2])) else { fail("Invalid key or unreadable file") }
let content: Data
let signatureString: String
if args.count == 4 {
    content = file
    signatureString = args[3]
} else {
    // Sparkle signs every byte preceding its final signature comment. Reject
    // ambiguous blocks and unsigned trailing bytes, stricter than XML parsing.
    let prefix = Data("<!-- sparkle-signatures:\n".utf8)
    guard let range = file.range(of: prefix),
          file.range(of: prefix, in: range.upperBound..<file.endIndex) == nil,
          let end = file.range(of: Data("-->".utf8), in: range.upperBound..<file.endIndex),
          let trailer = String(data: file[end.upperBound...], encoding: .utf8),
          trailer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
          let block = String(data: file[range.upperBound..<end.lowerBound], encoding: .utf8) else { fail("Missing or ambiguous signed feed block") }
    let lines = block.split(separator: "\n").map(String.init)
    let signatures = lines.filter { $0.hasPrefix("edSignature:") }
    let lengths = lines.filter { $0.hasPrefix("length:") }
    guard lines.count == 2, signatures.count == 1, lengths.count == 1,
          let length = Int(lengths[0].dropFirst("length:".count).trimmingCharacters(in: .whitespaces)) else { fail("Malformed signature block") }
    content = file[..<range.lowerBound]
    guard content.count == length else { fail("Feed length mismatch") }
    signatureString = signatures[0].dropFirst("edSignature:".count).trimmingCharacters(in: .whitespaces)
}
guard let signature = Data(base64Encoded: signatureString), signature.count == 64,
      key.isValidSignature(signature, for: content) else { fail("Ed25519 signature does not match embedded public key") }
print("Verified \(URL(fileURLWithPath: args[2]).lastPathComponent)")
