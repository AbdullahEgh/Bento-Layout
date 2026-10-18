import Foundation
import Darwin

/// Read-only WindowServer identity. Never moves a window or changes Spaces.
/// Resolve dynamically so an unavailable API pauses isolation rather than merging histories.
enum DesktopIdentity {
    private static let graphics = dlopen("/System/Library/Frameworks/CoreGraphics.framework/CoreGraphics", RTLD_LAZY)
    private typealias Connection = @convention(c) () -> Int32
    private typealias Spaces = @convention(c) (Int32, CFString?) -> Unmanaged<CFArray>?
    // The focused Space can differ from NSScreen.main for full-screen apps.
    // Read the native Space type (0 = desktop, 4 = fullscreen), as in Hammerspoon.
    static var isFullScreen: Bool {
        typealias ActiveSpace = @convention(c) (Int32) -> UInt64
        typealias SpaceType = @convention(c) (Int32, UInt64) -> Int32
        guard let graphics, let connection = dlsym(graphics, "CGSMainConnectionID"),
              let active = dlsym(graphics, "CGSGetActiveSpace"),
              let type = dlsym(graphics, "CGSSpaceGetType") else { return false }
        let id = unsafeBitCast(connection, to: Connection.self)()
        let space = unsafeBitCast(active, to: ActiveSpace.self)(id)
        return unsafeBitCast(type, to: SpaceType.self)(id, space) == 4
    }
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
    // Read-only window membership, also used by Hammerspoon's spaces adapter:
    // https://github.com/Hammerspoon/hammerspoon/blob/master/extensions/spaces/libspaces.m
    // A live AX window may have been moved to another Space, not merely hidden
    // by Mission Control. Never pull that window back into this desktop.
    static func containsWindow(_ number: Int) -> Bool? {
        typealias WindowSpaces = @convention(c) (Int32, Int32, CFArray) -> Unmanaged<CFArray>?
        guard let graphics, let connection = dlsym(graphics, "CGSMainConnectionID"),
              let copy = dlsym(graphics, "CGSCopySpacesForWindows"), let identity = current() else { return nil }
        let active = Set(identity.split(separator: "|").compactMap { UInt64($0.split(separator: ":").last ?? "") })
        let id = unsafeBitCast(connection, to: Connection.self)()
        let windows = [NSNumber(value: number)] as CFArray
        guard let values = unsafeBitCast(copy, to: WindowSpaces.self)(id, 7, windows)?.takeRetainedValue() as? [NSNumber] else { return nil }
        return values.contains { active.contains($0.uint64Value) }
    }

}
