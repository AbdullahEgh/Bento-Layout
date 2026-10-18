import Foundation

// Integer logical points on macOS, physical pixels on Windows. Fixtures describe abstract
// units. Only the platform adapter converts coordinates; the engine never changes scale.
public struct Point: Codable, Equatable, Sendable {
    public var x: Int; public var y: Int
    public init(_ x: Int, _ y: Int) { self.x = x; self.y = y }
}
public struct Size: Codable, Equatable, Sendable {
    public var width: Int; public var height: Int
    public init(_ width: Int, _ height: Int) { self.width = width; self.height = height }
}
public struct Rect: Codable, Equatable, Sendable {
    public var x: Int; public var y: Int; public var width: Int; public var height: Int
    public init(_ x: Int, _ y: Int, _ width: Int, _ height: Int) {
        self.x = x; self.y = y; self.width = width; self.height = height
    }
    public var right: Int { x + width }; public var bottom: Int { y + height }
    public func contains(_ p: Point) -> Bool { p.x >= x && p.x < right && p.y >= y && p.y < bottom }
    public func inset(_ amount: Int) -> Rect { Rect(x + amount, y + amount, max(0, width - 2 * amount), max(0, height - 2 * amount)) }
}
public enum Axis: String, Codable, Sendable { case horizontal, vertical }
public enum Placement: String, Codable, Sendable { case left, right, top, bottom, center }
public struct WindowLeaf: Codable, Equatable, Sendable {
    public var id: UUID; public var windowID: UUID; public var minimum: Size
    public init(id: UUID = UUID(), windowID: UUID, minimum: Size) { self.id = id; self.windowID = windowID; self.minimum = minimum }
}
public indirect enum LayoutNode: Codable, Equatable, Sendable {
    case window(WindowLeaf)
    case split(id: UUID, axis: Axis, ratio: Double, first: LayoutNode, second: LayoutNode)
    public var id: UUID { switch self { case .window(let w): return w.id; case .split(let id, _, _, _, _): return id } }
    public var windows: [WindowLeaf] {
        switch self { case .window(let w): return [w]; case .split(_, _, _, let a, let b): return a.windows + b.windows }
    }
    public func replacing(_ target: UUID, with replacement: LayoutNode) -> LayoutNode {
        if id == target { return replacement }
        guard case let .split(id, axis, ratio, a, b) = self else { return self }
        return .split(id: id, axis: axis, ratio: ratio, first: a.replacing(target, with: replacement), second: b.replacing(target, with: replacement))
    }
    public func removing(_ windowID: UUID) -> LayoutNode? {
        switch self {
        case .window(let w): return w.windowID == windowID ? nil : self
        case let .split(id, axis, ratio, a, b):
            let first = a.removing(windowID), second = b.removing(windowID)
            guard let first else { return second }; guard let second else { return first }
            return .split(id: id, axis: axis, ratio: ratio, first: first, second: second)
        }
    }
    public func resizing(_ target: UUID, ratio: Double) -> LayoutNode {
        guard case let .split(id, axis, oldRatio, a, b) = self else { return self }
        return .split(id: id, axis: axis, ratio: id == target ? ratio : oldRatio,
                      first: a.resizing(target, ratio: ratio), second: b.resizing(target, ratio: ratio))
    }
}
public struct Region: Equatable, Sendable { public let window: WindowLeaf; public let bounds: Rect }
public struct Divider: Equatable, Sendable { public let id: UUID; public let axis: Axis; public let bounds: Rect; public let parent: Rect }
public struct LayoutResult: Sendable { public var regions: [Region] = []; public var dividers: [Divider] = [] }
public enum LayoutError: Error, LocalizedError {
    case cannotFit, invalidInput, missingTarget
    public var errorDescription: String? {
        switch self {
        case .cannotFit: return "These windows cannot fit at usable sizes. Minimize a window or use a larger display."
        case .invalidInput: return "The layout contains invalid geometry."
        case .missingTarget: return "That window is no longer available."
        }
    }
}
public enum LayoutEngine {
    public static func minimum(_ node: LayoutNode, gap: Int) -> Size {
        switch node {
        case .window(let w): return w.minimum
        case let .split(_, axis, _, a, b):
            let x = minimum(a, gap: gap), y = minimum(b, gap: gap)
            return axis == .horizontal ? Size(x.width + gap + y.width, max(x.height, y.height)) : Size(max(x.width, y.width), x.height + gap + y.height)
        }
    }
    public static func calculate(_ root: LayoutNode?, in area: Rect, gap: Int = 8) throws -> LayoutResult {
        guard gap >= 0, area.width >= 0, area.height >= 0 else { throw LayoutError.invalidInput }
        var result = LayoutResult()
        func visit(_ node: LayoutNode, _ rect: Rect) throws {
            let minSize = minimum(node, gap: gap)
            guard minSize.width > 0, minSize.height > 0, rect.width >= minSize.width, rect.height >= minSize.height else { throw LayoutError.cannotFit }
            switch node {
            case .window(let w): result.regions.append(Region(window: w, bounds: rect))
            case let .split(id, axis, ratio, a, b):
                guard ratio.isFinite else { throw LayoutError.invalidInput }
                let m1 = minimum(a, gap: gap), m2 = minimum(b, gap: gap), horizontal = axis == .horizontal
                let length = (horizontal ? rect.width : rect.height) - gap
                // .NET Math.Round defaults to ties-to-even. Preserve it for shared fixtures.
                let rounded = Int((Double(length) * max(0, min(1, ratio))).rounded(.toNearestOrEven))
                let first = max(horizontal ? m1.width : m1.height, min(length - (horizontal ? m2.width : m2.height), rounded))
                let aRect = horizontal ? Rect(rect.x, rect.y, first, rect.height) : Rect(rect.x, rect.y, rect.width, first)
                let bRect = horizontal ? Rect(rect.x + first + gap, rect.y, length - first, rect.height) : Rect(rect.x, rect.y + first + gap, rect.width, length - first)
                let divider = horizontal ? Rect(rect.x + first, rect.y, gap, rect.height) : Rect(rect.x, rect.y + first, rect.width, gap)
                result.dividers.append(Divider(id: id, axis: axis, bounds: divider, parent: rect))
                try visit(a, aRect); try visit(b, bRect)
            }
        }
        if let root { try visit(root, area) }
        return result
    }
    public static func placement(in rect: Rect, at point: Point) throws -> Placement {
        guard rect.contains(point) else { throw LayoutError.invalidInput }
        let x = Double(point.x - rect.x) / Double(rect.width), y = Double(point.y - rect.y) / Double(rect.height)
        if x >= 0.25 && x <= 0.75 && y >= 0.25 && y <= 0.75 { return .center }
        let nearest = min(x, 1 - x, y, 1 - y)
        if nearest == x { return .left }; if nearest == 1 - x { return .right }
        return nearest == y ? .top : .bottom
    }
}

/// Desktop controls can briefly leave AppKit's visible frame stale while hiding.
/// Reclaim only opted-out reservations, retaining the camera-safe top inset.
public enum DesktopWorkArea {
    /// A shown system menu bar can precede the visibleFrame notification. Its
    /// WindowServer geometry is authoritative; an auto-hidden hover is excluded
    /// by the platform adapter, so transient reveals do not shrink the layout.
    public static func correctingMenu(frame: Rect, visible: Rect, bars: [Rect]) -> Rect {
        let bottom = bars.filter { abs($0.y - frame.y) <= 2 && $0.width >= frame.width * 4 / 5 && $0.x <= frame.x + 2 && $0.right >= frame.right - 2 }.map(\.bottom).max() ?? visible.y
        let top = max(visible.y, min(frame.bottom, bottom))
        return Rect(visible.x, top, visible.width, max(0, visible.bottom - top))
    }

    /// Dock accessibility geometry updates when its size/edge changes, even when
    /// NSScreen still reports the previous reservation. Ignore off-screen/invalid
    /// data and keep the menu-bar boundary independent of the Dock.
    public static func correctingDock(frame: Rect, visible: Rect, dock: Rect?) -> Rect {
        guard let dock, dock.width > 0, dock.height > 0,
              dock.right > frame.x, dock.x < frame.right, dock.bottom > frame.y, dock.y < frame.bottom else { return visible }
        var left = frame.x, right = frame.right, bottom = frame.bottom
        if dock.width >= dock.height, abs(frame.bottom - dock.bottom) <= 32, dock.height < frame.height / 3 {
            // AX includes a small visual fringe on some releases. Keep an
            // already matching AppKit reservation instead of shrinking by it.
            if frame.bottom - visible.bottom >= 8, abs(visible.bottom - dock.y) <= 8 { return visible }
            bottom = max(visible.y, dock.y)
        } else if dock.height > dock.width, abs(dock.x - frame.x) <= 32, dock.width < frame.width / 3 {
            left = dock.right
        } else if dock.height > dock.width, abs(frame.right - dock.right) <= 32, dock.width < frame.width / 3 {
            right = dock.x
        } else { return visible }
        return Rect(left, visible.y, max(0, right - left), max(0, bottom - visible.y))
    }

    public static func calculate(frame: Rect, visible: Rect, hideMenuBar: Bool, hideDock: Bool, safeTop: Int = 0, margin: Int = 0) -> Rect {
        let top = max(frame.y + safeTop, hideMenuBar ? frame.y : visible.y)
        let left = hideDock ? frame.x : max(frame.x, visible.x)
        let right = hideDock ? frame.right : min(frame.right, visible.right)
        let bottom = hideDock ? frame.bottom : min(frame.bottom, visible.bottom)
        return Rect(left, top, max(0, right - left), max(0, bottom - top)).inset(margin)
    }
}
