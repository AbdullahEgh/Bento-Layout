import Foundation
#if canImport(FoundationXML)
import FoundationXML
#endif
import CryptoKit

final class Feed: NSObject, XMLParserDelegate {
    var items: [[String: String]] = [], item: [String: String] = [:], collecting: String?
    func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?, qualifiedName: String?, attributes: [String: String]) {
        if name == "item" { item = [:] }
        if name == "enclosure" { item.merge(attributes) { _, new in new } }
        if name == "sparkle:version" || name == "description" { collecting = name == "description" ? "notes" : "version"; item[collecting!] = "" }
    }
    func parser(_ parser: XMLParser, foundCharacters string: String) { if let collecting { item[collecting, default: ""] += string } }
    func parser(_ parser: XMLParser, foundCDATA CDATABlock: Data) { if let collecting { item[collecting, default: ""] += String(decoding: CDATABlock, as: UTF8.self) } }
    func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName: String?) {
        if name == "sparkle:version" || name == "description" { collecting = nil }
        if name == "item" { items.append(item) }
    }
}
func fail(_ message: String) -> Never { fputs("Update validation failed: \(message)\n", stderr); exit(1) }
guard CommandLine.arguments.count == 5 else { fail("Expected Info.plist, appcast, archive and release tag.") }
do {
    let args = CommandLine.arguments, archive = try Data(contentsOf: URL(fileURLWithPath: args[3]))
    guard let info = try PropertyListSerialization.propertyList(from: Data(contentsOf: URL(fileURLWithPath: args[1])), format: nil) as? [String: Any] else { fail("Invalid app Info.plist.") }
    guard let encoded = info["SUPublicEDKey"] as? String, let publicData = Data(base64Encoded: encoded), publicData.count == 32,
          let version = info["CFBundleVersion"] as? String else { fail("Missing app version or public key.") }
    let feed = Feed(), parser = XMLParser(data: try Data(contentsOf: URL(fileURLWithPath: args[2])))
    parser.shouldResolveExternalEntities = false; parser.delegate = feed
    guard parser.parse(), let item = feed.items.first(where: { $0["version"] == version || $0["sparkle:version"] == version }),
          let encodedSignature = item["sparkle:edSignature"], let signature = Data(base64Encoded: encodedSignature),
          item["url"] == "https://github.com/AbdullahEgh/Bento-Layout/releases/download/\(args[4])/Bento-macos-universal.zip",
          item["length"].flatMap(Int.init) == archive.count else { fail("Feed version, URL, length or signature is invalid.") }
    guard let notes = item["notes"], !notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { fail("Missing embedded release notes for the update popup.") }
    let key = try Curve25519.Signing.PublicKey(rawRepresentation: publicData)
    guard key.isValidSignature(signature, for: archive) else { fail("The archive does not match the app's embedded public key.") }
    print("Verified release archive, app version and feed enclosure.")
} catch { fail(error.localizedDescription) }
