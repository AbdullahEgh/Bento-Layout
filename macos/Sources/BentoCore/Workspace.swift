import Foundation

public struct Workspace: Codable, Equatable, Sendable {
    public var roots: [String: LayoutNode]
    public init(roots: [String: LayoutNode] = [:]) { self.roots = roots }
    public var windows: [WindowLeaf] { roots.values.flatMap(\.windows) }
    public func removing(_ id: UUID) -> Workspace {
        Workspace(roots: roots.compactMapValues { $0.removing(id) })
    }
    public func placing(_ incoming: WindowLeaf, on display: String, target targetID: UUID?, placement: Placement) throws -> Workspace {
        let original = roots[display], target = original?.windows.first { $0.id == targetID }
        if targetID == nil && original != nil { throw LayoutError.missingTarget }
        if target?.windowID == incoming.windowID { return self }
        if targetID != nil && target == nil { throw LayoutError.missingTarget }
        let source = windows.first { $0.windowID == incoming.windowID }
        var next = removing(incoming.windowID)
        guard let target else { next.roots[display] = .window(incoming); return next }
        if placement == .center {
            if let source {
                next = self
                var movedTarget = target; movedTarget.id = source.id
                var movedSource = incoming; movedSource.id = target.id
                for (key, root) in roots {
                    next.roots[key] = root.replacing(source.id, with: .window(movedTarget)).replacing(target.id, with: .window(movedSource))
                }
            } else { next.roots[display] = next.roots[display]?.replacing(target.id, with: .window(incoming)) }
            return next
        }
        let before = placement == .left || placement == .top
        let branch = LayoutNode.split(id: UUID(), axis: placement == .left || placement == .right ? .horizontal : .vertical,
                                     ratio: 0.5, first: .window(before ? incoming : target), second: .window(before ? target : incoming))
        next.roots[display] = next.roots[display]?.replacing(target.id, with: branch)
        return next
    }
}
public struct LayoutHistory {
    public private(set) var current = Workspace()
    private var past: [Workspace] = [], future: [Workspace] = []
    public init() {}
    public mutating func commit(_ next: Workspace) {
        guard next != current else { return }
        past.append(current); if past.count > 100 { past.removeFirst() }; current = next; future = []
    }
    public mutating func undo() -> Workspace {
        if let previous = past.popLast() { future.append(current); current = previous }; return current
    }
    public mutating func redo() -> Workspace {
        if let next = future.popLast() { past.append(current); current = next }; return current
    }
}
public struct DragIntent {
    private var monitor: String?, target: UUID?, edge: Placement = .center
    private var enteredAt: Double = 0, armed = false
    public init() {}
    public mutating func reset() { self = DragIntent() }
    public mutating func update(display: String, target: UUID, bounds: Rect, point: Point, now: Double, holdMilliseconds: Int) throws -> (placement: Placement, progress: Double) {
        var next = try LayoutEngine.placement(in: bounds, at: point)
        if monitor == display && self.target == target && edge != .center && next != edge && withinEdge(bounds, point, edge) { next = edge }
        if monitor != display || self.target != target || edge != next {
            monitor = display; self.target = target; edge = next; enteredAt = now; armed = false
        }
        if edge == .center { return (.center, 0) }
        let progress = holdMilliseconds <= 0 ? 1 : max(0, min(1, (now - enteredAt) * 1000 / Double(holdMilliseconds)))
        armed = armed || progress >= 1
        return (armed ? edge : .center, progress)
    }
    private func withinEdge(_ r: Rect, _ p: Point, _ edge: Placement) -> Bool {
        let x = Double(p.x - r.x), y = Double(p.y - r.y), w = Double(r.width), h = Double(r.height)
        switch edge {
        case .left: return x <= w * 0.25 + 10 && y >= h * 0.2 && y <= h * 0.8
        case .right: return w - x <= w * 0.25 + 10 && y >= h * 0.2 && y <= h * 0.8
        case .top: return y <= h * 0.25 + 10 && x >= w * 0.2 && x <= w * 0.8
        case .bottom: return h - y <= h * 0.25 + 10 && x >= w * 0.2 && x <= w * 0.8
        case .center: return false
        }
    }
}
