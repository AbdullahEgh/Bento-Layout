import XCTest
@testable import BentoCore

final class ResizeHandleTests: XCTestCase {
    let area = Rect(0, 0, 1200, 800), gap = 10
    func leaf(_ w: Int = 100, _ h: Int = 100) -> LayoutNode { .window(WindowLeaf(windowID: UUID(), minimum: Size(w, h))) }
    func split(_ axis: Axis, _ a: LayoutNode, _ b: LayoutNode, ratio: Double = 0.5) -> LayoutNode {
        .split(id: UUID(), axis: axis, ratio: ratio, first: a, second: b)
    }
    func fixture() -> LayoutNode {
        split(.horizontal, split(.vertical, split(.horizontal, leaf(), leaf()), leaf()), split(.vertical, leaf(), leaf()), ratio: 0.6)
    }
    func frames(_ root: LayoutNode, _ area: Rect? = nil) throws -> [UUID: Rect] {
        Dictionary(uniqueKeysWithValues: try LayoutEngine.calculate(root, in: area ?? self.area, gap: gap).regions.map { ($0.window.windowID, $0.bounds) })
    }
    func testEquivalentHandlesNeverMoveWindowsAndHaveStableIdentity() throws {
        let root = fixture(), before = try frames(root)
        let handles = try ResizeHandles.calculate(root, in: area, gap: gap)
        XCTAssertGreaterThan(handles.count, 4)
        for h in handles { XCTAssertEqual(try frames(h.root), before) }
        XCTAssertEqual(handles, try ResizeHandles.calculate(root, in: area, gap: gap))
    }
    func testBottomRowResizesHorizontallyWithoutMovingTopRow() throws {
        let root = fixture(), before = try frames(root)
        let handles = try ResizeHandles.calculate(root, in: area, gap: gap)
        let handle = try XCTUnwrap(ResizeHandles.hit(handles, at: Point(718, 650)))
        XCTAssertEqual(handle.divider.axis, .horizontal)
        XCTAssertEqual(handle.divider.bounds.y, 405)
        XCTAssertFalse(handle.shared)
        let next = try InteractionGeometry.resize(Workspace(roots: ["screen": handle.root]), display: "screen", divider: handle.divider,
            pointer: Point(638, 650), area: area, gap: gap, grabbedAt: Point(718, 650))
        let after = try frames(XCTUnwrap(next.roots["screen"]))
        for (id, frame) in before where frame.y == 0 { XCTAssertEqual(after[id], frame) }
        XCTAssertEqual(after.values.filter { $0.y == 405 && $0.x == 0 }.first?.width, 634)
    }
    func testCenterSelectsSharedRowAndSideSelectsLocalRow() throws {
        let handles = try ResizeHandles.calculate(fixture(), in: area, gap: gap)
        let whole = try XCTUnwrap(ResizeHandles.hit(handles, at: Point(600, 399)))
        XCTAssertTrue(whole.shared); XCTAssertEqual(whole.divider.bounds.width, 1200)
        let local = try XCTUnwrap(ResizeHandles.hit(handles, at: Point(1050, 399)))
        XCTAssertFalse(local.shared); XCTAssertEqual(local.divider.bounds.x, 724)
    }
    func testLocalVerticalEditKeepsHorizontalResizeAvailable() throws {
        let handles = try ResizeHandles.calculate(fixture(), in: area, gap: gap)
        let local = try XCTUnwrap(ResizeHandles.hit(handles, at: Point(1050, 399)))
        let next = try InteractionGeometry.resize(Workspace(roots: ["screen": local.root]), display: "screen", divider: local.divider,
            pointer: Point(1050, 340), area: area, gap: gap, grabbedAt: Point(1050, 399))
        let updated = try ResizeHandles.calculate(XCTUnwrap(next.roots["screen"]), in: area, gap: gap)
        let horizontal = try XCTUnwrap(ResizeHandles.hit(updated, at: Point(718, 650)))
        XCTAssertEqual(horizontal.divider.axis, .horizontal)
        let moved = try InteractionGeometry.resize(Workspace(roots: ["screen": horizontal.root]), display: "screen", divider: horizontal.divider,
            pointer: Point(678, 650), area: area, gap: gap, grabbedAt: Point(718, 650))
        XCTAssertNotEqual(try frames(XCTUnwrap(moved.roots["screen"])), try frames(XCTUnwrap(next.roots["screen"])))
    }
    func testColumnsHaveTheSameSharedAndLocalOptions() throws {
        let root = split(.vertical, split(.horizontal, leaf(), leaf()), split(.horizontal, leaf(), leaf()))
        let handles = try ResizeHandles.calculate(root, in: area, gap: gap)
        let whole = try XCTUnwrap(ResizeHandles.hit(handles, at: Point(599, 400)))
        XCTAssertTrue(whole.shared); XCTAssertEqual(whole.divider.bounds.height, 800)
        let local = try XCTUnwrap(ResizeHandles.hit(handles, at: Point(599, 150)))
        XCTAssertFalse(local.shared); XCTAssertEqual(local.divider.bounds.height, 395)
    }
    func testDockReflowKeepsJoinedRowsWhenOneBranchHitsMinimum() throws {
        let root = split(.horizontal, split(.vertical, leaf(100, 350), leaf()), split(.vertical, leaf(), leaf()))
        let small = Rect(0, 30, 1200, 690)
        let next = try LayoutReflow.preservingSeams(root, reference: root, from: area, to: small, gap: gap)
        let dividers = try LayoutEngine.calculate(next, in: small, gap: gap).dividers.filter { $0.axis == .vertical }
        XCTAssertEqual(Set(dividers.map { $0.bounds.y }).count, 1)
        XCTAssertEqual(dividers.first?.bounds.y, 380)
        let restored = try LayoutReflow.preservingSeams(root, reference: root, from: area, to: area, gap: gap)
        XCTAssertEqual(try frames(restored), try frames(root))
    }
    func testImpossibleSharedRowRetainsMembershipWithoutOverlap() throws {
        let root = split(.horizontal, split(.vertical, leaf(100, 350), leaf()), split(.vertical, leaf(), leaf(100, 350)))
        let small = Rect(0, 30, 1200, 600)
        let next = try LayoutReflow.preservingSeams(root, reference: root, from: area, to: small, gap: gap)
        XCTAssertEqual(next, root)
        XCTAssertEqual(try LayoutEngine.calculate(next, in: small, gap: gap).regions.count, 4)
    }
    func testMiddleRowCanResizeIndependentlyInThreeRowGrid() throws {
        let root = split(.horizontal,
            split(.vertical, leaf(), split(.vertical, leaf(), leaf()), ratio: 0.33),
            split(.vertical, leaf(), split(.vertical, leaf(), leaf()), ratio: 0.33))
        let geometry = try LayoutEngine.calculate(root, in: area, gap: gap)
        let middle = geometry.regions.filter { $0.bounds.x == 0 }.sorted { $0.bounds.y < $1.bounds.y }[1].bounds
        let handles = try ResizeHandles.calculate(root, in: area, gap: gap)
        XCTAssertTrue(handles.contains { $0.divider.axis == .horizontal && $0.divider.bounds.y == middle.y && $0.divider.bounds.height == middle.height })
    }
    func testNoGripIsOfferedWhenNeitherNeighborCanResize() throws {
        let root = split(.horizontal, leaf(100, 100), leaf(100, 100))
        XCTAssertTrue(try ResizeHandles.calculate(root, in: Rect(0, 0, 210, 300), gap: gap).isEmpty)
    }
    func testShownMenuCorrectsStaleExpandedGeometryOnItsOwnDisplay() {
        XCTAssertEqual(DesktopWorkArea.correctingMenu(frame: area, visible: area, bars: [Rect(0, 0, 1200, 30)]), Rect(0, 30, 1200, 770))
        XCTAssertEqual(DesktopWorkArea.correctingMenu(frame: area, visible: area, bars: [Rect(1200, 0, 1200, 30)]), area)
        XCTAssertEqual(DesktopWorkArea.correctingMenu(frame: area, visible: area, bars: []), area)
    }
}
