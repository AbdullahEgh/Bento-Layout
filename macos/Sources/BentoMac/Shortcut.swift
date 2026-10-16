import AppKit
import Carbon.HIToolbox

struct ShortcutConfig: Codable, Equatable {
    var enabled = true, control = true, option = true, shift = false, command = false
    var key = "B"
    var valid: Bool { Self.keys.contains(key) && (!enabled || control || option || shift || command) }
    static let keys = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789").map(String.init)
    var modifiers: UInt32 { (control ? UInt32(controlKey) : 0) | (option ? UInt32(optionKey) : 0) | (shift ? UInt32(shiftKey) : 0) | (command ? UInt32(cmdKey) : 0) }
    var label: String { enabled ? (control ? "⌃" : "") + (option ? "⌥" : "") + (shift ? "⇧" : "") + (command ? "⌘" : "") + key : "Shortcut disabled" }
    var keyCode: UInt32? {
        let codes = [0, 11, 8, 2, 14, 3, 5, 4, 34, 38, 40, 37, 46, 45, 31, 35, 12, 15, 1, 17, 32, 9, 13, 7, 16, 6, 29, 18, 19, 20, 21, 23, 22, 26, 28, 25]
        return Self.keys.firstIndex(of: key).map { UInt32(codes[$0]) }
    }
}
