import Foundation

/// One immutable result per display. Every geometry input participates in the key;
/// focus, hover and menu updates can reuse handles without exploring slicing trees.
public struct ResizeHandleCache {
    private struct Entry {
        let root: LayoutNode
        let area: Rect
        let gap: Int
        let handles: [ResizeHandle]
    }
    private var entries: [String: Entry] = [:]
    public private(set) var calculationCount = 0
    public var entryCount: Int { entries.count }
    public init() {}
    public mutating func handles(display: String, root: LayoutNode, area: Rect, gap: Int) throws -> [ResizeHandle] {
        if let entry = entries[display], entry.root == root, entry.area == area, entry.gap == gap { return entry.handles }
        let handles = try ResizeHandles.calculate(root, in: area, gap: gap)
        entries[display] = Entry(root: root, area: area, gap: gap, handles: handles)
        calculationCount += 1
        return handles
    }
    public mutating func retain(displays: Set<String>) { entries = entries.filter { displays.contains($0.key) } }
    public mutating func removeAll() { entries.removeAll() }
}

/// Full seam ink is interrupted around each short section pill. Hit geometry is
/// intentionally independent: the short pill has a larger invisible target.
public enum GripInk {
    public static func segments(span: Double, localCenters: [Double]) -> [ClosedRange<Double>] {
        let end = span - 4
        guard end > 4 else { return [] }
        let pills = localCenters.sorted().compactMap { center -> ClosedRange<Double>? in
            let lo = max(4, center - 40), hi = min(end, center + 40)
            return lo < hi ? lo...hi : nil
        }
        var result: [ClosedRange<Double>] = [], cursor = 4.0
        for pill in pills {
            let stop = max(4, pill.lowerBound - 8)
            if cursor < stop { result.append(cursor...stop) }
            cursor = max(cursor, min(end, pill.upperBound + 8))
        }
        if cursor < end { result.append(cursor...end) }
        return result + pills
    }
    public static func joinOpacity(elapsed: Double) -> Double {
        let t = min(1, max(0, (elapsed - 0.18) / 0.37))
        return 1 - t * t * (3 - 2 * t)
    }
}
