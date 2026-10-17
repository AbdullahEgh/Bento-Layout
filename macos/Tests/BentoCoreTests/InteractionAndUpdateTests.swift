import XCTest
import CryptoKit
@testable import BentoCore

final class InteractionAndUpdateTests: XCTestCase {
    func testStatusHoldConsumesReleaseAndFiresOnce() {
        var press = StatusPress()
        press.begin(at: 1)
        XCTAssertFalse(press.hold(at: 1.3))
        XCTAssertTrue(press.end())
        press.begin(at: 2)
        XCTAssertTrue(press.hold(at: 2.6))
        XCTAssertFalse(press.hold(at: 3))
        XCTAssertFalse(press.end())
        press.begin(at: 4); press.cancel()
        XCTAssertFalse(press.end())
    }
    func testNativeSeamReclaimsRoundedStripWithoutChangingMembership() throws {
        let a = WindowLeaf(windowID: UUID(), minimum: Size(160, 120))
        let b = WindowLeaf(windowID: UUID(), minimum: Size(160, 120))
        for axis in [Axis.horizontal, .vertical] {
            let root = LayoutNode.split(id: UUID(), axis: axis, ratio: 0.5, first: .window(a), second: .window(b))
            let area = Rect(0, 0, 1208, 908)
            let regions = try LayoutEngine.calculate(root, in: area, gap: 8).regions
            for rounded in [a.windowID, b.windowID] {
                var frames = Dictionary(uniqueKeysWithValues: regions.map { ($0.window.windowID, $0.bounds) })
                if axis == .horizontal { frames[rounded]!.width -= 14 } else { frames[rounded]!.height -= 14 }
                XCTAssertNil(NativeSeamAlignment.proposal(root, area: area, gap: 8, frames: frames, affectedWindows: []),
                    "A manual edit must not repair an unrelated divider")
                let aligned = try XCTUnwrap(NativeSeamAlignment.proposal(root, area: area, gap: 8, frames: frames))
                let result = try LayoutEngine.calculate(aligned, in: area, gap: 8)
                XCTAssertEqual(aligned.windows.map(\.windowID), root.windows.map(\.windowID))
                let target = try XCTUnwrap(result.regions.first { $0.window.windowID == rounded })
                XCTAssertEqual(axis == .horizontal ? target.bounds.width : target.bounds.height,
                    axis == .horizontal ? frames[rounded]!.width : frames[rounded]!.height)
                let exact = Dictionary(uniqueKeysWithValues: result.regions.map { ($0.window.windowID, $0.bounds) })
                XCTAssertNil(NativeSeamAlignment.proposal(aligned, area: area, gap: 8, frames: exact))
            }
        }
    }

    func testDesktopWorkAreaReclaimsHiddenMenuAndDockWithoutUsingCameraArea() {
        let frame = Rect(-1440, -900, 1440, 900), visible = Rect(-1440, -870, 1440, 823)
        XCTAssertEqual(DesktopWorkArea.calculate(frame: frame, visible: visible, hideMenuBar: true, hideDock: false, margin: 8), Rect(-1432, -892, 1424, 837))
        XCTAssertEqual(DesktopWorkArea.calculate(frame: frame, visible: visible, hideMenuBar: true, hideDock: true, margin: 8), frame.inset(8))
        XCTAssertEqual(DesktopWorkArea.calculate(frame: frame, visible: visible, hideMenuBar: true, hideDock: true, safeTop: 38).y, -862)
        let leftDock = Rect(-1370, -870, 1370, 870)
        XCTAssertEqual(DesktopWorkArea.calculate(frame: frame, visible: leftDock, hideMenuBar: false, hideDock: true), Rect(-1440, -870, 1440, 870))
        XCTAssertEqual(DesktopWorkArea.calculate(frame: frame, visible: visible, hideMenuBar: false, hideDock: false), visible)
        let largerDock = Rect(-1440, -870, 1440, 770)
        XCTAssertEqual(DesktopWorkArea.calculate(frame: frame, visible: largerDock, hideMenuBar: false, hideDock: false), largerDock)
    }
    func testPhysicalEdgeMovesWholeSectionWhenLeafSwapCannotFit() throws {
        for direction in [Placement.left, .right, .top, .bottom] {
            let horizontal = direction == .left || direction == .right
            let firstEdge = direction == .left || direction == .top
            let big = leaf(horizontal ? 650 : 1400, horizontal ? 1400 : 650), a = leaf(), b = leaf()
            let stack = LayoutNode.split(id: UUID(), axis: horizontal ? .vertical : .horizontal, ratio: 0.4, first: .window(a), second: .window(b))
            let screen = Rect(-1800, -300, 1600, 1600), area = screen.inset(40)
            let root = LayoutNode.split(id: UUID(), axis: horizontal ? .horizontal : .vertical, ratio: firstEdge ? 0.3 : 0.7,
                first: firstEdge ? stack : .window(big), second: firstEdge ? .window(big) : stack)
            let state = Workspace(roots: ["A": root]), before = try LayoutEngine.calculate(root, in: area)
            let target = before.regions.first { $0.window.windowID == a.windowID }!.bounds
            var leafSwap = DropSession(workspace: state, source: big)
            XCTAssertNil(try leafSwap.propose(pointer: Point(target.x + target.width / 2, target.y + target.height / 2), areas: ["A": area], gap: 8, hold: 900, now: 0))
            let point: Point
            switch direction {
            case .left: point = Point(screen.x, screen.y + 800)
            case .right: point = Point(screen.right - 1, screen.y + 800)
            case .top: point = Point(screen.x + 800, screen.y)
            default: point = Point(screen.x + 800, screen.bottom - 1)
            }
            var session = DropSession(workspace: state, source: big)
            let proposal = try XCTUnwrap(session.propose(pointer: point, areas: ["A": area], gap: 8, hold: 900, now: 0, screenBounds: ["A": screen]))
            XCTAssertTrue(proposal.swapsSections); XCTAssertFalse(proposal.waitingForSplit)
            let after = try LayoutEngine.calculate(proposal.workspace.roots["A"], in: area)
            XCTAssertEqual(proposal.neighbors.count, 2)
            for region in before.regions {
                let moved = try XCTUnwrap(after.regions.first { $0.window == region.window })
                XCTAssertEqual(moved.bounds.width, region.bounds.width)
                XCTAssertEqual(moved.bounds.height, region.bounds.height)
            }
            XCTAssertEqual(proposal.workspace.roots["A"]?.id, root.id)
            XCTAssertEqual(proposal.workspace.roots["A"]?.windows.count, 3)
            for time in 1...200 {
                XCTAssertEqual(try session.propose(pointer: point, areas: ["A": area], gap: 8, hold: 900, now: Double(time), screenBounds: ["A": screen]), proposal)
            }
            XCTAssertEqual(session.geometryBuildCount, 1)
            // Leaving the physical edge clears section intent, even in the margin.
            XCTAssertNil(try session.propose(pointer: Point(screen.x + 25, screen.y + 25), areas: ["A": area], gap: 8, hold: 900, now: 201, screenBounds: ["A": screen]))
        }
    }
    func testSectionMovePreservesClampedWidthsAndSkipsAlreadyOutermostSection() throws {
        let large = leaf(1000, 150), a = leaf(), b = leaf()
        let stack = LayoutNode.split(id: UUID(), axis: .vertical, ratio: 0.4, first: .window(a), second: .window(b))
        let root = LayoutNode.split(id: UUID(), axis: .horizontal, ratio: 0.9, first: stack, second: .window(large))
        let state = Workspace(roots: ["A": root])
        let moved = try XCTUnwrap(InteractionGeometry.moveSection(state, source: large.windowID, display: "A", toward: .left, area: area, gap: 8))
        let before = try LayoutEngine.calculate(root, in: area), after = try LayoutEngine.calculate(moved.roots["A"], in: area)
        XCTAssertEqual(before.regions.first { $0.window == large }?.bounds.width, after.regions.first { $0.window == large }?.bounds.width)
        XCTAssertNil(try InteractionGeometry.moveSection(moved, source: large.windowID, display: "A", toward: .left, area: area, gap: 8))
        XCTAssertNil(try InteractionGeometry.moveSection(state, source: leaf().windowID, display: "A", toward: .left, area: area, gap: 8))
        let restored = try XCTUnwrap(InteractionGeometry.moveSection(moved, source: large.windowID, display: "A", toward: .right, area: area, gap: 8))
        XCTAssertEqual(try LayoutEngine.calculate(restored.roots["A"], in: area).regions, before.regions)
    }
    func testSectionMovementCarriesSourceGroupAndDoesNotActivateOnAnotherDisplay() throws {
        let a = leaf(), b = leaf(), c = leaf(), d = leaf()
        let group = LayoutNode.split(id: UUID(), axis: .vertical, ratio: 0.3, first: .window(a), second: .window(b))
        let root = LayoutNode.split(id: UUID(), axis: .horizontal, ratio: 0.4, first: .window(c), second: group)
        let state = Workspace(roots: ["A": root, "B": .window(d)])
        let moved = try XCTUnwrap(InteractionGeometry.moveSection(state, source: a.windowID, display: "A", toward: .left, area: area, gap: 8))
        guard case .split(_, _, _, let first, _) = moved.roots["A"] else { return XCTFail("Expected split") }
        XCTAssertEqual(first, group); XCTAssertEqual(moved.roots["B"], .window(d))
        var session = DropSession(workspace: state, source: a)
        let proposal = try session.propose(pointer: Point(1600, 500), areas: ["A": area, "B": Rect(1600, 0, 1600, 1000)], gap: 8, hold: 900, now: 0,
                                           screenBounds: ["A": area, "B": Rect(1600, 0, 1600, 1000)])
        XCTAssertFalse(proposal?.swapsSections ?? false)
    }
    func testResumeRetainsDisplaySlotIdentityAndRatioWithoutAdmittingFloatingWindows() throws {
        let a = leaf(), b = leaf(), c = leaf(), floating = leaf()
        let branch = UUID()
        let state = Workspace(roots: ["left": .window(a), "right": .split(id: branch, axis: .horizontal, ratio: 0.37, first: .window(b), second: .window(c))])
        XCTAssertEqual(state.reconciled(with: [c, floating, a, b]), state)
        let closed = state.reconciled(with: [a, c, floating])
        XCTAssertEqual(closed.roots["left"], .window(a))
        XCTAssertEqual(closed.roots["right"], .window(c))
        XCTAssertFalse(closed.windows.contains { $0.windowID == floating.windowID })
        var constrained = b; constrained.minimum.width = 680
        let refreshed = state.reconciled(with: [a, constrained, c])
        let regions = try LayoutEngine.calculate(refreshed.roots["right"], in: Rect(1200, 0, 1000, 800)).regions
        XCTAssertEqual(refreshed.roots["right"]?.id, branch)
        XCTAssertEqual(regions[0].window.id, b.id)
        XCTAssertEqual(regions[0].bounds.width, 680)
        XCTAssertEqual(regions[1].window.id, c.id)
    }
    func testFloatingCenterDropInsertsWithoutDisplacingAndEmptyDisplayAcceptsDrop() throws {
        for area in [Rect(0, 0, 1200, 800), Rect(0, 0, 800, 1200)] {
            let a = leaf(), incoming = leaf()
            let state = Workspace(roots: ["A": .window(a)])
            var session = DropSession(workspace: state, source: incoming)
            let proposal = try XCTUnwrap(session.propose(pointer: Point(area.width / 2, area.height / 2), areas: ["A": area], gap: 8, hold: 900, now: 0))
            XCTAssertEqual(proposal.placement, area.width >= area.height ? .right : .bottom)
            XCTAssertEqual(Set(proposal.workspace.windows.map(\.windowID)), [a.windowID, incoming.windowID])
            XCTAssertFalse(proposal.waitingForSplit)
            XCTAssertEqual(proposal.bounds, try LayoutEngine.calculate(proposal.workspace.roots["A"], in: area).regions.first { $0.window.windowID == incoming.windowID }?.bounds)
        }
        let a = leaf(), empty = Rect(1200, 0, 1000, 800)
        var session = DropSession(workspace: Workspace(roots: ["A": .window(a)]), source: a)
        let moved = try XCTUnwrap(session.propose(pointer: Point(1500, 400), areas: ["A": Rect(0, 0, 1200, 800), "B": empty], gap: 8, hold: 900, now: 0))
        XCTAssertNil(moved.workspace.roots["A"])
        XCTAssertEqual(moved.workspace.roots["B"], .window(a))
        XCTAssertEqual(moved.bounds, empty)
    }
    func testImpossibleDropShowsConflictWithoutChangingWorkspace() throws {
        let a = leaf(900, 100), b = leaf(200, 100), area = Rect(0, 0, 1000, 500)
        let state = Workspace(roots: ["A": .split(id: UUID(), axis: .vertical, ratio: 0.5, first: .window(a), second: .window(b))])
        let target = try LayoutEngine.calculate(state.roots["A"], in: area).regions[1].bounds
        var session = DropSession(workspace: state, source: a)
        XCTAssertNil(try session.propose(pointer: Point(target.x + 2, target.y + target.height / 2), areas: ["A": area], gap: 8, hold: 0, now: 0))
        XCTAssertEqual(session.conflictBounds, target)
        XCTAssertEqual(session.original, state)
        _ = try session.propose(pointer: Point(-50, -50), areas: ["A": area], gap: 8, hold: 0, now: 1)
        XCTAssertNil(session.conflictBounds)
    }
    func testSplitPreviewIsStableAcrossRepeatedSamplesInEveryDirection() throws {
        let a = leaf(), b = leaf(), c = leaf()
        let state = Workspace(roots: ["A": try AutoLayout.arrange([a, b, c], in: area)!])
        let target = try LayoutEngine.calculate(state.roots["A"], in: area).regions[1].bounds
        let points: [(Placement, Point)] = [(.left, Point(target.x + 2, target.y + target.height / 2)),
            (.right, Point(target.right - 2, target.y + target.height / 2)),
            (.top, Point(target.x + target.width / 2, target.y + 2)),
            (.bottom, Point(target.x + target.width / 2, target.bottom - 2))]
        for (placement, point) in points {
            var session = DropSession(workspace: state, source: a)
            let first = try XCTUnwrap(session.propose(pointer: point, areas: ["A": area], gap: 8, hold: 0, now: 0))
            XCTAssertEqual(first.placement, placement)
            for sample in 1...250 {
                let next = try XCTUnwrap(session.propose(pointer: point, areas: ["A": area], gap: 8, hold: 0, now: Double(sample) / 45))
                XCTAssertEqual(next, first, "A stationary split preview must keep its exact tree and slot identities")
            }
            XCTAssertEqual(session.geometryBuildCount, 1)
            XCTAssertEqual(first.workspace.windows.count, 3)
            XCTAssertEqual(session.original, state)
        }
    }
    func testSplitCacheInvalidatesForWorkAreaAndGapAndMemoizesConflict() throws {
        let a = leaf(), b = leaf()
        let state = Workspace(roots: ["A": try AutoLayout.arrange([a, b], in: area)!])
        let target = try LayoutEngine.calculate(state.roots["A"], in: area).regions[1].bounds
        var session = DropSession(workspace: state, source: a)
        let pointer = Point(target.x + 32, target.y + target.height / 2)
        let before = try XCTUnwrap(session.propose(pointer: pointer, areas: ["A": area], gap: 8, hold: 0, now: 0))
        let after = try XCTUnwrap(session.propose(pointer: pointer, areas: ["A": area], gap: 16, hold: 0, now: 1))
        XCTAssertNotEqual(before.workspace, after.workspace)
        XCTAssertEqual(session.geometryBuildCount, 2)
        let resizedArea = Rect(area.x, area.y, area.width - 80, area.height - 40)
        let resized = try XCTUnwrap(session.propose(pointer: pointer, areas: ["A": resizedArea], gap: 16, hold: 0, now: 2))
        XCTAssertNotEqual(resized.bounds, after.bounds)
        XCTAssertEqual(session.geometryBuildCount, 3)
        let large = leaf(900, 100), small = leaf(200, 100), narrow = Rect(0, 0, 1000, 500)
        let impossible = Workspace(roots: ["A": .split(id: UUID(), axis: .vertical, ratio: 0.5, first: .window(large), second: .window(small))])
        var failed = DropSession(workspace: impossible, source: large)
        for sample in 0..<250 {
            XCTAssertNil(try failed.propose(pointer: Point(2, 400), areas: ["A": narrow], gap: 8, hold: 0, now: Double(sample)))
            XCTAssertNotNil(failed.conflictBounds)
        }
        XCTAssertEqual(failed.geometryBuildCount, 1)
    }
    func testMotionAcceleratesAndSettlesGentlyWithoutOvershoot() {
        let start = Rect(0, 0, 100, 100), end = Rect(1000, 1000, 1100, 1100)
        XCTAssertLessThan(WindowMotion.frame(from: start, to: end, progress: 0.1).x, 20)
        XCTAssertEqual(WindowMotion.frame(from: start, to: end, progress: 0.5).x, 500)
        XCTAssertGreaterThan(WindowMotion.frame(from: start, to: end, progress: 0.9).x, 980)
        for i in 0...100 { XCTAssertTrue((0...1000).contains(WindowMotion.frame(from: start, to: end, progress: Double(i) / 100).x)) }
    }
    func testMotionEndpointsAndMonotonicity() {
        let a = Rect(-200, 30, 800, 400), b = Rect(30, -200, 400, 800)
        XCTAssertEqual(WindowMotion.frame(from: a, to: b, progress: 0), a)
        XCTAssertEqual(WindowMotion.frame(from: a, to: b, progress: 1), b)
        var previous = a
        for i in 1...100 {
            let current = WindowMotion.frame(from: a, to: b, progress: Double(i) / 100)
            XCTAssertGreaterThanOrEqual(current.x, previous.x)
            XCTAssertLessThanOrEqual(current.width, previous.width)
            XCTAssertGreaterThanOrEqual(current.width, b.width)
            previous = current
        }
    }
    func testDockReopenGetsSpaceBeforeExistingWindows() throws {
        let big = leaf(700, 700), small = leaf(300, 300), other = leaf(300, 300)
        let area = Rect(0, 0, 900, 800)
        let old = try AutoLayout.arrange([small, other], in: area)
        let next = try AutoLayout.fitting([small, other, big], in: area, preserving: old, prioritizing: [big.windowID])
        XCTAssertEqual(next?.windows.map(\.windowID), [big.windowID])
        _ = try LayoutEngine.calculate(next, in: area)
    }
    private let area = Rect(0, 0, 1600, 1000)
    private func leaf(_ width: Int = 200, _ height: Int = 150) -> WindowLeaf { WindowLeaf(windowID: UUID(), minimum: Size(width, height)) }
    private func fixture() throws -> Workspace { Workspace(roots: ["A": try AutoLayout.arrange([leaf(), leaf(), leaf()], in: area)!]) }
    func testNativeDropQuickSwapAndTimedSplit() throws {
        let state = try fixture(), regions = try LayoutEngine.calculate(state.roots["A"], in: area).regions
        var session = DropSession(workspace: state, source: regions[0].window)
        let target = regions[1], point = Point(target.bounds.x + 5, target.bounds.y + target.bounds.height / 2)
        let quick = try XCTUnwrap(session.propose(pointer: point, areas: ["A": area], gap: 8, hold: 900, now: 0))
        XCTAssertEqual(quick.placement, .center); XCTAssertEqual(quick.bounds, target.bounds)
        let armed = try XCTUnwrap(session.propose(pointer: point, areas: ["A": area], gap: 8, hold: 900, now: 0.901))
        XCTAssertEqual(armed.placement, .left)
        XCTAssertEqual(armed.workspace.windows.count, 3)
        XCTAssertEqual(Set(armed.workspace.windows.map(\.windowID)), Set(state.windows.map(\.windowID)))
        XCTAssertEqual(armed.bounds, try LayoutEngine.calculate(armed.workspace.roots["A"], in: area).regions.first { $0.window.windowID == regions[0].window.windowID }?.bounds)
        XCTAssertEqual(try LayoutEngine.calculate(state.roots["A"], in: area).regions, regions)
    }
    func testPreviewMatchesFinalSlotsAfterSourceRemovalAndMinimumClamping() throws {
        for placement in [Placement.left, .right, .top, .bottom, .center] {
            let a = leaf(900, 550), b = leaf(200, 150)
            let state = Workspace(roots: ["A": .split(id: UUID(), axis: .horizontal, ratio: 0.65, first: .window(a), second: .window(b))])
            let target = try LayoutEngine.calculate(state.roots["A"], in: area).regions[1].bounds
            let point: Point
            switch placement {
            case .left: point = Point(target.x + 3, target.y + target.height / 2)
            case .right: point = Point(target.right - 3, target.y + target.height / 2)
            case .top: point = Point(target.x + target.width / 2, target.y + 3)
            case .bottom: point = Point(target.x + target.width / 2, target.bottom - 3)
            case .center: point = Point(target.x + target.width / 2, target.y + target.height / 2)
            }
            var session = DropSession(workspace: state, source: a)
            let proposal = try XCTUnwrap(session.propose(pointer: point, areas: ["A": area], gap: 8, hold: 0, now: 0))
            let final = try LayoutEngine.calculate(proposal.workspace.roots["A"], in: area).regions
            XCTAssertEqual(proposal.placement, placement)
            XCTAssertEqual(proposal.bounds, final.first { $0.window.windowID == a.windowID }?.bounds)
            XCTAssertEqual(proposal.neighbors, final.filter { $0.window.windowID == b.windowID }.map(\.bounds))
            XCTAssertGreaterThanOrEqual(proposal.bounds.width, 900)
            XCTAssertGreaterThanOrEqual(proposal.bounds.height, 550)
        }
    }
    func testHoldIndicatorResetsWhenPointerMovesToCenter() throws {
        let state = try fixture(), regions = try LayoutEngine.calculate(state.roots["A"], in: area).regions
        var session = DropSession(workspace: state, source: regions[0].window)
        let r = regions[1].bounds, edge = Point(r.x + 3, r.y + r.height / 2)
        let start = try XCTUnwrap(session.propose(pointer: edge, areas: ["A": area], gap: 8, hold: 900, now: 0))
        XCTAssertTrue(start.waitingForSplit)
        let half = try XCTUnwrap(session.propose(pointer: edge, areas: ["A": area], gap: 8, hold: 900, now: 0.45))
        XCTAssertEqual(half.progress, 0.5, accuracy: 0.001)
        let center = try XCTUnwrap(session.propose(pointer: Point(r.x + r.width / 2, r.y + r.height / 2), areas: ["A": area], gap: 8, hold: 900, now: 0.5))
        XCTAssertFalse(center.waitingForSplit); XCTAssertEqual(center.progress, 0)
    }
    func testLeavingTargetResetsHoldAndOutsideDropCancels() throws {
        let state = try fixture(), regions = try LayoutEngine.calculate(state.roots["A"], in: area).regions
        var session = DropSession(workspace: state, source: regions[0].window)
        let r = regions[1].bounds, point = Point(r.x + 3, r.y + r.height / 2)
        _ = try session.propose(pointer: point, areas: ["A": area], gap: 8, hold: 900, now: 0)
        XCTAssertNil(try session.propose(pointer: Point(-1, -1), areas: ["A": area], gap: 8, hold: 900, now: 1))
        XCTAssertEqual(try session.propose(pointer: point, areas: ["A": area], gap: 8, hold: 900, now: 2)?.placement, .center)
    }
    func testInfeasibleTargetIsNotOffered() throws {
        let a = leaf(500, 400), b = leaf(500, 400), bounds = Rect(0, 0, 1100, 500)
        let state = Workspace(roots: ["A": .window(a), "B": .window(b)])
        var session = DropSession(workspace: state, source: b)
        let result = try session.propose(pointer: Point(550, 3), areas: ["A": bounds, "B": Rect(1200, 0, 1100, 500)], gap: 8, hold: 0, now: 0)
        XCTAssertNil(result)
    }
    func testGripClampsAndDoesNotMutateSnapshot() throws {
        let a = leaf(400), b = leaf(300), root = LayoutNode.split(id: UUID(), axis: .horizontal, ratio: 0.5, first: .window(a), second: .window(b))
        let state = Workspace(roots: ["A": root]), divider = try LayoutEngine.calculate(root, in: area).dividers[0]
        let next = try InteractionGeometry.resize(state, display: "A", divider: divider, pointer: Point(-200, 0), area: area, gap: 8)
        let regions = try LayoutEngine.calculate(next.roots["A"], in: area).regions
        XCTAssertEqual(regions[0].bounds.width, 400)
        XCTAssertEqual(state.roots["A"], root)
        XCTAssertThrowsError(try InteractionGeometry.resize(state, display: "missing", divider: divider, pointer: Point(500, 0), area: area, gap: 8))
    }
    func testOffCenterGripKeepsAnchorAcrossBothAxesAndOddGaps() throws {
        for axis in [Axis.horizontal, .vertical] {
            for gap in [7, 8] {
                let root = LayoutNode.split(id: UUID(), axis: axis, ratio: 0.5, first: .window(leaf()), second: .window(leaf()))
                let state = Workspace(roots: ["A": root])
                let divider = try LayoutEngine.calculate(root, in: area, gap: gap).dividers[0]
                let start = Point(divider.bounds.x + 1, divider.bounds.y + 1)
                XCTAssertEqual(try InteractionGeometry.resize(state, display: "A", divider: divider, pointer: start, area: area, gap: gap, grabbedAt: start), state)
                let moved = try InteractionGeometry.resize(state, display: "A", divider: divider, pointer: Point(start.x + 37, start.y + 37), area: area, gap: gap, grabbedAt: start)
                let after = try LayoutEngine.calculate(moved.roots["A"], in: area, gap: gap).dividers[0]
                XCTAssertEqual(axis == .horizontal ? after.bounds.x - divider.bounds.x : after.bounds.y - divider.bounds.y, 37)
                let limited = try InteractionGeometry.resize(state, display: "A", divider: divider, pointer: Point(-10000, -10000), area: area, gap: gap, grabbedAt: start)
                let first = try LayoutEngine.calculate(limited.roots["A"], in: area, gap: gap).regions[0]
                XCTAssertEqual(axis == .horizontal ? first.bounds.width : first.bounds.height, axis == .horizontal ? 200 : 150)
            }
        }
    }
    func testNativeBorderChangesAncestorAndNeighbor() throws {
        let a = leaf(), b = leaf(), root = LayoutNode.split(id: UUID(), axis: .horizontal, ratio: 0.5, first: .window(a), second: .window(b))
        let before = try LayoutEngine.calculate(root, in: area).regions
        var requested = before[0].bounds; requested.width += 150
        let next = try InteractionGeometry.resizeWindow(root, windowID: a.windowID, requested: requested, area: area, gap: 8)
        let after = try LayoutEngine.calculate(next, in: area).regions
        XCTAssertEqual(after[0].bounds.width, before[0].bounds.width + 150)
        XCTAssertEqual(after[1].bounds.width, before[1].bounds.width - 150)
        XCTAssertEqual(after[0].bounds.right + 8, after[1].bounds.x)
    }
    func testSignedOTAConfigurationRejectsUnsafeSources() throws {
        let key = Data(repeating: 7, count: 32).base64EncodedString()
        XCTAssertNoThrow(try UpdateConfiguration.validate(feed: UpdateConfiguration.feed, publicKey: key, developmentBuild: false))
        XCTAssertThrowsError(try UpdateConfiguration.validate(feed: UpdateConfiguration.feed, publicKey: key, developmentBuild: true))
        XCTAssertThrowsError(try UpdateConfiguration.validate(feed: URL(string: "http://raw.githubusercontent.com/AbdullahEgh/Bento-Layout/macos-updates/appcast.xml"), publicKey: key, developmentBuild: false))
        XCTAssertThrowsError(try UpdateConfiguration.validate(feed: URL(string: "https://example.org/appcast.xml"), publicKey: key, developmentBuild: false))
        XCTAssertThrowsError(try UpdateConfiguration.validate(feed: UpdateConfiguration.feed, publicKey: "missing", developmentBuild: false))
    }
    func testOfficialSparkleArchiveSignatureAndCorruptionRejection() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let signer = root.appendingPathComponent(".build/artifacts/macos/Sparkle/bin/sign_update")
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let key = Curve25519.Signing.PrivateKey(), bytes = Data("Disposable OTA fixture".utf8)
        let keyURL = directory.appendingPathComponent("fixture.key"), archive = directory.appendingPathComponent("fixture.zip")
        // Sparkle's current export format is the 32-byte Ed25519 seed, base64 encoded.
        try key.rawRepresentation.base64EncodedData().write(to: keyURL, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: keyURL.path)
        try bytes.write(to: archive)
        let process = Process(), output = Pipe(), diagnostic = Pipe()
        process.executableURL = signer; process.arguments = ["--ed-key-file", keyURL.path, "-p", archive.path]; process.standardOutput = output; process.standardError = diagnostic
        try process.run(); process.waitUntilExit()
        let errorText = String(data: diagnostic.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let signatureText = String(data: output.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)!.trimmingCharacters(in: .whitespacesAndNewlines)
        let sanitized = (errorText + signatureText).replacingOccurrences(of: "[A-Za-z0-9+/]{40,}={0,2}", with: "<redacted>", options: .regularExpression)
        XCTAssertEqual(process.terminationStatus, 0, sanitized)
        guard process.terminationStatus == 0 else { return }
        let signature = try XCTUnwrap(Data(base64Encoded: signatureText))
        XCTAssertTrue(key.publicKey.isValidSignature(signature, for: bytes))
        XCTAssertFalse(key.publicKey.isValidSignature(signature, for: bytes + Data([0])))
    }
}

final class ActivationOverrideTests: XCTestCase {
    final class Backend: PreferenceBackend {
        var values: [PreferenceKey: Data] = [:], fail: PreferenceKey?, refreshFails = false
        var refreshCount = 0
        func read(_ key: PreferenceKey) -> Data? { values[key] }
        func write(_ key: PreferenceKey, value: Data?) throws {
            if fail == key { throw CocoaError(.fileWriteUnknown) }; values[key] = value
        }
        func refresh(_ keys: [PreferenceKey]) throws { refreshCount += 1; if refreshFails { throw CocoaError(.fileWriteUnknown) } }
    }
    private func temporaryJournal() -> URL { FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathComponent("session.json") }
    func testLiveToggleRestoresOnlyItsOwnKeyAndKeepsOriginalBaseline() throws {
        let backend = Backend(), url = temporaryJournal(), dock = PreferenceKey("dock", "autohide"), menu = PreferenceKey("global", "menu")
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let off = try ActivationOverrides.boolean(false), on = try ActivationOverrides.boolean(true)
        backend.values[menu] = off
        let manager = ActivationOverrides(backend: backend, journal: url)
        try manager.activate([dock: on, menu: on])
        let refreshes = backend.refreshCount
        try manager.update([dock: on, menu: on]); XCTAssertEqual(backend.refreshCount, refreshes)
        try manager.update([menu: on]); XCTAssertNil(backend.values[dock]); XCTAssertEqual(backend.values[menu], on)
        try manager.update([dock: on]); XCTAssertEqual(backend.values[menu], off); XCTAssertEqual(backend.values[dock], on)
        try manager.update([:]); XCTAssertNil(backend.values[dock]); XCTAssertEqual(backend.values[menu], off)
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
        try manager.update([dock: on]); try manager.restore(); XCTAssertNil(backend.values[dock])
    }
    func testLiveValueChangeKeepsFirstOriginalAndRespectsManualChange() throws {
        let backend = Backend(), url = temporaryJournal(), key = PreferenceKey("tiling", "edge")
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let off = try ActivationOverrides.boolean(false), on = try ActivationOverrides.boolean(true)
        let manager = ActivationOverrides(backend: backend, journal: url)
        try manager.activate([key: on]); try manager.update([key: off]); try manager.restore()
        XCTAssertNil(backend.values[key])
        try manager.activate([key: on]); backend.values[key] = off
        let refreshes = backend.refreshCount
        try manager.update([key: on]); XCTAssertEqual(backend.values[key], off); XCTAssertEqual(backend.refreshCount, refreshes)
        try manager.update([:]); XCTAssertEqual(backend.values[key], off)
    }
    func testLiveRefreshFailureKeepsRecoverableOriginalValues() throws {
        let backend = Backend(), url = temporaryJournal(), dock = PreferenceKey("dock", "hide"), menu = PreferenceKey("global", "menu")
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let off = try ActivationOverrides.boolean(false), on = try ActivationOverrides.boolean(true)
        backend.values[menu] = off
        let manager = ActivationOverrides(backend: backend, journal: url)
        try manager.activate([dock: on]); backend.refreshFails = true
        XCTAssertThrowsError(try manager.update([menu: on]))
        XCTAssertNil(backend.values[dock]); XCTAssertEqual(backend.values[menu], off)
        backend.refreshFails = false; try manager.restore()
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
    }
    func testInterruptedLiveValueChangeRestoresEitherOwnedValue() throws {
        let backend = Backend(), url = temporaryJournal(), key = PreferenceKey("tiling", "edge")
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let off = try ActivationOverrides.boolean(false), on = try ActivationOverrides.boolean(true)
        let entry = PreferenceChange(key: key, original: nil, applied: off, previouslyApplied: on)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        for interruptedValue in [on, off] {
            try JSONEncoder().encode([entry]).write(to: url)
            backend.values[key] = interruptedValue
            try ActivationOverrides(backend: backend, journal: url).restore()
            XCTAssertNil(backend.values[key])
        }
    }
    func testExactRestorationAndAbsentKeyDeletion() throws {
        let backend = Backend(), url = temporaryJournal(), dock = PreferenceKey("dock", "autohide"), menu = PreferenceKey("global", "menu")
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let before = try ActivationOverrides.boolean(false), after = try ActivationOverrides.boolean(true)
        backend.values[dock] = before
        let manager = ActivationOverrides(backend: backend, journal: url)
        try manager.activate([dock: after, menu: after]); XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
        try manager.restore(); XCTAssertEqual(backend.values[dock], before); XCTAssertNil(backend.values[menu])
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
    }
    func testCrashRecoveryAndManualChoiceWins() throws {
        let backend = Backend(), url = temporaryJournal(), key = PreferenceKey("dock", "hide")
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let off = try ActivationOverrides.boolean(false), on = try ActivationOverrides.boolean(true)
        backend.values[key] = off
        try ActivationOverrides(backend: backend, journal: url).activate([key: on])
        try ActivationOverrides(backend: backend, journal: url).restore(); XCTAssertEqual(backend.values[key], off)
        try ActivationOverrides(backend: backend, journal: url).activate([key: on])
        backend.values[key] = nil
        try ActivationOverrides(backend: backend, journal: url).restore(); XCTAssertNil(backend.values[key])
    }
    func testPartialWriteFailureRollsBackAndRetainsRecoveryJournal() throws {
        let backend = Backend(), url = temporaryJournal(), first = PreferenceKey("a", "one"), second = PreferenceKey("z", "two")
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let on = try ActivationOverrides.boolean(true); backend.fail = second
        XCTAssertThrowsError(try ActivationOverrides(backend: backend, journal: url).activate([first: on, second: on]))
        XCTAssertNil(backend.values[first]); XCTAssertNil(backend.values[second])
    }
    func testFailedRefreshCanRecoverNextLaunch() throws {
        let backend = Backend(), url = temporaryJournal(), key = PreferenceKey("dock", "hide")
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        backend.refreshFails = true
        XCTAssertThrowsError(try ActivationOverrides(backend: backend, journal: url).activate([key: ActivationOverrides.boolean(true)]))
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
        backend.refreshFails = false
        try ActivationOverrides(backend: backend, journal: url).restore()
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
    }
}
