import Foundation

/// Native apps such as terminals resize in whole cells. Keep their frames
/// inside the slot without treating a small unused strip as a resize failure.
public enum NativeFrameFit {
    public static func accepts(_ actual: Rect, in slot: Rect) -> Bool {
        abs(actual.x - slot.x) <= 2 && abs(actual.y - slot.y) <= 2 &&
        actual.width > 0 && actual.height > 0 &&
        (-2...32).contains(slot.width - actual.width) &&
        (-2...32).contains(slot.height - actual.height)
    }

    /// One bounded inward correction for cell rounding. A real minimum still
    /// refuses this target and is learned by the normal settled validation.
    public static func inwardTarget(actual: Rect, slot: Rect) -> Rect {
        var target = slot
        let dx = actual.width - slot.width, dy = actual.height - slot.height
        if (3...32).contains(dx) { target.width = max(1, slot.width - dx - 1) }
        if (3...32).contains(dy) { target.height = max(1, slot.height - dy - 1) }
        return target
    }
}
