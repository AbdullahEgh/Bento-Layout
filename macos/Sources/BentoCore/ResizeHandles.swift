import Foundation

/// Equivalent slicing trees expose all valid local and shared seams without
/// moving a single window. A gesture chooses its tree once and keeps it until up.
public struct ResizeHandle: Equatable, Sendable {
    public let divider: Divider
    public let root: LayoutNode
    public var shared: Bool = false
}
public enum ResizeHandles {
    public static func calculate(_ root: LayoutNode, in area: Rect, gap: Int) throws -> [ResizeHandle] {
        let original = try LayoutEngine.calculate(root, in: area, gap: gap)
        var result = original.dividers.map { ResizeHandle(divider: $0, root: root) }
        guard gap > 0 else { return result }
        func cuts(_ regions: [Region], _ rect: Rect, _ axis: Axis) -> [Int] {
            let horizontal = axis == .horizontal
            return Set(regions.map { horizontal ? $0.bounds.right : $0.bounds.bottom }).sorted().filter { cut in
                let first = regions.filter { (horizontal ? $0.bounds.right : $0.bounds.bottom) <= cut }
                let second = regions.filter { (horizontal ? $0.bounds.x : $0.bounds.y) >= cut + gap }
                return !first.isEmpty && !second.isEmpty && first.count + second.count == regions.count
                    && first.contains { (horizontal ? $0.bounds.right : $0.bounds.bottom) == cut }
                    && second.contains { (horizontal ? $0.bounds.x : $0.bounds.y) == cut + gap }
            }
        }
        func stableID(_ regions: [Region], axis: Axis, first: [Region]) -> UUID {
            let key = axis.rawValue + regions.map { $0.window.id.uuidString }.sorted().joined() + ":" + first.map { $0.window.id.uuidString }.sorted().joined()
            func hash(_ seed: UInt64) -> UInt64 { key.utf8.reduce(seed) { ($0 ^ UInt64($1)) &* 1099511628211 } }
            let hex = String(format: "%016llx%016llx", hash(14695981039346656037), hash(1099511628211))
            let a = Array(hex)
            return UUID(uuidString: String(a[0..<8]) + "-" + String(a[8..<12]) + "-" + String(a[12..<16]) + "-" + String(a[16..<20]) + "-" + String(a[20..<32]))!
        }
        func build(_ regions: [Region], _ rect: Rect, forced: (Axis, Int)? = nil, preferred: Axis = .horizontal) -> LayoutNode? {
            if regions.count == 1 { return regions[0].bounds == rect ? .window(regions[0].window) : nil }
            let choices: [(Axis, Int)] = forced.map { [$0] } ?? [preferred, preferred == .horizontal ? .vertical : .horizontal].flatMap { axis in cuts(regions, rect, axis).map { (axis, $0) } }
            for (axis, cut) in choices {
                let h = axis == .horizontal
                let first = regions.filter { (h ? $0.bounds.right : $0.bounds.bottom) <= cut }
                let second = regions.filter { (h ? $0.bounds.x : $0.bounds.y) >= cut + gap }
                guard !first.isEmpty, !second.isEmpty, first.count + second.count == regions.count else { continue }
                let length = (h ? rect.width : rect.height) - gap, start = h ? rect.x : rect.y
                let a = h ? Rect(rect.x, rect.y, cut - start, rect.height) : Rect(rect.x, rect.y, rect.width, cut - start)
                let b = h ? Rect(cut + gap, rect.y, rect.right - cut - gap, rect.height) : Rect(rect.x, cut + gap, rect.width, rect.bottom - cut - gap)
                guard let left = build(first, a, preferred: preferred), let right = build(second, b, preferred: preferred) else { continue }
                let bounds = h ? Rect(cut, rect.y, gap, rect.height) : Rect(rect.x, cut, rect.width, gap)
                let id = original.dividers.first { $0.axis == axis && $0.bounds == bounds && $0.parent == rect }?.id ?? stableID(regions, axis: axis, first: first)
                return .split(id: id, axis: axis, ratio: Double(cut - start) / Double(length), first: left, second: right)
            }
            return nil
        }
        // Every original subtree is also considered: local alternatives must not
        // require rotating an unrelated ancestor or changing an unrelated slot.
        var visited = Set<[Int]>()
        func visit(_ node: LayoutNode, _ rect: Rect, base: LayoutNode) throws {
            let layout = try LayoutEngine.calculate(node, in: rect, gap: gap)
            if visited.insert([rect.x, rect.y, rect.width, rect.height]).inserted {
                for axis in [Axis.horizontal, .vertical] {
                    for cut in cuts(layout.regions, rect, axis) {
                        guard let alternate = build(layout.regions, rect, forced: (axis, cut), preferred: axis) else { continue }
                        let candidate = base.replacing(node.id, with: alternate)
                        let geometry = try LayoutEngine.calculate(candidate, in: area, gap: gap)
                        guard geometry.regions.allSatisfy({ region in original.regions.contains { $0.window.windowID == region.window.windowID && $0.bounds == region.bounds } }) else { continue }
                        for divider in geometry.dividers where !result.contains(where: { $0.divider.bounds == divider.bounds && $0.divider.axis == divider.axis && $0.divider.parent == divider.parent }) {
                            result.append(ResizeHandle(divider: divider, root: candidate))
                        }
                        // Rotating an ancestor can create a new rectangular group
                        // (e.g. the left two of three columns). Explore its children
                        // too; original-tree subgroups alone miss the joined grip.
                        try visit(alternate, rect, base: candidate)
                    }
                }
            }
            if case let .split(_, axis, _, a, b) = node, let divider = layout.dividers.first {
                let d = divider.bounds
                try visit(a, axis == .horizontal ? Rect(rect.x, rect.y, d.x - rect.x, rect.height) : Rect(rect.x, rect.y, rect.width, d.y - rect.y), base: base)
                try visit(b, axis == .horizontal ? Rect(d.right, rect.y, rect.right - d.right, rect.height) : Rect(rect.x, d.bottom, rect.width, rect.bottom - d.bottom), base: base)
            }
        }
        try visit(root, area, base: root)
        func movable(_ node: LayoutNode, _ divider: Divider) -> Bool {
            guard case let .split(id, axis, _, a, b) = node else { return false }
            if id != divider.id { return movable(a, divider) || movable(b, divider) }
            let m1 = LayoutEngine.minimum(a, gap: gap), m2 = LayoutEngine.minimum(b, gap: gap)
            return axis == .horizontal ? m1.width + m2.width + gap < divider.parent.width
                : m1.height + m2.height + gap < divider.parent.height
        }
        result.removeAll { !movable($0.root, $0.divider) }
        for i in result.indices {
            let d = result[i].divider
            result[i].shared = result.contains { other in
                let b = other.divider
                return b.axis == d.axis && b.bounds != d.bounds && (d.axis == .horizontal
                    ? b.bounds.x == d.bounds.x && b.bounds.y >= d.bounds.y && b.bounds.bottom <= d.bounds.bottom
                    : b.bounds.y == d.bounds.y && b.bounds.x >= d.bounds.x && b.bounds.right <= d.bounds.right)
            }
        }
        return result
    }
    /// Local ink is 80 points long; allow 40 points of padding at each end.
    public static let localHitRadius = 80
    public static func contains(_ outer: ResizeHandle, _ inner: ResizeHandle) -> Bool {
        let a = outer.divider, b = inner.divider
        guard a.axis == b.axis else { return false }
        return a.axis == .horizontal
            ? a.bounds.x == b.bounds.x && a.bounds.y <= b.bounds.y && a.bounds.bottom >= b.bounds.bottom && a.bounds.height > b.bounds.height
            : a.bounds.y == b.bounds.y && a.bounds.x <= b.bounds.x && a.bounds.right >= b.bounds.right && a.bounds.width > b.bounds.width
    }
    public static func isUniversal(_ handle: ResizeHandle, among handles: [ResizeHandle]) -> Bool {
        !handles.contains { contains($0, handle) }
    }
    /// Announce only the full joined seam, never its overlapping subgroups.
    public static func newlyJoined(_ handles: [ResizeHandle], previous: [ResizeHandle]) -> [ResizeHandle] {
        guard !previous.isEmpty else { return [] }
        return handles.filter { handle in
            handle.shared && isUniversal(handle, among: handles) && !previous.contains {
                $0.shared && $0.divider.axis == handle.divider.axis && $0.divider.bounds == handle.divider.bounds
            }
        }
    }
    /// Local sections win only beside their short grip. The remainder belongs
    /// to the longest joined seam. Standalone dividers keep their full hit area.
    public static func hit(_ handles: [ResizeHandle], at point: Point) -> ResizeHandle? {
        let hits = handles.filter { $0.divider.bounds.contains(point) }
        func centerDistance(_ handle: ResizeHandle) -> Int {
            let d = handle.divider
            return abs(d.axis == .horizontal ? point.y - (d.bounds.y + d.bounds.height / 2) : point.x - (d.bounds.x + d.bounds.width / 2))
        }
        func nearer(_ a: ResizeHandle, _ b: ResizeHandle) -> Bool {
            let x = centerDistance(a), y = centerDistance(b)
            if x != y { return x < y }
            let sa = a.divider.bounds.width + a.divider.bounds.height, sb = b.divider.bounds.width + b.divider.bounds.height
            return sa == sb ? a.divider.id.uuidString < b.divider.id.uuidString : sa < sb
        }
        let local = hits.filter { !isUniversal($0, among: handles) && centerDistance($0) <= localHitRadius }
        if let selected = local.min(by: nearer) { return selected }
        return hits.filter { isUniversal($0, among: handles) }.min(by: nearer)
    }
}
