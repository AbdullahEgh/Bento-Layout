import Foundation

public enum InteractionGeometry {
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
    public let neighbors: [Rect]
    public let progress: Double
    public let waitingForSplit: Bool
}
public struct DropSession {
    public let original: Workspace
    public let source: WindowLeaf
    public private(set) var conflictBounds: Rect?
    private var intent = DragIntent()
    public init(workspace: Workspace, source: WindowLeaf) { original = workspace; self.source = source }
    public mutating func propose(pointer: Point, areas: [String: Rect], gap: Int, hold: Int, now: Double) throws -> DropProposal? {
        conflictBounds = nil
        guard let (display, area) = areas.first(where: { $0.value.contains(pointer) }), let root = original.roots[display],
              let target = try LayoutEngine.calculate(root, in: area, gap: gap).regions.first(where: { $0.bounds.contains(pointer) }),
              target.window.windowID != source.windowID else { intent.reset(); return nil }
        let gesture = try intent.update(display: display, target: target.window.id, bounds: target.bounds, point: pointer, now: now, holdMilliseconds: hold)
        let next = try original.placing(source, on: display, target: target.window.id, placement: gesture.placement)
        var destination: Rect?
        var neighbors: [Rect] = []
        do {
            for (id, node) in next.roots {
                guard let workArea = areas[id] else { throw LayoutError.missingTarget }
                let before = try LayoutEngine.calculate(original.roots[id], in: workArea, gap: gap).regions
                for region in try LayoutEngine.calculate(node, in: workArea, gap: gap).regions {
                    if region.window.windowID == source.windowID { destination = region.bounds }
                    else if before.first(where: { $0.window.windowID == region.window.windowID })?.bounds != region.bounds {
                        neighbors.append(region.bounds)
                    }
                }
            }
        } catch LayoutError.cannotFit { conflictBounds = target.bounds; return nil }
        guard let destination else { throw LayoutError.missingTarget }
        return DropProposal(workspace: next, bounds: destination, placement: gesture.placement, neighbors: neighbors,
                            progress: gesture.progress, waitingForSplit: gesture.waitingForSplit)
    }
}

/// A shared, time-based curve keeps a batch of windows moving together.
public enum WindowMotion {
    public static func frame(from: Rect, to: Rect, progress: Double) -> Rect {
        let t = max(0, min(1, progress.isFinite ? progress : 1))
        let eased = t * t * (3 - 2 * t)
        func mix(_ a: Int, _ b: Int) -> Int { Int((Double(a) + (Double(b) - Double(a)) * eased).rounded()) }
        return Rect(mix(from.x, to.x), mix(from.y, to.y), mix(from.width, to.width), mix(from.height, to.height))
    }
}
