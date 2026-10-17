import Foundation

/// A hold consumes the press so releasing never also toggles the layout.
public struct StatusPress {
    private var began: Double?
    private var consumed = false
    public init() {}
    public var isTracking: Bool { began != nil }
    public mutating func begin(at time: Double) { began = time; consumed = false }
    public mutating func hold(at time: Double) -> Bool {
        guard let began, !consumed, time - began >= 0.55 else { return false }
        consumed = true; return true
    }
    public mutating func end() -> Bool {
        defer { began = nil; consumed = false }
        return began != nil && !consumed
    }
    public mutating func cancel() { began = nil; consumed = false }
}
