import Foundation

/// A bounded, order-independent search over slicing layouts. Each subset keeps
/// only its non-dominated minimum rectangles; native windows are never probed.
enum CapacityPlanner {
    private struct Shape { let minimum: Size; let tree: LayoutNode }

    static func plan(_ windows: [WindowLeaf], in area: Rect, gap: Int, all: Bool) -> LayoutNode? {
        guard !windows.isEmpty, windows.count <= 8 else { return nil }
        let end = 1 << windows.count
        var shapes = Array(repeating: [Shape](), count: end)
        for index in windows.indices {
            let leaf = windows[index]
            if leaf.minimum.width <= area.width && leaf.minimum.height <= area.height {
                shapes[1 << index] = [Shape(minimum: leaf.minimum, tree: .window(leaf))]
            }
        }
        var remaining = 250_000
        for mask in 1..<end where mask.nonzeroBitCount > 1 {
            var a = (mask - 1) & mask
            while a > 0 {
                let b = mask ^ a
                // Keep the most recent member first and visit each partition once.
                if a & (mask & -mask) != 0 {
                    for first in shapes[a] { for second in shapes[b] {
                        for axis in [Axis.horizontal, .vertical] {
                            remaining -= 1
                            guard remaining >= 0 else { return nil }
                            let x = first.minimum, y = second.minimum
                            let minimum = axis == .horizontal ? Size(x.width + gap + y.width, max(x.height, y.height)) : Size(max(x.width, y.width), x.height + gap + y.height)
                            guard minimum.width <= area.width, minimum.height <= area.height else { continue }
                            if shapes[mask].contains(where: { $0.minimum.width <= minimum.width && $0.minimum.height <= minimum.height }) { continue }
                            shapes[mask].removeAll { minimum.width <= $0.minimum.width && minimum.height <= $0.minimum.height }
                            shapes[mask].append(Shape(minimum: minimum, tree: .split(id: UUID(), axis: axis, ratio: 0.5, first: first.tree, second: second.tree)))
                        }
                    } }
                }
                a = (a - 1) & mask
            }
        }
        // Keep the focused/recent app, maximize usable app count, then prefer
        // recent membership. Geometry preferences never evict a fitting app.
        let masks = all ? [end - 1] : (1..<end).filter { $0 & 1 != 0 }.sorted {
            if $0.nonzeroBitCount != $1.nonzeroBitCount { return $0.nonzeroBitCount > $1.nonzeroBitCount }
            for bit in windows.indices where ($0 & (1 << bit)) != ($1 & (1 << bit)) { return $0 & (1 << bit) != 0 }
            return false
        }
        let primary = windows[0].windowID
        func expand(_ tree: LayoutNode, _ bounds: Rect) -> LayoutNode {
            guard case let .split(id, axis, _, first, second) = tree else { return tree }
            let length = (axis == .horizontal ? bounds.width : bounds.height) - gap
            func weight(_ node: LayoutNode) -> Double { Double(node.windows.count) + (node.windows.contains { $0.windowID == primary } ? 0.6 : 0) }
            let a = LayoutEngine.minimum(first, gap: gap), b = LayoutEngine.minimum(second, gap: gap)
            let low = axis == .horizontal ? a.width : a.height, high = length - (axis == .horizontal ? b.width : b.height)
            let cut = max(low, min(high, Int((Double(length) * weight(first) / (weight(first) + weight(second))).rounded())))
            let r1 = axis == .horizontal ? Rect(bounds.x, bounds.y, cut, bounds.height) : Rect(bounds.x, bounds.y, bounds.width, cut)
            let r2 = axis == .horizontal ? Rect(bounds.x + cut + gap, bounds.y, length - cut, bounds.height) : Rect(bounds.x, bounds.y + cut + gap, bounds.width, length - cut)
            return .split(id: id, axis: axis, ratio: Double(cut) / Double(length), first: expand(first, r1), second: expand(second, r2))
        }
        for mask in masks where !shapes[mask].isEmpty {
            var best: LayoutNode?, bestScore = -Double.infinity
            for shape in shapes[mask] {
                let tree = expand(shape.tree, area)
                guard let regions = try? LayoutEngine.calculate(tree, in: area, gap: gap).regions else { continue }
                let primaryArea = regions.first { $0.window.windowID == primary }.map { Double($0.bounds.width * $0.bounds.height) } ?? 0
                let total = Double(max(1, area.width * area.height))
                // Prefer a useful primary and avoid very thin panes. Ties retain
                // deterministic partition order, independent of UUID generation.
                let thinness = regions.reduce(0.0) { value, region in
                    let r = region.bounds
                    return value + max(0, abs(log(Double(r.width) / Double(r.height))) - 1.2)
                }
                let largest = regions.allSatisfy { Double($0.bounds.width * $0.bounds.height) <= primaryArea }
                let score = primaryArea / total + (largest ? 0.25 : 0) - thinness * 0.15
                if score > bestScore { best = tree; bestScore = score }
            }
            if let best { return best }
        }
        return nil
    }
}
