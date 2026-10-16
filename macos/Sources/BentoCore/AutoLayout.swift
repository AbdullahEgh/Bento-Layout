import Foundation

public enum AutoLayout {
    /// Retain a valid edited layout where possible. Priority admission tries a
    /// fitting arrangement for all usable apps before evicting idle windows.
    /// Only capacity errors are recoverable; invalid geometry still fails explicitly.
    public static func fitting(_ windows: [WindowLeaf], in area: Rect, gap: Int = 8, preserving original: LayoutNode? = nil, prioritizing priority: Set<UUID> = [], leastRecentlyUsed: [UUID] = []) throws -> LayoutNode? {
        guard gap >= 0, area.width >= 0, area.height >= 0,
              Set(windows.map(\.windowID)).count == windows.count,
              windows.allSatisfy({ $0.minimum.width > 0 && $0.minimum.height > 0 }) else { throw LayoutError.invalidInput }
        if !priority.isEmpty {
            // Preserve edits and all windows if possible. Only remove candidates
            // when the whole set cannot fit, oldest interaction first.
            let feasiblePriority = priority.intersection(windows.filter {
                $0.minimum.width <= area.width && $0.minimum.height <= area.height
            }.map(\.windowID))
            guard !feasiblePriority.isEmpty else { return try fitting(windows, in: area, gap: gap, preserving: original) }
            if let original {
                let current = Dictionary(uniqueKeysWithValues: windows.map { ($0.windowID, $0) })
                var retained: LayoutNode? = original
                for leaf in original.windows {
                    if var updated = current[leaf.windowID] {
                        updated.id = leaf.id
                        retained = retained?.replacing(leaf.id, with: .window(updated))
                    } else { retained = retained?.removing(leaf.windowID) }
                }
                if let retained, (try? LayoutEngine.calculate(retained, in: area, gap: gap)) != nil {
                    return try admitLocally(windows, into: retained, in: area, gap: gap,
                        priority: feasiblePriority, leastRecentlyUsed: leastRecentlyUsed)
                }
            }
            // An individually impossible app must never force a usable app out
            // while we search for space for the focused/admitted window.
            var candidates = windows.filter { $0.minimum.width <= area.width && $0.minimum.height <= area.height }
            let rank = Dictionary(leastRecentlyUsed.enumerated().map { ($0.element, $0.offset) }, uniquingKeysWith: min)
            let evictionOrder = candidates.enumerated().filter { !feasiblePriority.contains($0.element.windowID) }.sorted {
                let a = rank[$0.element.windowID] ?? -1, b = rank[$1.element.windowID] ?? -1
                return a == b ? $0.offset < $1.offset : a < b
            }.map { $0.element.windowID }
            for index in 0...evictionOrder.count {
                let retained = try fitting(candidates, in: area, gap: gap, preserving: original)
                if retained?.windows.count == candidates.count { return retained }
                // A retained edited tree can be too restrictive; try a full reflow
                // before sacrificing another window.
                do { return try arrange(candidates, in: area, gap: gap) }
                catch LayoutError.cannotFit { }
                if index < evictionOrder.count { candidates.removeAll { $0.windowID == evictionOrder[index] } }
            }
            // Simultaneously reopened windows may not all fit together.
            return try fitting(candidates, in: area, gap: gap)
        }
        let byID = Dictionary(uniqueKeysWithValues: windows.map { ($0.windowID, $0) })
        var retained = original
        for leaf in original?.windows ?? [] {
            if var current = byID[leaf.windowID] {
                current.id = leaf.id
                retained = retained?.replacing(leaf.id, with: .window(current))
            } else { retained = retained?.removing(leaf.windowID) }
        }
        if let retained {
            do { _ = try LayoutEngine.calculate(retained, in: area, gap: gap) }
            catch LayoutError.cannotFit { return try fitting(windows, in: area, gap: gap) }
        } else {
            do { return try arrange(windows, in: area, gap: gap) }
            catch LayoutError.cannotFit { /* Build a usable subset below. */ }
        }
        let candidates = windows.enumerated().sorted {
            let a = Double($0.element.minimum.width) * Double($0.element.minimum.height)
            let b = Double($1.element.minimum.width) * Double($1.element.minimum.height)
            return a == b ? $0.offset < $1.offset : a < b
        }
        for (_, window) in candidates where !(retained?.windows.contains(where: { $0.windowID == window.windowID }) ?? false) {
            do { retained = try insert(window, into: retained, in: area, gap: gap) }
            catch LayoutError.cannotFit { continue }
        }
        return retained
    }

    // Admission is planned entirely in memory. Keep the split tree fixed where
    // possible: replace an idle window in its exact slot before expanding a branch.
    private static func admitLocally(_ windows: [WindowLeaf], into original: LayoutNode, in area: Rect,
                                     gap: Int, priority: Set<UUID>, leastRecentlyUsed: [UUID]) throws -> LayoutNode? {
        var root: LayoutNode? = original
        var displaced = Set<UUID>()
        let rank = Dictionary(leastRecentlyUsed.enumerated().map { ($0.element, $0.offset) }, uniquingKeysWith: min)
        let victims = original.windows.enumerated().filter { !priority.contains($0.element.windowID) }.sorted {
            let a = rank[$0.element.windowID] ?? -1, b = rank[$1.element.windowID] ?? -1
            return a == b ? $0.offset < $1.offset : a < b
        }.map(\.element)
        let incoming = windows.filter { priority.contains($0.windowID) }
        for window in incoming where !(root?.windows.contains { $0.windowID == window.windowID } ?? false) {
            if let inserted = try insertLocally(window, into: root, in: area, gap: gap) { root = inserted; continue }
            // A fragmented edited tree is not proof that the apps cannot fit.
            // Plan one full candidate in memory before minimizing an idle app.
            do {
                root = try arrange((root?.windows ?? []) + [window], in: area, gap: gap)
                continue
            } catch LayoutError.cannotFit { }
            for victim in victims where root?.windows.contains(where: { $0.windowID == victim.windowID }) == true {
                let replacement = root!.replacing(victim.id, with: .window(window))
                if let slot = try LayoutEngine.calculate(root, in: area, gap: gap).regions.first(where: { $0.window.windowID == victim.windowID }),
                   slot.bounds.width >= window.minimum.width, slot.bounds.height >= window.minimum.height {
                    root = replacement; displaced.insert(victim.windowID); break
                }
                root = root?.removing(victim.windowID); displaced.insert(victim.windowID)
                if let inserted = try insertLocally(window, into: root, in: area, gap: gap) { root = inserted; break }
            }
        }
        for window in windows where !priority.contains(window.windowID) && !displaced.contains(window.windowID)
            && !(root?.windows.contains { $0.windowID == window.windowID } ?? false) {
            if let inserted = try insertLocally(window, into: root, in: area, gap: gap) { root = inserted }
        }
        return root
    }
    private static func insertLocally(_ incoming: WindowLeaf, into root: LayoutNode?, in area: Rect, gap: Int) throws -> LayoutNode? {
        guard let root else {
            guard incoming.minimum.width <= area.width, incoming.minimum.height <= area.height else { return nil }
            return .window(incoming)
        }
        let regions = try LayoutEngine.calculate(root, in: area, gap: gap).regions.enumerated().sorted {
            let a = $0.element.bounds.width * $0.element.bounds.height, b = $1.element.bounds.width * $1.element.bounds.height
            return a == b ? $0.offset < $1.offset : a > b
        }.map(\.element)
        for region in regions {
            let wide = Double(region.bounds.width) >= Double(region.bounds.height) * 1.35
            for horizontal in [wide, !wide] {
                let branch = LayoutNode.split(id: UUID(), axis: horizontal ? .horizontal : .vertical, ratio: 0.5,
                    first: .window(region.window), second: .window(incoming))
                // Test the actual slot, so ancestors never move to satisfy this split.
                if (try? LayoutEngine.calculate(branch, in: region.bounds, gap: gap)) != nil {
                    return root.replacing(region.window.id, with: branch)
                }
            }
        }
        return nil
    }

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
