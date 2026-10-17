import Foundation

/// Reclaim a small strip left by cell-sized windows by moving one neighboring
/// divider. Membership and split direction never change. Native validation must
/// confirm an improvement before the caller commits the proposal.
public enum NativeSeamAlignment {
    public static func score(_ root: LayoutNode, area: Rect, gap: Int, frames: [UUID: Rect]) -> Int {
        guard let layout = try? LayoutEngine.calculate(root, in: area, gap: gap) else { return Int.max }
        var total = 0
        for region in layout.regions {
            guard let actual = frames[region.window.windowID], NativeFrameFit.accepts(actual, in: region.bounds) else { return Int.max }
            total += max(0, region.bounds.width - actual.width) + max(0, region.bounds.height - actual.height)
        }
        return total
    }
    public static func proposal(_ root: LayoutNode, area: Rect, gap: Int, frames: [UUID: Rect], affectedWindows: Set<UUID>? = nil) -> LayoutNode? {
        guard let layout = try? LayoutEngine.calculate(root, in: area, gap: gap), score(root, area: area, gap: gap, frames: frames) != Int.max else { return nil }
        var best: (Int, LayoutNode)?
        func visit(_ node: LayoutNode) {
            guard case let .split(id, axis, _, first, second) = node,
                  let divider = layout.dividers.first(where: { $0.id == id }) else { return }
            for (child, isFirst) in [(first, true), (second, false)] {
                guard case let .window(leaf) = child,
                      affectedWindows == nil || affectedWindows!.contains(leaf.windowID),
                      let slot = layout.regions.first(where: { $0.window.windowID == leaf.windowID })?.bounds,
                      let actual = frames[leaf.windowID] else { continue }
                let slack = axis == .horizontal ? slot.width - actual.width : slot.height - actual.height
                guard (3...32).contains(slack), slack > (best?.0 ?? 0) else { continue }
                let length = (axis == .horizontal ? divider.parent.width : divider.parent.height) - gap
                let offset = axis == .horizontal ? divider.bounds.x - divider.parent.x : divider.bounds.y - divider.parent.y
                guard length > 0 else { continue }
                let target = offset + (isFirst ? -slack : slack)
                let candidate = root.resizing(id, ratio: Double(target) / Double(length))
                guard let proposed = try? LayoutEngine.calculate(candidate, in: area, gap: gap),
                      let resized = proposed.regions.first(where: { $0.window.windowID == leaf.windowID })?.bounds,
                      (axis == .horizontal ? resized.width == actual.width : resized.height == actual.height) else { continue }
                best = (slack, candidate)
            }
            visit(first); visit(second)
        }
        visit(root)
        return best?.1
    }
}
