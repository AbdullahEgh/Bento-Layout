import Foundation

/// Preserve coincident row/column seams when the desktop changes size. Independent
/// branch clamping can separate seams that occupied the same physical line.
public enum LayoutReflow {
    public static func preservingSeams(_ root: LayoutNode, reference: LayoutNode, from old: Rect, to area: Rect, gap: Int) throws -> LayoutNode {
        let original = try LayoutEngine.calculate(reference, in: old, gap: gap)
        var result = root
        var visited = Set<UUID>()
        for seam in original.dividers where !visited.contains(seam.id) {
            let h = seam.axis == .horizontal
            let coordinate = h ? seam.bounds.x : seam.bounds.y
            let group = original.dividers.filter { $0.axis == seam.axis && (h ? $0.bounds.x : $0.bounds.y) == coordinate }
            visited.formUnion(group.map(\.id))
            guard group.count > 1 else { continue }
            let current = try LayoutEngine.calculate(result, in: area, gap: gap)
            let dividers = group.compactMap { old in current.dividers.first { $0.id == old.id } }
            guard dividers.count == group.count else { continue }
            func children(_ node: LayoutNode, _ id: UUID) -> (LayoutNode, LayoutNode)? {
                guard case let .split(key, _, _, a, b) = node else { return nil }
                return key == id ? (a, b) : children(a, id) ?? children(b, id)
            }
            var low = Int.min, high = Int.max
            for d in dividers {
                guard let (a, b) = children(result, d.id) else { throw LayoutError.missingTarget }
                let m1 = LayoutEngine.minimum(a, gap: gap), m2 = LayoutEngine.minimum(b, gap: gap)
                low = max(low, (h ? d.parent.x + m1.width : d.parent.y + m1.height))
                high = min(high, (h ? d.parent.right - m2.width : d.parent.bottom - m2.height) - gap)
            }
            // A shared row may genuinely not fit once system controls return.
            // Retain its branches and membership; do not rebuild the whole layout.
            guard low <= high else { continue }
            let oldLength = (h ? old.width : old.height) - gap
            guard oldLength > 0 else { continue }
            let fraction = Double(coordinate - (h ? old.x : old.y)) / Double(oldLength)
            let target = max(low, min(high, (h ? area.x : area.y) + Int((fraction * Double((h ? area.width : area.height) - gap)).rounded(.toNearestOrEven))))
            for d in dividers {
                let length = (h ? d.parent.width : d.parent.height) - gap
                result = result.resizing(d.id, ratio: Double(target - (h ? d.parent.x : d.parent.y)) / Double(length))
            }
        }
        _ = try LayoutEngine.calculate(result, in: area, gap: gap)
        return result
    }
}
