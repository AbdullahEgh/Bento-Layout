import Foundation

public enum AutoLayout {
    public static func arrange(_ windows: [WindowLeaf], in area: Rect, gap: Int = 8) throws -> LayoutNode? {
        guard gap >= 0, Set(windows.map(\.windowID)).count == windows.count,
              windows.allSatisfy({ $0.minimum.width > 0 && $0.minimum.height > 0 }) else { throw LayoutError.invalidInput }
        if windows.isEmpty { return nil }
        struct Key: Hashable { let start: Int; let count: Int; let width: Int; let height: Int }
        var failed = Set<Key>(), remaining = 100_000
        func build(_ start: Int, _ count: Int, _ width: Int, _ height: Int) -> LayoutNode? {
            remaining -= 1
            guard remaining >= 0, width > 0, height > 0 else { return nil }
            if count == 1 { let w = windows[start]; return width >= w.minimum.width && height >= w.minimum.height ? .window(w) : nil }
            let key = Key(start: start, count: count, width: width, height: height)
            if failed.contains(key) { return nil }
            let wide = Double(width) >= Double(height) * 1.35
            let midpoint = Double(count) / 2.0
            let counts: [Int] = (1..<count).sorted { (a: Int, b: Int) -> Bool in
                let distanceA = abs(Double(a) - midpoint)
                let distanceB = abs(Double(b) - midpoint)
                if distanceA == distanceB { return a < b }
                return distanceA < distanceB
            }
            for horizontal in [wide, !wide] {
                for firstCount in counts {
                    let length = (horizontal ? width : height) - gap
                    let minA = windows[start..<(start + firstCount)].map { horizontal ? $0.minimum.width : $0.minimum.height }.max()!
                    let minB = windows[(start + firstCount)..<(start + count)].map { horizontal ? $0.minimum.width : $0.minimum.height }.max()!
                    if length < minA + minB { continue }
                    var cuts = Set<Int>()
                    for raw in [length / 2, Int((Double(length) * Double(firstCount) / Double(count)).rounded(.toNearestOrEven)), minA, length - minB] {
                        let cut = max(minA, min(length - minB, raw))
                        if !cuts.insert(cut).inserted { continue }
                        if let a = build(start, firstCount, horizontal ? cut : width, horizontal ? height : cut),
                           let b = build(start + firstCount, count - firstCount, horizontal ? length - cut : width, horizontal ? height : length - cut) {
                            return .split(id: UUID(), axis: horizontal ? .horizontal : .vertical, ratio: Double(cut) / Double(length), first: a, second: b)
                        }
                    }
                }
            }
            failed.insert(key); return nil
        }
        guard let root = build(0, windows.count, area.width, area.height) else { throw LayoutError.cannotFit }
        _ = try LayoutEngine.calculate(root, in: area, gap: gap)
        return root
    }
    public static func insert(_ incoming: WindowLeaf, into root: LayoutNode?, in area: Rect, gap: Int = 8) throws -> LayoutNode {
        guard let root else { return try arrange([incoming], in: area, gap: gap)! }
        if root.windows.contains(where: { $0.windowID == incoming.windowID }) { return root }
        let regions = try LayoutEngine.calculate(root, in: area, gap: gap).regions.sorted { $0.bounds.width * $0.bounds.height > $1.bounds.width * $1.bounds.height }
        for region in regions {
            let wide = Double(region.bounds.width) >= Double(region.bounds.height) * 1.35
            for horizontal in [wide, !wide] {
                let branch = LayoutNode.split(id: UUID(), axis: horizontal ? .horizontal : .vertical, ratio: 0.5, first: .window(region.window), second: .window(incoming))
                let candidate = root.replacing(region.window.id, with: branch)
                if (try? LayoutEngine.calculate(candidate, in: area, gap: gap)) != nil { return candidate }
            }
        }
        return try arrange(root.windows + [incoming], in: area, gap: gap)!
    }
}
