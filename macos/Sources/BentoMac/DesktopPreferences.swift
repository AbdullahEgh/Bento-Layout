import AppKit
import BentoCore

final class DesktopPreferenceBackend: PreferenceBackend {
    private func validate(_ key: PreferenceKey) throws {
        let allowed: Set<PreferenceKey> = [PreferenceKey("com.apple.dock", "autohide"), PreferenceKey("NSGlobalDomain", "_HIHideMenuBar"), PreferenceKey("com.apple.WindowManager", "EnableTilingByEdgeDrag"), PreferenceKey("com.apple.WindowManager", "EnableTopTilingByEdgeDrag"), PreferenceKey("com.apple.WindowManager", "EnableTilingOptionAccelerator")]
        guard allowed.contains(key) else { throw CocoaError(.fileReadCorruptFile) }
    }
    private func domain(_ key: PreferenceKey) -> CFString { key.domain == "NSGlobalDomain" ? kCFPreferencesAnyApplication : key.domain as CFString }
    func read(_ key: PreferenceKey) throws -> Data? {
        try validate(key)
        CFPreferencesSynchronize(domain(key), kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
        guard let value = CFPreferencesCopyValue(key.name as CFString, domain(key), kCFPreferencesCurrentUser, kCFPreferencesAnyHost) else { return nil }
        return try PropertyListSerialization.data(fromPropertyList: value, format: .binary, options: 0)
    }
    func write(_ key: PreferenceKey, value: Data?) throws {
        try validate(key)
        let object = try value.map { try PropertyListSerialization.propertyList(from: $0, format: nil) }
        // Apply before storing: CoreDock may otherwise see the already-written
        // preference and skip the message that changes the live reserved area.
        let flag = (object as? NSNumber)?.boolValue ?? false
        if key.domain == "com.apple.dock", key.name == "autohide" { _ = NativeDesktopVisibility.setDockHidden(flag) }
        if key.name == "_HIHideMenuBar" { _ = NativeDesktopVisibility.setMenuHidden(flag) }
        CFPreferencesSetValue(key.name as CFString, object as CFPropertyList?, domain(key), kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
        guard CFPreferencesSynchronize(domain(key), kCFPreferencesCurrentUser, kCFPreferencesAnyHost) else { throw CocoaError(.fileWriteUnknown) }
    }
    func refresh(_ keys: [PreferenceKey]) throws {
        guard !keys.isEmpty else { return }
        // Preference files alone do not update WindowServer's reserved areas.
        // Apply the live native state, then preserve exact journaled key values
        // (native setters may materialize a default that originally was absent).
        let values = try keys.map { ($0, try read($0)) }
        var fallbackHosts = Set<String>()
        for (key, value) in values {
            let flag = try value.map { (try PropertyListSerialization.propertyList(from: $0, format: nil) as? NSNumber)?.boolValue ?? false } ?? false
            if key.domain == "com.apple.dock", key.name == "autohide" {
                if !NativeDesktopVisibility.setDockHidden(flag) { fallbackHosts.insert("Dock") }
            } else if key.name == "_HIHideMenuBar" {
                if !NativeDesktopVisibility.setMenuHidden(flag) { fallbackHosts.insert("ControlCenter") }
            }
        }
        for (key, value) in values where try read(key) != value { try write(key, value: value) }
        DistributedNotificationCenter.default().postNotificationName(NSNotification.Name("com.apple.dock.prefchanged"), object: nil, userInfo: nil, deliverImmediately: true)
        if keys.contains(where: { $0.name == "_HIHideMenuBar" }) {
            DistributedNotificationCenter.default().postNotificationName(NSNotification.Name("AppleInterfaceMenuBarHidingChangedNotification"), object: nil, userInfo: nil, deliverImmediately: true)
        }
        if keys.contains(where: { $0.domain == "com.apple.WindowManager" }) {
            // Native snapping reads these preferences in Dock. Visibility-only
            // changes never restart a host or disturb application focus.
            fallbackHosts.insert("Dock")
        }
        for host in fallbackHosts.sorted() {
            let process = Process(); process.executableURL = URL(fileURLWithPath: "/usr/bin/killall"); process.arguments = [host]
            process.standardOutput = FileHandle.nullDevice; process.standardError = FileHandle.nullDevice
            try process.run(); process.waitUntilExit()
            guard process.terminationStatus == 0 || process.terminationStatus == 1 else { throw CocoaError(.executableRuntimeMismatch) }
        }
    }
}
extension MacSettings {
    func desktopOverrides() throws -> [PreferenceKey: Data] {
        var changes: [PreferenceKey: Data] = [:]
        if hideDock { changes[PreferenceKey("com.apple.dock", "autohide")] = try ActivationOverrides.boolean(true) }
        if hideMenuBar { changes[PreferenceKey("NSGlobalDomain", "_HIHideMenuBar")] = try ActivationOverrides.boolean(true) }
        if edgeSnapping != "Keep" {
            for key in ["EnableTilingByEdgeDrag", "EnableTopTilingByEdgeDrag", "EnableTilingOptionAccelerator"] {
                changes[PreferenceKey("com.apple.WindowManager", key)] = try ActivationOverrides.boolean(edgeSnapping == "On")
            }
        }
        return changes
    }
}
