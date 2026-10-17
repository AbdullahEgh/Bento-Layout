import Foundation
import Darwin

/// Read-only WindowServer identity. Never moves a window or changes Spaces.
/// Resolve dynamically so an unavailable API pauses isolation rather than merging histories.
enum DesktopIdentity {
    private static let graphics = dlopen("/System/Library/Frameworks/CoreGraphics.framework/CoreGraphics", RTLD_LAZY)
    private typealias Connection = @convention(c) () -> Int32
    private typealias Spaces = @convention(c) (Int32, CFString?) -> Unmanaged<CFArray>?
    static func current() -> String? {
        guard let graphics, let connection = dlsym(graphics, "CGSMainConnectionID"),
              let copy = dlsym(graphics, "CGSCopyManagedDisplaySpaces") else { return nil }
        let id = unsafeBitCast(connection, to: Connection.self)()
        guard let rows = unsafeBitCast(copy, to: Spaces.self)(id, nil)?.takeRetainedValue() as? [[String: Any]], !rows.isEmpty else { return nil }
        let identities = rows.compactMap { row -> String? in
            guard let display = row["Display Identifier"] as? String,
                  let current = row["Current Space"] as? [String: Any],
                  let number = (current["ManagedSpaceID"] ?? current["id64"]) as? NSNumber else { return nil }
            return display + ":" + number.stringValue
        }
        guard identities.count == rows.count else { return nil }
        return identities.sorted().joined(separator: "|")
    }
}
