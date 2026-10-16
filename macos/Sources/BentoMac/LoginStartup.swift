import AppKit
import SwiftUI
import ServiceManagement

@MainActor final class LoginStartup: ObservableObject {
    @Published private(set) var enabled = false
    @Published private(set) var needsApproval = false
    @Published private(set) var message: String?
    init() { refresh() }
    func refresh() {
        let status = SMAppService.mainApp.status
        enabled = status == .enabled || status == .requiresApproval
        needsApproval = status == .requiresApproval
    }
    func setEnabled(_ desired: Bool) {
        do {
            if desired { try SMAppService.mainApp.register() }
            else { try SMAppService.mainApp.unregister() }
            message = nil
        } catch { message = "Could not change Start at login: \(error.localizedDescription). Keep Bento in a stable Applications folder and try again." }
        refresh()
    }
    func openSettings() { SMAppService.openSystemSettingsLoginItems() }
}
