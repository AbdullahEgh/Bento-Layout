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
        CFPreferencesSetValue(key.name as CFString, object as CFPropertyList?, domain(key), kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
        guard CFPreferencesSynchronize(domain(key), kCFPreferencesCurrentUser, kCFPreferencesAnyHost) else { throw CocoaError(.fileWriteUnknown) }
    }
    func refresh(_ keys: [PreferenceKey]) throws {
        guard !keys.isEmpty else { return }
        if keys.contains(where: { $0.name == "_HIHideMenuBar" }) {
            DistributedNotificationCenter.default().postNotificationName(NSNotification.Name("AppleInterfaceMenuBarHidingChangedNotification"), object: nil, userInfo: nil, deliverImmediately: true)
        }
        // Dock hosts both the Dock and native tiling. Restart only when an opted-in
        // override changed; no security setting, service or launch agent is modified.
        if keys.contains(where: { $0.domain == "com.apple.dock" || $0.domain == "com.apple.WindowManager" || $0.name == "_HIHideMenuBar" }) {
            let process = Process(); process.executableURL = URL(fileURLWithPath: "/usr/bin/killall"); process.arguments = ["Dock"]
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
