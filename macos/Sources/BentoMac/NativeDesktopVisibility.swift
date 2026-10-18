import AppKit
import Darwin

/// Resolve native visibility entry points at runtime so unsupported OS versions
/// can fail closed without a hard dependency on private framework symbols.
enum NativeDesktopVisibility {
    private static let services = dlopen("/System/Library/Frameworks/ApplicationServices.framework/ApplicationServices", RTLD_LAZY)
    private static let graphics = dlopen("/System/Library/Frameworks/CoreGraphics.framework/CoreGraphics", RTLD_LAZY)
    private typealias DockSetter = @convention(c) (Bool) -> Void
    private typealias Connection = @convention(c) () -> Int32
    private typealias MenuSetter = @convention(c) (Int32, Bool) -> Int32

    static func setDockHidden(_ hidden: Bool) -> Bool {
        guard !DesktopIdentity.isFullScreen else { return true }
        guard let services, let symbol = dlsym(services, "CoreDockSetAutoHideEnabled") else { return false }
        unsafeBitCast(symbol, to: DockSetter.self)(hidden)
        return true
    }
    static func setMenuHidden(_ hidden: Bool) -> Bool {
        guard !DesktopIdentity.isFullScreen else { return true }
        guard let graphics, let connection = dlsym(graphics, "CGSMainConnectionID"),
              let symbol = dlsym(graphics, "CGSSetMenuBarAutohideEnabled") else { return false }
        let id = unsafeBitCast(connection, to: Connection.self)()
        return unsafeBitCast(symbol, to: MenuSetter.self)(id, hidden) == 0
    }
}
