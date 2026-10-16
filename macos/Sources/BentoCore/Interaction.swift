import Foundation

public enum InteractionGeometry {
    // Preview the existing target slot, not a reflowed slot after removing its source.
    public static func preview(_ slot: Rect, placement: Placement, gap: Int) -> Rect {
        let width = max(1, (slot.width - gap) / 2), height = max(1, (slot.height - gap) / 2)
        switch placement {
        case .left: return Rect(slot.x, slot.y, width, slot.height)
        case .right: return Rect(slot.x + width + gap, slot.y, slot.width - width - gap, slot.height)
        case .top: return Rect(slot.x, slot.y, slot.width, height)
        case .bottom: return Rect(slot.x, slot.y + height + gap, slot.width, slot.height - height - gap)
        case .center: return slot
        }
    }
    public static func resize(_ workspace: Workspace, display: String, divider: Divider, pointer: Point, area: Rect, gap: Int) throws -> Workspace {
        guard let root = workspace.roots[display], (try LayoutEngine.calculate(root, in: area, gap: gap)).dividers.contains(where: { $0.id == divider.id }) else { throw LayoutError.missingTarget }
        let horizontal = divider.axis == .horizontal
        let length = (horizontal ? divider.parent.width : divider.parent.height) - gap
        guard length > 0 else { throw LayoutError.invalidInput }
        let position = (horizontal ? pointer.x - divider.parent.x : pointer.y - divider.parent.y) - gap / 2
        let candidate = root.resizing(divider.id, ratio: max(0, min(1, Double(position) / Double(length))))
        _ = try LayoutEngine.calculate(candidate, in: area, gap: gap)
        var next = workspace; next.roots[display] = candidate; return next
    }
    public static func resizeWindow(_ root: LayoutNode, windowID: UUID, requested: Rect, area: Rect, gap: Int) throws -> LayoutNode {
        let original = try LayoutEngine.calculate(root, in: area, gap: gap)
        guard let leaf = original.regions.first(where: { $0.window.windowID == windowID }) else { return root }
        var result = root
        for divider in original.dividers {
            let horizontal = divider.axis == .horizontal
            let trailing = horizontal ? leaf.bounds.right == divider.bounds.x : leaf.bounds.bottom == divider.bounds.y
            let leading = horizontal ? leaf.bounds.x == divider.bounds.right : leaf.bounds.y == divider.bounds.bottom
            let adjacent = horizontal ? leaf.bounds.y >= divider.parent.y && leaf.bounds.bottom <= divider.parent.bottom : leaf.bounds.x >= divider.parent.x && leaf.bounds.right <= divider.parent.right
            guard adjacent, trailing || leading else { continue }
            let oldEdge = horizontal ? (trailing ? leaf.bounds.right : leaf.bounds.x) : (trailing ? leaf.bounds.bottom : leaf.bounds.y)
            let newEdge = horizontal ? (trailing ? requested.right : requested.x) : (trailing ? requested.bottom : requested.y)
            if abs(newEdge - oldEdge) <= 2 { continue }
            guard let current = try LayoutEngine.calculate(result, in: area, gap: gap).dividers.first(where: { $0.id == divider.id }) else { continue }
            let length = (horizontal ? current.parent.width : current.parent.height) - gap
            guard length > 0 else { throw LayoutError.invalidInput }
            let start = horizontal ? current.parent.x : current.parent.y
            result = result.resizing(divider.id, ratio: max(0, min(1, Double(newEdge - start - (leading ? gap : 0)) / Double(length))))
        }
        _ = try LayoutEngine.calculate(result, in: area, gap: gap)
        return result
    }
}

public struct DropProposal {
    public let workspace: Workspace
    public let bounds: Rect
    public let placement: Placement
}
public struct DropSession {
    public let original: Workspace
    public let source: WindowLeaf
    private var intent = DragIntent()
    public init(workspace: Workspace, source: WindowLeaf) { original = workspace; self.source = source }
    public mutating func propose(pointer: Point, areas: [String: Rect], gap: Int, hold: Int, now: Double) throws -> DropProposal? {
        guard let (display, area) = areas.first(where: { $0.value.contains(pointer) }), let root = original.roots[display],
              let target = try LayoutEngine.calculate(root, in: area, gap: gap).regions.first(where: { $0.bounds.contains(pointer) }),
              target.window.windowID != source.windowID else { intent.reset(); return nil }
        let gesture = try intent.update(display: display, target: target.window.id, bounds: target.bounds, point: pointer, now: now, holdMilliseconds: hold)
        let next = try original.placing(source, on: display, target: target.window.id, placement: gesture.placement)
        do {
            for (id, node) in next.roots {
                guard let workArea = areas[id] else { throw LayoutError.missingTarget }
                _ = try LayoutEngine.calculate(node, in: workArea, gap: gap)
            }
        } catch LayoutError.cannotFit { return nil }
        return DropProposal(workspace: next, bounds: InteractionGeometry.preview(target.bounds, placement: gesture.placement, gap: gap), placement: gesture.placement)
    }
}
