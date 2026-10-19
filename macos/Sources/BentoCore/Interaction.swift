import Foundation

public enum InteractionGeometry {
    /// Move the outermost eligible section, carrying its complete subtree with it.
    /// Mirroring the measured split keeps each section's size even when minima
    /// clamped the saved ratio; no app is squeezed into a different leaf slot.
    public static func moveSection(_ workspace: Workspace, source: UUID, display: String, toward edge: Placement, area: Rect, gap: Int) throws -> Workspace? {
        guard edge != .center, let root = workspace.roots[display], root.windows.contains(where: { $0.windowID == source }) else { return nil }
        let layout = try LayoutEngine.calculate(root, in: area, gap: gap)
        let axis: Axis = edge == .left || edge == .right ? .horizontal : .vertical
        let wantsFirst = edge == .left || edge == .top
        func moved(_ node: LayoutNode) -> LayoutNode? {
            guard case let .split(id, direction, ratio, first, second) = node else { return nil }
            let inFirst = first.windows.contains { $0.windowID == source }
            if direction == axis && inFirst != wantsFirst,
               let divider = layout.dividers.first(where: { $0.id == id }) {
                let length = (axis == .horizontal ? divider.parent.width : divider.parent.height) - gap
                let offset = axis == .horizontal ? divider.bounds.x - divider.parent.x : divider.bounds.y - divider.parent.y
                return .split(id: id, axis: direction, ratio: Double(length - offset) / Double(length), first: second, second: first)
            }
            guard let child = moved(inFirst ? first : second) else { return nil }
            return .split(id: id, axis: direction, ratio: ratio, first: inFirst ? child : first, second: inFirst ? second : child)
        }
        guard let replacement = moved(root) else { return nil }
        _ = try LayoutEngine.calculate(replacement, in: area, gap: gap)
        var next = workspace; next.roots[display] = replacement; return next
    }

    public static func resize(_ workspace: Workspace, display: String, divider: Divider, pointer: Point, area: Rect, gap: Int, grabbedAt: Point? = nil) throws -> Workspace {
        guard let root = workspace.roots[display], (try LayoutEngine.calculate(root, in: area, gap: gap)).dividers.contains(where: { $0.id == divider.id }) else { throw LayoutError.missingTarget }
        let horizontal = divider.axis == .horizontal
        let length = (horizontal ? divider.parent.width : divider.parent.height) - gap
        guard length > 0 else { throw LayoutError.invalidInput }
        let position: Int
        if let grabbedAt {
            let delta = horizontal ? pointer.x - grabbedAt.x : pointer.y - grabbedAt.y
            if delta == 0 { return workspace }
            position = (horizontal ? divider.bounds.x - divider.parent.x : divider.bounds.y - divider.parent.y) + delta
        } else {
            position = (horizontal ? pointer.x - divider.parent.x : pointer.y - divider.parent.y) - gap / 2
        }
        let candidate = root.resizing(divider.id, ratio: max(0, min(1, Double(position) / Double(length))))
        _ = try LayoutEngine.calculate(candidate, in: area, gap: gap)
        var next = workspace; next.roots[display] = try snappingSeam(candidate, divider: divider.id, area: area, gap: gap); return next
    }
    /// Snap only adjoining, parallel sections. The inactive section stays fixed;
    /// exact alignment lets ResizeHandles derive the perpendicular local cuts.
    /// Each sample starts from the gesture snapshot, so pulling away breaks the join.
    public static func snappingSeam(_ root: LayoutNode, divider id: UUID, area: Rect, gap: Int, distance: Int = 12) throws -> LayoutNode {
        let layout = try LayoutEngine.calculate(root, in: area, gap: gap)
        guard let moving = layout.dividers.first(where: { $0.id == id }) else { return root }
        let h = moving.axis == .horizontal
        let position = h ? moving.bounds.x : moving.bounds.y
        let neighbors = layout.dividers.filter { other in
            guard other.id != id, other.axis == moving.axis else { return false }
            let adjacent = h
                ? abs(other.bounds.bottom - moving.bounds.y) <= gap || abs(moving.bounds.bottom - other.bounds.y) <= gap
                : abs(other.bounds.right - moving.bounds.x) <= gap || abs(moving.bounds.right - other.bounds.x) <= gap
            return adjacent && abs((h ? other.bounds.x : other.bounds.y) - position) <= distance
        }.sorted { a, b in
            let x = h ? a.bounds.x : a.bounds.y, y = h ? b.bounds.x : b.bounds.y
            return abs(x - position) == abs(y - position) ? x < y : abs(x - position) < abs(y - position)
        }
        for neighbor in neighbors {
            let target = h ? neighbor.bounds.x : neighbor.bounds.y
            let start = h ? moving.parent.x : moving.parent.y
            let length = (h ? moving.parent.width : moving.parent.height) - gap
            guard length > 0 else { continue }
            let candidate = root.resizing(id, ratio: Double(target - start) / Double(length))
            let result = try LayoutEngine.calculate(candidate, in: area, gap: gap)
            // A min-size clamp must never pretend that the seams joined.
            if let actual = result.dividers.first(where: { $0.id == id }),
               (h ? actual.bounds.x : actual.bounds.y) == target { return candidate }
        }
        return root
    }
    public static func resizeWindow(_ root: LayoutNode, windowID: UUID, requested: Rect, area: Rect, gap: Int) throws -> LayoutNode {
        guard let before = try LayoutEngine.calculate(root, in: area, gap: gap).regions.first(where: { $0.window.windowID == windowID }) else { return root }
        var result = root
        // Pick an equivalent local tree for each edited edge, not its saved
        // ancestor. Untouched rows/columns remain at their original rectangles.
        for (axis, leading, delta) in [(Axis.horizontal, true, requested.x - before.bounds.x),
                                      (.horizontal, false, requested.right - before.bounds.right),
                                      (.vertical, true, requested.y - before.bounds.y),
                                      (.vertical, false, requested.bottom - before.bounds.bottom)] where abs(delta) > 2 {
            let layout = try LayoutEngine.calculate(result, in: area, gap: gap)
            guard let leaf = layout.regions.first(where: { $0.window.windowID == windowID }) else { continue }
            let h = axis == .horizontal
            let edge = h ? (leading ? leaf.bounds.x : leaf.bounds.right) : (leading ? leaf.bounds.y : leaf.bounds.bottom)
            let handles = try ResizeHandles.calculate(result, in: area, gap: gap).filter { handle in
                let d = handle.divider
                guard d.axis == axis else { return false }
                let boundary = h ? (leading ? d.bounds.right : d.bounds.x) : (leading ? d.bounds.bottom : d.bounds.y)
                let covers = h ? d.parent.y <= leaf.bounds.y && d.parent.bottom >= leaf.bounds.bottom
                    : d.parent.x <= leaf.bounds.x && d.parent.right >= leaf.bounds.right
                return edge == boundary && covers
            }
            guard let local = handles.min(by: { $0.divider.parent.width * $0.divider.parent.height < $1.divider.parent.width * $1.divider.parent.height }) else { continue }
            let d = local.divider, length = (h ? d.parent.width : d.parent.height) - gap
            guard length > 0 else { continue }
            let offset = (h ? d.bounds.x - d.parent.x : d.bounds.y - d.parent.y) + delta
            result = local.root.resizing(d.id, ratio: max(0, min(1, Double(offset) / Double(length))))
            result = try snappingSeam(result, divider: d.id, area: area, gap: gap)
        }
        return result
    }
}

public struct DropProposal: Equatable {
    public let workspace: Workspace
    public let bounds: Rect
    public let placement: Placement
    public let neighbors: [Rect]
    public let progress: Double
    public let waitingForSplit: Bool
    public var swapsSections = false
}
public struct DropSession {
    public let original: Workspace
    public let source: WindowLeaf
    public private(set) var conflictBounds: Rect?
    private var intent = DragIntent()
    private struct GeometryKey: Equatable { let display: String; let target: UUID?; let placement: Placement; var section = false }
    private struct Geometry { let workspace: Workspace; let bounds: Rect; let neighbors: [Rect]; var placement: Placement? = nil }
    private var cachedAreas: [String: Rect] = [:]
    private var cachedGap: Int?
    private var layouts: [String: LayoutResult] = [:]
    private var geometryKey: GeometryKey?
    private var geometry: Geometry?
    private var cachedConflict: Rect?
    private(set) var geometryBuildCount = 0
    public init(workspace: Workspace, source: WindowLeaf) { original = workspace; self.source = source }
    public mutating func propose(pointer: Point, areas: [String: Rect], gap: Int, hold: Int, now: Double, screenBounds: [String: Rect] = [:]) throws -> DropProposal? {
        conflictBounds = nil
        if cachedAreas != areas || cachedGap != gap {
            intent.reset()
            cachedAreas = areas; cachedGap = gap; layouts = [:]; geometryKey = nil; geometry = nil; cachedConflict = nil
            for (id, node) in original.roots {
                guard let area = areas[id] else { throw LayoutError.missingTarget }
                layouts[id] = try LayoutEngine.calculate(node, in: area, gap: gap)
            }
        }
        guard let display = areas.keys.sorted().first(where: { areas[$0]!.contains(pointer) || screenBounds[$0]?.contains(pointer) == true }) else { intent.reset(); return nil }
        // Only the thin physical screen edge activates section movement. The
        // normal slot interior keeps its quick swap / hold-to-split behavior.
        if let screen = screenBounds[display], screen.contains(pointer),
           original.roots[display]?.windows.contains(where: { $0.windowID == source.windowID }) == true {
            let distances: [(Placement, Int)] = [(.left, pointer.x - screen.x), (.right, screen.right - 1 - pointer.x),
                                                (.top, pointer.y - screen.y), (.bottom, screen.bottom - 1 - pointer.y)]
            if let (edge, distance) = distances.min(by: { $0.1 < $1.1 }), distance < 20 {
                intent.reset()
                let key = GeometryKey(display: display, target: nil, placement: edge, section: true)
                if geometryKey != key {
                    geometryKey = key; geometry = nil; cachedConflict = nil; geometryBuildCount += 1
                    if let next = try InteractionGeometry.moveSection(original, source: source.windowID, display: display, toward: edge, area: areas[display]!, gap: gap) {
                        let regions = try LayoutEngine.calculate(next.roots[display], in: areas[display]!, gap: gap).regions
                        let before = Dictionary(uniqueKeysWithValues: (layouts[display]?.regions ?? []).map { ($0.window.windowID, $0.bounds) })
                        if let destination = regions.first(where: { $0.window.windowID == source.windowID }) {
                            geometry = Geometry(workspace: next, bounds: destination.bounds,
                                neighbors: regions.filter { $0.window.windowID != source.windowID && before[$0.window.windowID] != $0.bounds }.map(\.bounds))
                        }
                    }
                }
                guard let geometry else { return nil }
                return DropProposal(workspace: geometry.workspace, bounds: geometry.bounds, placement: edge, neighbors: geometry.neighbors,
                                    progress: 0, waitingForSplit: false, swapsSections: true)
            }
        }
        let target = layouts[display]?.regions.first(where: { $0.bounds.contains(pointer) })
        guard target?.window.windowID != source.windowID,
              target != nil || original.roots[display] == nil else { intent.reset(); return nil }
        guard areas[display]!.contains(pointer) else { intent.reset(); return nil }
        let targetBounds = target?.bounds ?? areas[display]!
        let gesture: (placement: Placement, progress: Double, waitingForSplit: Bool)
        if let target {
            gesture = try intent.update(display: display, target: target.window.id, bounds: target.bounds, point: pointer, now: now, holdMilliseconds: hold)
        } else { intent.reset(); gesture = (.center, 0, false) }
        // Match the shared Windows interaction: floating windows insert beside a
        // slot, rather than silently ejecting its occupant on a quick center drop.
        let floating = !original.windows.contains { $0.windowID == source.windowID }
        let placement = floating && target != nil && gesture.placement == .center
            ? (targetBounds.width >= targetBounds.height ? Placement.right : .bottom) : gesture.placement
        let key = GeometryKey(display: display, target: target?.window.id, placement: placement)
        if geometryKey != key {
            geometryKey = key; geometry = nil; cachedConflict = nil; geometryBuildCount += 1
            var bases = [original]
            var placements = [placement]
            if floating && target != nil && gesture.placement == .center {
                placements.append(placement == .right ? .bottom : .right)
            }
            search: for direction in placements {
                var baseIndex = 0
                while baseIndex < bases.count {
                    let base = bases[baseIndex]; baseIndex += 1
                    let next = try base.placing(source, on: display, target: target?.window.id, placement: direction)
                    var destination: Rect?, neighbors: [Rect] = []
                    do {
                        for id in next.roots.keys.sorted() {
                            guard let workArea = areas[id], let node = next.roots[id] else { throw LayoutError.missingTarget }
                            let before = Dictionary(uniqueKeysWithValues: (layouts[id]?.regions ?? []).map { ($0.window.windowID, $0.bounds) })
                            for region in try LayoutEngine.calculate(node, in: workArea, gap: gap).regions {
                                if region.window.windowID == source.windowID { destination = region.bounds }
                                else if before[region.window.windowID] != region.bounds { neighbors.append(region.bounds) }
                            }
                        }
                        guard let destination else { throw LayoutError.missingTarget }
                        geometry = Geometry(workspace: next, bounds: destination, neighbors: neighbors, placement: direction)
                        break search
                    } catch LayoutError.cannotFit {
                        if baseIndex == 1 && bases.count == 1 {
                            if let root = original.roots[display], let area = areas[display] {
                                for handle in try ResizeHandles.calculate(root, in: area, gap: gap) {
                                    var alternate = original; alternate.roots[display] = handle.root
                                    if !bases.contains(alternate) { bases.append(alternate) }
                                }
                            }
                        }
                        continue
                    }
                }
            }
            if geometry == nil { cachedConflict = targetBounds }

        }
        conflictBounds = cachedConflict
        guard let geometry else { return nil }
        return DropProposal(workspace: geometry.workspace, bounds: geometry.bounds, placement: geometry.placement ?? placement, neighbors: geometry.neighbors,
                            progress: gesture.progress, waitingForSplit: gesture.waitingForSplit)
    }
}

/// A shared, time-based curve keeps a batch of windows moving together.
public enum WindowMotion {
    public static func frame(from: Rect, to: Rect, progress: Double) -> Rect {
        let t = max(0, min(1, progress.isFinite ? progress : 1))
        // Minimum-jerk curve: zero velocity and acceleration at both ends.
        // No overshoot, so app frames remain inside the planned transition.
        let eased = t * t * t * (t * (6 * t - 15) + 10)
        func mix(_ a: Int, _ b: Int) -> Int { Int((Double(a) + (Double(b) - Double(a)) * eased).rounded()) }
        return Rect(mix(from.x, to.x), mix(from.y, to.y), mix(from.width, to.width), mix(from.height, to.height))
    }
}
