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
        let local = try XCTUnwrap(ResizeHandles.hit(handles, at: Point(962, 399)))
        XCTAssertFalse(local.shared); XCTAssertEqual(local.divider.bounds.x, 724)
    }
    func testLocalVerticalEditKeepsHorizontalResizeAvailable() throws {
        let handles = try ResizeHandles.calculate(fixture(), in: area, gap: gap)
        let local = try XCTUnwrap(ResizeHandles.hit(handles, at: Point(962, 399)))
        let next = try InteractionGeometry.resize(Workspace(roots: ["screen": local.root]), display: "screen", divider: local.divider,
            pointer: Point(962, 340), area: area, gap: gap, grabbedAt: Point(962, 399))
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
    func testLocalGripPaddingAndUniversalRemainderOnBothAxes() throws {
        let root = split(.horizontal, split(.vertical, leaf(), leaf()), split(.vertical, leaf(), leaf()))
        let handles = try ResizeHandles.calculate(root, in: area, gap: gap)
        for axis in [Axis.horizontal, .vertical] {
            let universal = try XCTUnwrap(handles.first { $0.shared && $0.divider.axis == axis && ResizeHandles.isUniversal($0, among: handles) })
            for local in handles where ResizeHandles.contains(universal, local) {
                let d = local.divider.bounds
                let center = axis == .horizontal ? d.y + d.height / 2 : d.x + d.width / 2
                for offset in [-81, -80, 0, 80, 81] {
                    let point = axis == .horizontal ? Point(d.x + 1, center + offset) : Point(center + offset, d.y + 1)
                    let picked = try XCTUnwrap(ResizeHandles.hit(handles, at: point))
                    XCTAssertEqual(picked.divider, abs(offset) <= 80 ? local.divider : universal.divider)
                }
            }
            let d = universal.divider.bounds
            for point in [Point(d.x + 1, d.y + 1), Point(d.right - 1, d.bottom - 1)] {
                XCTAssertEqual(ResizeHandles.hit(handles, at: point)?.divider, universal.divider)
            }
        }
    }
    func testJoinCueOnlyTargetsFullUniversalSeams() throws {
        let handles = try ResizeHandles.calculate(fixture(), in: area, gap: gap)
        let previous = try ResizeHandles.calculate(split(.horizontal, leaf(), leaf()), in: area, gap: gap)
        let cues = ResizeHandles.newlyJoined(handles, previous: previous)
        XCTAssertFalse(cues.isEmpty)
        XCTAssertTrue(cues.allSatisfy { ResizeHandles.isUniversal($0, among: handles) })
        XCTAssertTrue(ResizeHandles.newlyJoined(handles, previous: handles).isEmpty)
        XCTAssertTrue(ResizeHandles.newlyJoined(handles, previous: []).isEmpty)
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
    func testNearbyRowsSnapAndRestorePerpendicularLocalHandles() throws {
        let root = split(.horizontal, split(.vertical, leaf(), leaf()),
                         split(.vertical, split(.horizontal, leaf(), leaf()), leaf(), ratio: 0.55))
        let before = try frames(root)
        let handles = try ResizeHandles.calculate(root, in: area, gap: gap)
        let local = try XCTUnwrap(handles.first { $0.divider.axis == .vertical && $0.divider.parent.x > 0 })
        let at = Point(1000, local.divider.bounds.y + 5)
        let next = try InteractionGeometry.resize(Workspace(roots: ["s": local.root]), display: "s", divider: local.divider,
            pointer: Point(1000, 404), area: area, gap: gap, grabbedAt: at)
        let joined = try XCTUnwrap(next.roots["s"])
        let after = try frames(joined)
        for (id, frame) in before where frame.x == 0 { XCTAssertEqual(after[id], frame) }
        XCTAssertEqual(Set(after.values.filter { $0.y > 0 }.map(\.y)), [405])
        let options = try ResizeHandles.calculate(joined, in: area, gap: gap)
        XCTAssertTrue(options.contains { $0.divider.axis == .horizontal && $0.divider.bounds.y == 405 })
        XCTAssertTrue(options.contains { $0.divider.axis == .vertical && $0.shared })
        // Same held gesture can pull away again; no sticky tree replacement.
        let separated = try InteractionGeometry.resize(Workspace(roots: ["s": local.root]), display: "s", divider: local.divider,
            pointer: Point(1000, 350), area: area, gap: gap, grabbedAt: at)
        XCTAssertNotEqual(try frames(XCTUnwrap(separated.roots["s"])), after)
    }
    func testNearbyColumnsSnapSymmetrically() throws {
        let root = split(.vertical, split(.horizontal, leaf(), leaf()), split(.horizontal, leaf(), leaf(), ratio: 0.506))
        let layout = try LayoutEngine.calculate(root, in: area, gap: gap)
        let local = try XCTUnwrap(layout.dividers.first { $0.axis == .horizontal && $0.parent.y > 0 })
        let joined = try InteractionGeometry.snappingSeam(root, divider: local.id, area: area, gap: gap)
        let seams = try LayoutEngine.calculate(joined, in: area, gap: gap).dividers.filter { $0.axis == .horizontal }
        XCTAssertEqual(Set(seams.map { $0.bounds.x }), [595])
        XCTAssertTrue(try ResizeHandles.calculate(joined, in: area, gap: gap).contains { $0.shared && $0.divider.axis == .horizontal })
    }
    func testSnapRespectsMinimumAndLeavesDistantSeamsAlone() throws {
        let root = split(.horizontal, split(.vertical, leaf(), leaf()), split(.vertical, leaf(100, 402), leaf()))
        let local = try XCTUnwrap(LayoutEngine.calculate(root, in: area, gap: gap).dividers.first { $0.axis == .vertical && $0.parent.x > 0 })
        XCTAssertEqual(try InteractionGeometry.snappingSeam(root, divider: local.id, area: area, gap: gap), root)
        let far = split(.horizontal, split(.vertical, leaf(), leaf()), split(.vertical, leaf(), leaf(), ratio: 0.7))
        let d = try XCTUnwrap(LayoutEngine.calculate(far, in: area, gap: gap).dividers.first { $0.axis == .vertical && $0.parent.x > 0 })
        XCTAssertEqual(try InteractionGeometry.snappingSeam(far, divider: d.id, area: area, gap: gap), far)
    }

    func testNativeWidthResizeChangesOnlyItsLocalRow() throws {
        let root = split(.horizontal, split(.vertical, leaf(), leaf()), split(.vertical, leaf(), leaf()))
        let before = try frames(root)
        let topLeft = try XCTUnwrap(before.first { $0.value.x == 0 && $0.value.y == 0 })
        let r = topLeft.value
        let changed = try InteractionGeometry.resizeWindow(root, windowID: topLeft.key,
            requested: Rect(r.x, r.y, r.width - 70, r.height), area: area, gap: gap)
        let after = try frames(changed)
        for (id, frame) in before where frame.y > 0 { XCTAssertEqual(after[id], frame) }
        XCTAssertEqual(after[topLeft.key]?.width, r.width - 70)
    }
    func testNativeHeightResizeChangesOnlyItsLocalColumn() throws {
        let root = split(.vertical, split(.horizontal, leaf(), leaf()), split(.horizontal, leaf(), leaf()))
        let before = try frames(root)
        let topLeft = try XCTUnwrap(before.first { $0.value.x == 0 && $0.value.y == 0 })
        let r = topLeft.value
        let changed = try InteractionGeometry.resizeWindow(root, windowID: topLeft.key,
            requested: Rect(r.x, r.y, r.width, r.height - 70), area: area, gap: gap)
        let after = try frames(changed)
        for (id, frame) in before where frame.x > 0 { XCTAssertEqual(after[id], frame) }
        XCTAssertEqual(after[topLeft.key]?.height, r.height - 70)
    }

    func testJoinedFirstTwoColumnsExposeSharedGripBesideFullHeightThirdColumn() throws {
        let root = split(.horizontal, split(.vertical, leaf(), leaf()),
                         split(.horizontal, split(.vertical, leaf(), leaf()), leaf()))
        let before = try frames(root)
        let handles = try ResizeHandles.calculate(root, in: area, gap: gap)
        let shared = try XCTUnwrap(handles.first { $0.shared && $0.divider.axis == .vertical && $0.divider.bounds.x == 0 })
        XCTAssertLessThan(shared.divider.bounds.right, area.right)
        XCTAssertEqual(try frames(shared.root), before)
        let d = shared.divider
        let next = try InteractionGeometry.resize(Workspace(roots: ["s": shared.root]), display: "s", divider: d,
            pointer: Point(d.bounds.x + d.bounds.width / 2, d.bounds.y - 35), area: area, gap: gap,
            grabbedAt: Point(d.bounds.x + d.bounds.width / 2, d.bounds.y))
        let after = try frames(XCTUnwrap(next.roots["s"]))
        for (id, frame) in before where frame.height == area.height { XCTAssertEqual(after[id], frame) }
        XCTAssertEqual(Set(after.values.filter { $0.height < area.height && $0.y == 0 }.map(\.bottom)).count, 1)
        XCTAssertEqual(ResizeHandles.hit(handles, at: Point(d.bounds.x + d.bounds.width / 2, d.bounds.y + 1))?.divider, d)
    }

    func testRemovingPlanningPreferencesPreservesExactFittedGeometry() throws {
        let root = split(.horizontal, leaf(700, 100), split(.vertical, leaf(100, 500), leaf()))
        let before = try frames(root)
        let measured = try LayoutEngine.measuredRatios(root, in: area, gap: gap)
        let unconstrained = root.windows.map { WindowLeaf(id: $0.id, windowID: $0.windowID, minimum: Size(100, 100)) }
        let committed = Workspace(roots: ["s": measured]).reconciled(with: unconstrained)
        XCTAssertEqual(try frames(XCTUnwrap(committed.roots["s"])), before)
    }

    func testCachePreservesHandlesAndInvalidatesEveryGeometryInput() throws {
        var cache = ResizeHandleCache()
        let root = fixture(), expected = try ResizeHandles.calculate(root, in: area, gap: gap)
        for _ in 0..<100 { XCTAssertEqual(try cache.handles(display: "a", root: root, area: area, gap: gap), expected) }
        XCTAssertEqual(cache.calculationCount, 1)
        _ = try cache.handles(display: "a", root: root, area: area, gap: gap + 2)
        _ = try cache.handles(display: "a", root: root, area: Rect(0, 30, 1200, 700), gap: gap)
        let changed = split(.horizontal, leaf(250, 200), leaf(300, 150))
        _ = try cache.handles(display: "a", root: changed, area: area, gap: gap)
        _ = try cache.handles(display: "b", root: root, area: area, gap: gap)
        XCTAssertEqual(cache.calculationCount, 5)
        var member = root.windows[0]; member.minimum = Size(180, 140)
        let newLimit = root.replacing(member.id, with: .window(member))
        let refreshed = try cache.handles(display: "b", root: newLimit, area: area, gap: gap)
        XCTAssertEqual(refreshed, try ResizeHandles.calculate(newLimit, in: area, gap: gap))
        XCTAssertEqual(cache.calculationCount, 6)
        XCTAssertEqual(cache.entryCount, 2)
        cache.retain(displays: ["b"]); XCTAssertEqual(cache.entryCount, 1)
        cache.removeAll(); XCTAssertEqual(cache.entryCount, 0)
    }
    func testGripInkSeparatesShortPillsWithoutChangingLargerHitTargets() {
        let segments = GripInk.segments(span: 800, localCenters: [200, 600])
        XCTAssertEqual(segments, [4.0...152.0, 248.0...552.0, 648.0...796.0, 160.0...240.0, 560.0...640.0])
        XCTAssertEqual(GripInk.segments(span: 800, localCenters: []), [4.0...796.0])
        XCTAssertEqual(ResizeHandles.localHitRadius, 80)
        XCTAssertTrue(GripInk.segments(span: 6, localCenters: [3]).isEmpty)
        XCTAssertEqual(GripInk.joinOpacity(elapsed: 0), 1)
        XCTAssertEqual(GripInk.joinOpacity(elapsed: 0.15), 1)
        XCTAssertEqual(GripInk.joinOpacity(elapsed: 0.55), 0)
    }
    func testRepeatedGeometryBenchmark() throws {
        let root = fixture(), iterations = 250
        let start = Date()
        var uncached: [ResizeHandle] = []
        for _ in 0..<iterations { uncached = try ResizeHandles.calculate(root, in: area, gap: gap) }
        let uncachedMS = Date().timeIntervalSince(start) * 1000
        var cache = ResizeHandleCache(), cached: [ResizeHandle] = []
        let cachedStart = Date()
        for _ in 0..<iterations { cached = try cache.handles(display: "a", root: root, area: area, gap: gap) }
        let cachedMS = Date().timeIntervalSince(cachedStart) * 1000
        XCTAssertEqual(cached, uncached); XCTAssertEqual(cache.calculationCount, 1)
        print("Grip geometry benchmark: \(iterations) unchanged requests, uncached=\(uncachedMS)ms cached=\(cachedMS)ms; identical handles")
    }

    func testMovingAnExistingJoinedGripDoesNotReplaySnapCue() throws {
        let root = fixture(), handles = try ResizeHandles.calculate(root, in: area, gap: gap)
        let handle = try XCTUnwrap(handles.first { $0.shared && ResizeHandles.isUniversal($0, among: handles) })
        let d = handle.divider.bounds
        let start = Point(d.x + d.width / 2, d.y + d.height / 2)
        let moved = handle.divider.axis == .horizontal ? Point(start.x + 20, start.y) : Point(start.x, start.y + 20)
        let next = try InteractionGeometry.resize(Workspace(roots: ["a": handle.root]), display: "a", divider: handle.divider,
            pointer: moved, area: area, gap: gap, grabbedAt: start)
        let updated = try ResizeHandles.calculate(XCTUnwrap(next.roots["a"]), in: area, gap: gap)
        XCTAssertFalse(ResizeHandles.newlyJoined(updated, previous: handles).contains { $0.divider.id == handle.divider.id })
    }

}
