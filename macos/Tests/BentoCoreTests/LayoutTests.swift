import XCTest
@testable import BentoCore

final class LayoutTests: XCTestCase {
    private let area = Rect(0, 0, 1920, 1080)
    private func window(_ width: Int = 200, _ height: Int = 150) -> WindowLeaf { WindowLeaf(windowID: UUID(), minimum: Size(width, height)) }
    private func assertValid(_ result: LayoutResult, in area: Rect, count: Int, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(result.regions.count, count, file: file, line: line)
        XCTAssertEqual(Set(result.regions.map(\.window.windowID)).count, count, file: file, line: line)
        for (i, region) in result.regions.enumerated() {
            let a = region.bounds
            XCTAssertGreaterThanOrEqual(a.x, area.x, file: file, line: line); XCTAssertGreaterThanOrEqual(a.y, area.y, file: file, line: line)
            XCTAssertLessThanOrEqual(a.right, area.right, file: file, line: line); XCTAssertLessThanOrEqual(a.bottom, area.bottom, file: file, line: line)
            XCTAssertGreaterThanOrEqual(a.width, region.window.minimum.width, file: file, line: line)
            XCTAssertGreaterThanOrEqual(a.height, region.window.minimum.height, file: file, line: line)
            for other in result.regions.dropFirst(i + 1) {
                let b = other.bounds
                XCTAssertTrue(a.right <= b.x || b.right <= a.x || a.bottom <= b.y || b.bottom <= a.y, "Overlap", file: file, line: line)
            }
        }
    }
    func testRecentActivationPrimaryAndOldestOverflow() throws {
        for count in 2...12 {
            let recent = (0..<count).map { _ in window(120, 100) }
            let root = try AutoLayout.activating(recent, in: area, gap: 14)
            let result = try LayoutEngine.calculate(root, in: area, gap: 14)
            assertValid(result, in: area, count: count)
            let primary = try XCTUnwrap(result.regions.first { $0.window.windowID == recent[0].windowID })
            XCTAssertTrue(result.regions.allSatisfy { $0.bounds.width * $0.bounds.height <= primary.bounds.width * primary.bounds.height })
        }
        let recent = [window(600, 500), window(600, 500), window(600, 500)]
        let small = Rect(0, 0, 1000, 600)
        let root = try AutoLayout.activating(recent, in: small)
        XCTAssertEqual(root?.windows.map(\.windowID), [recent[0].windowID])
    }
    func testRecentActivationHonorsAsymmetricLimitsAndImpossibleApps() throws {
        let recent = [window(3000, 2000), window(750, 300), window(200, 200)]
        let bounds = Rect(0, 0, 1000, 800)
        let result = try LayoutEngine.calculate(AutoLayout.activating(recent, in: bounds, gap: 14), in: bounds, gap: 14)
        assertValid(result, in: bounds, count: 2)
        XCTAssertFalse(result.regions.contains { $0.window.windowID == recent[0].windowID })
        XCTAssertThrowsError(try AutoLayout.activating([window(0, 20)], in: bounds))
    }
    func testPairCapacityMatchesBothPossibleSplitAxes() throws {
        for bounds in [Rect(0, 0, 480, 850), Rect(0, 0, 824, 600), Rect(0, 0, 1280, 720), Rect(0, 0, 1920, 1113)] {
            for widthA in [160, 336, 480, 700] { for heightA in [120, 242, 600] {
                for widthB in [160, 336, 480, 700] { for heightB in [120, 242, 600] {
                    let apps = [window(widthA, heightA), window(widthB, heightB)]
                    let fits = (widthA + widthB + 8 <= bounds.width && max(heightA, heightB) <= bounds.height) ||
                        (max(widthA, widthB) <= bounds.width && heightA + heightB + 8 <= bounds.height)
                    let root = try AutoLayout.activating(apps, in: bounds, gap: 8)
                    XCTAssertEqual(root?.windows.count == 2, fits)
                    if fits { assertValid(try LayoutEngine.calculate(root, in: bounds, gap: 8), in: bounds, count: 2) }
                } }
            } }
        }
    }
    func testNativeCellRoundingStaysInsideItsSlot() {
        let slot = Rect(962, 30, 958, 1113)
        XCTAssertTrue(NativeFrameFit.accepts(Rect(962, 30, 958, 1099), in: slot))
        XCTAssertFalse(NativeFrameFit.accepts(Rect(962, 30, 961, 1113), in: slot))
        XCTAssertFalse(NativeFrameFit.accepts(Rect(952, 30, 958, 1099), in: slot))
        XCTAssertFalse(NativeFrameFit.accepts(Rect(962, 30, 958, 1000), in: slot))
        XCTAssertEqual(NativeFrameFit.inwardTarget(actual: Rect(962, 30, 961, 1117), slot: slot), Rect(962, 30, 954, 1108))
        XCTAssertEqual(NativeFrameFit.inwardTarget(actual: Rect(962, 30, 1200, 1200), slot: slot), slot)
    }
    func testVisibleNonFocusedAppCanReflowExistingSlots() throws {
        let a = window(400, 500), b = window(400, 500), terminal = window(800, 150)
        let bounds = Rect(0, 0, 1000, 800)
        let original = LayoutNode.split(id: UUID(), axis: .horizontal, ratio: 0.5, first: .window(a), second: .window(b))
        let result = try LayoutEngine.calculate(AutoLayout.fitting([a, b, terminal], in: bounds, gap: 8,
            preserving: original, prioritizing: [a.windowID]), in: bounds, gap: 8)
        assertValid(result, in: bounds, count: 3)
    }
    func testChatAndTerminalFitEitherOrientationAtExactLimits() throws {
        let chat = window(480, 600), terminal = window(336, 242)
        for bounds in [Rect(0, 0, 824, 600), Rect(0, 0, 480, 850)] {
            for apps in [[chat, terminal], [terminal, chat]] {
                assertValid(try LayoutEngine.calculate(AutoLayout.activating(apps, in: bounds, gap: 8), in: bounds, gap: 8), in: bounds, count: 2)
            }
        }
    }
    func testLiveDockGeometryRespectsBothNativeReservations() {
        let frame = Rect(0, 0, 1280, 800), stale = Rect(0, 30, 1280, 707)
        XCTAssertEqual(DesktopWorkArea.correctingDock(frame: frame, visible: stale, dock: Rect(300, 710, 680, 90)), Rect(0, 30, 1280, 680))
        XCTAssertEqual(DesktopWorkArea.correctingDock(frame: frame, visible: stale, dock: Rect(300, 760, 680, 40)), stale)
        XCTAssertEqual(DesktopWorkArea.correctingDock(frame: frame, visible: stale, dock: Rect(0, 100, 60, 600)), Rect(60, 30, 1220, 707))
        XCTAssertEqual(DesktopWorkArea.correctingDock(frame: frame, visible: stale, dock: Rect(1220, 100, 60, 600)), Rect(0, 30, 1220, 707))
        XCTAssertEqual(DesktopWorkArea.correctingDock(frame: frame, visible: stale, dock: Rect(-500, 0, 40, 500)), stale)
        XCTAssertEqual(DesktopWorkArea.correctingDock(frame: frame, visible: stale, dock: nil), stale)
        let settled = Rect(0, 30, 1280, 730)
        XCTAssertEqual(DesktopWorkArea.correctingDock(frame: frame, visible: settled, dock: Rect(300, 760, 680, 40)), settled)
    }
    func testActivationDoesNotHideFittingAppsToEnlargeThePrimary() throws {
        let recent = [window(160, 120), window(500, 600), window(336, 339)]
        let bounds = Rect(8, 38, 1264, 691)
        let result = try LayoutEngine.calculate(AutoLayout.activating(recent, in: bounds, gap: 14), in: bounds, gap: 14)
        assertValid(result, in: bounds, count: 3)
        XCTAssertEqual(Set(result.regions.map(\.window.windowID)), Set(recent.map(\.windowID)))
    }
    func testOrderIndependentConstraintGrouping() throws {
        let apps = [window(600, 200), window(200, 600), window(600, 200), window(200, 600)]
        let bounds = Rect(0, 0, 1020, 620)
        let root = try AutoLayout.arrange(apps, in: bounds, gap: 10)
        assertValid(try LayoutEngine.calculate(root, in: bounds, gap: 10), in: bounds, count: 4)
    }
    func testRealBrowserAndChatLimitsKeepAllFourAppsUsable() throws {
        let apps = [window(500, 400), window(480, 600), window(336, 242), window(336, 242)]
        let bounds = Rect(8, 38, 1264, 687)
        let root = try AutoLayout.activating(apps, in: bounds, gap: 14)
        assertValid(try LayoutEngine.calculate(root, in: bounds, gap: 14), in: bounds, count: 4)
        let again = try AutoLayout.activating(apps, in: bounds, gap: 14)
        XCTAssertEqual(try LayoutEngine.calculate(root, in: bounds, gap: 14).regions.map(\.bounds), try LayoutEngine.calculate(again, in: bounds, gap: 14).regions.map(\.bounds))
    }
    func testSelectionKeepsMoreUsableAppsWithRecentUseAsTieBreaker() throws {
        let apps = [window(200, 200), window(900, 600), window(400, 300), window(400, 300)]
        let bounds = Rect(0, 0, 1000, 650)
        let result = try LayoutEngine.calculate(AutoLayout.activating(apps, in: bounds, gap: 10), in: bounds, gap: 10)
        assertValid(result, in: bounds, count: 3)
        XCTAssertEqual(Set(result.regions.map(\.window.windowID)), Set([apps[0].windowID, apps[2].windowID, apps[3].windowID]))
    }
    func testSelectionUsesRecencyWhenEqualCountsFit() throws {
        let apps = [window(400, 400), window(400, 400), window(400, 400)]
        let bounds = Rect(0, 0, 820, 420)
        let result = try LayoutEngine.calculate(AutoLayout.activating(apps, in: bounds, gap: 10), in: bounds, gap: 10)
        assertValid(result, in: bounds, count: 2)
        XCTAssertEqual(Set(result.regions.map(\.window.windowID)), Set(apps.prefix(2).map(\.windowID)))
    }
    func testEightAppCapacitySearchHasStableGeometry() throws {
        let apps = [window(500, 190), window(230, 540), window(360, 280), window(250, 400), window(460, 210), window(240, 420), window(330, 270), window(270, 350)]
        let bounds = Rect(-1200, 30, 1800, 1000)
        let start = Date()
        let first = CapacityPlanner.plan(apps, in: bounds, gap: 12, all: false)
        let second = CapacityPlanner.plan(apps, in: bounds, gap: 12, all: false)
        let result = try LayoutEngine.calculate(first, in: bounds, gap: 12)
        assertValid(result, in: bounds, count: 8)
        XCTAssertEqual(result.regions.map(\.bounds), try LayoutEngine.calculate(second, in: bounds, gap: 12).regions.map(\.bounds))
        XCTAssertLessThan(Date().timeIntervalSince(start), 2, "Two bounded searches should not stall desktop interaction")
    }
    func testSharedWindowsGeometryFixtures() throws {
        struct Pack: Decodable { let version: Int; let cases: [Fixture] }
        struct Fixture: Decodable {
            let name: String; let area: [Int]; let gap: Int; let tree: Node; let expected: [String: [Int]]?; let reject: Bool?
        }
        final class Node: Decodable {
            let window: Int?; let minimum: [Int]?; let axis: Axis?; let ratio: Double?; let first: Node?; let second: Node?
        }
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("shared/fixtures/layout-v1.json")
        let pack = try JSONDecoder().decode(Pack.self, from: Data(contentsOf: url)); XCTAssertEqual(pack.version, 1)
        for fixture in pack.cases {
            var ids: [UUID: String] = [:]
            func build(_ node: Node) -> LayoutNode {
                if let n = node.window {
                    let leaf = window(node.minimum![0], node.minimum![1]); ids[leaf.windowID] = String(n); return .window(leaf)
                }
                return .split(id: UUID(), axis: node.axis!, ratio: node.ratio!, first: build(node.first!), second: build(node.second!))
            }
            let root = build(fixture.tree), a = fixture.area, bounds = Rect(a[0], a[1], a[2], a[3])
            if fixture.reject == true { XCTAssertThrowsError(try LayoutEngine.calculate(root, in: bounds, gap: fixture.gap), fixture.name); continue }
            let result = try LayoutEngine.calculate(root, in: bounds, gap: fixture.gap)
            for region in result.regions {
                let r = region.bounds
                XCTAssertEqual([r.x, r.y, r.width, r.height], fixture.expected![ids[region.window.windowID]!]!, fixture.name)
            }
        }
    }
    func testAutomaticOneThroughTwelve() throws {
        for count in 1...12 {
            let root = try AutoLayout.arrange((0..<count).map { _ in window() }, in: area)
            assertValid(try LayoutEngine.calculate(root, in: area), in: area, count: count)
        }
    }
    func testPortraitAndAsymmetricMinima() throws {
        let portrait = Rect(-1080, -500, 1080, 1920)
        let root = try AutoLayout.arrange((0..<7).map { _ in window() }, in: portrait)
        assertValid(try LayoutEngine.calculate(root, in: portrait), in: portrait, count: 7)
        let wide = Rect(0, 0, 1000, 600)
        assertValid(try LayoutEngine.calculate(AutoLayout.arrange([window(750, 300), window()], in: wide), in: wide), in: wide, count: 2)
    }
    func testInvalidAndImpossibleInputs() throws {
        let w = window()
        XCTAssertThrowsError(try AutoLayout.arrange([w, w], in: area))
        XCTAssertThrowsError(try AutoLayout.arrange([window(0)], in: area))
        XCTAssertThrowsError(try AutoLayout.arrange([window(), window()], in: Rect(0, 0, 100, 100)))
        XCTAssertThrowsError(try LayoutEngine.calculate(.window(w), in: area, gap: -1))
        let invalid = LayoutNode.split(id: UUID(), axis: .horizontal, ratio: .nan, first: .window(window()), second: .window(window()))
        XCTAssertThrowsError(try LayoutEngine.calculate(invalid, in: area))
    }
    func testFittingLeavesOversizedWindowsOut() throws {
        let small = [window(), window()], oversized = window(2000, 1200)
        let root = try AutoLayout.fitting([oversized] + small, in: area)
        assertValid(try LayoutEngine.calculate(root, in: area), in: area, count: 2)
        XCTAssertEqual(Set(root!.windows.map(\.windowID)), Set(small.map(\.windowID)))
        XCTAssertNil(try AutoLayout.fitting([oversized], in: area))
    }
    func testFittingChoosesUsableSubsetWhenTogetherTooLarge() throws {
        let bounds = Rect(0, 0, 600, 400), large = window(550, 350)
        let small = [window(250, 300), window(250, 300)]
        let root = try AutoLayout.fitting([large] + small, in: bounds)
        assertValid(try LayoutEngine.calculate(root, in: bounds), in: bounds, count: 2)
        XCTAssertFalse(root!.windows.contains { $0.windowID == large.windowID })
    }
    func testFittingPreservesEditsAndRefreshesLearnedMinimums() throws {
        let a = window(), b = window(), large = window(2000, 1200)
        let root = LayoutNode.split(id: UUID(), axis: .horizontal, ratio: 0.7, first: .window(a), second: .window(b))
        XCTAssertEqual(try AutoLayout.fitting([a, b, large], in: area, preserving: root), root)
        var grown = a; grown.minimum = Size(2000, 1200)
        let updated = try AutoLayout.fitting([grown, b], in: area, preserving: root)
        XCTAssertEqual(updated?.windows.map(\.windowID), [b.windowID])
        let recovered = try AutoLayout.fitting([a, b], in: area, preserving: updated)
        assertValid(try LayoutEngine.calculate(recovered, in: area), in: area, count: 2)
    }
    func testFocusedAppDoesNotCauseEvictionForAnIndividuallyImpossibleWindow() throws {
        let bounds = Rect(0, 0, 600, 400)
        let focused = window(350, 160), other = window(350, 160), impossible = window(700, 100)
        let next = try AutoLayout.fitting([focused, other, impossible], in: bounds, prioritizing: [focused.windowID],
            leastRecentlyUsed: [other.windowID, impossible.windowID, focused.windowID])
        XCTAssertEqual(Set(next!.windows.map(\.windowID)), [focused.windowID, other.windowID])
        assertValid(try LayoutEngine.calculate(next, in: bounds), in: bounds, count: 2)
    }
    func testAdmissionReflowsFragmentedSlotsBeforeEvictingAnApp() throws {
        let bounds = Rect(0, 0, 1000, 700)
        let a = window(200, 200), b = window(200, 200), incoming = window(700, 250)
        let edited = LayoutNode.split(id: UUID(), axis: .horizontal, ratio: 0.5, first: .window(a), second: .window(b))
        let next = try AutoLayout.fitting([a, b, incoming], in: bounds, preserving: edited,
            prioritizing: [incoming.windowID], leastRecentlyUsed: [a.windowID, b.windowID])
        XCTAssertEqual(Set(next!.windows.map(\.windowID)), [a.windowID, b.windowID, incoming.windowID])
        assertValid(try LayoutEngine.calculate(next, in: bounds), in: bounds, count: 3)
        let wide = try XCTUnwrap(LayoutEngine.calculate(next, in: bounds).regions.first { $0.window.windowID == incoming.windowID })
        XCTAssertGreaterThanOrEqual(wide.bounds.width, 700)
    }
    func testDockAdmissionEvictsOldestAndOnlyAsManyAsNeeded() throws {
        let bounds = Rect(0, 0, 600, 400)
        let recent = window(350, 160), oldest = window(350, 160), incoming = window(350, 160)
        let old = try AutoLayout.arrange([recent, oldest], in: bounds)
        let next = try AutoLayout.fitting([recent, oldest, incoming], in: bounds, preserving: old,
            prioritizing: [incoming.windowID], leastRecentlyUsed: [oldest.windowID, recent.windowID])
        XCTAssertEqual(Set(next!.windows.map(\.windowID)), [recent.windowID, incoming.windowID])
        assertValid(try LayoutEngine.calculate(next, in: bounds), in: bounds, count: 2)
        let huge = window(550, 350)
        let solo = try AutoLayout.fitting([recent, oldest, huge], in: bounds, preserving: old,
            prioritizing: [huge.windowID], leastRecentlyUsed: [oldest.windowID, recent.windowID])
        XCTAssertEqual(solo?.windows.map(\.windowID), [huge.windowID])
    }
    func testDockAdmissionPreservesEditedLayoutWhenAllFit() throws {
        let a = window(), b = window(), c = window()
        let edited = LayoutNode.split(id: UUID(), axis: .horizontal, ratio: 0.7, first: .window(a), second: .window(b))
        let expected = try AutoLayout.fitting([a, b, c], in: area, preserving: edited)
        let next = try AutoLayout.fitting([a, b, c], in: area, preserving: edited, prioritizing: [c.windowID])
        XCTAssertEqual(next?.id, expected?.id)
        XCTAssertEqual(try LayoutEngine.calculate(next, in: area).regions.map(\.bounds),
                       try LayoutEngine.calculate(expected, in: area).regions.map(\.bounds))
    }
    func testCrowdedDockAdmissionReplacesOneSlotWithoutMovingNeighbors() throws {
        let bounds = Rect(0, 0, 1200, 600)
        let a = window(300, 400), b = window(300, 400), c = window(300, 400), incoming = window(300, 400)
        let edited = LayoutNode.split(id: UUID(), axis: .horizontal, ratio: 0.4, first: .window(a), second:
            .split(id: UUID(), axis: .horizontal, ratio: 0.5, first: .window(b), second: .window(c)))
        let before = try LayoutEngine.calculate(edited, in: bounds).regions
        let next = try AutoLayout.fitting([a, b, c, incoming], in: bounds, preserving: edited,
            prioritizing: [incoming.windowID], leastRecentlyUsed: [b.windowID, c.windowID, a.windowID])
        let after = try LayoutEngine.calculate(next, in: bounds).regions
        for id in [a.windowID, c.windowID] {
            XCTAssertEqual(after.first { $0.window.windowID == id }?.bounds, before.first { $0.window.windowID == id }?.bounds)
        }
        XCTAssertEqual(after.first { $0.window.windowID == incoming.windowID }?.bounds, before.first { $0.window.windowID == b.windowID }?.bounds)
        XCTAssertFalse(after.contains { $0.window.windowID == b.windowID })
    }
    func testImpossibleDockWindowDoesNotEvictUsableWindows() throws {
        let a = window(), b = window(), impossible = window(3000, 2000)
        let edited = try AutoLayout.arrange([a, b], in: area)
        XCTAssertEqual(try AutoLayout.fitting([a, b, impossible], in: area, preserving: edited,
            prioritizing: [impossible.windowID]), edited)
    }
    func testFittingRejectsInvalidInputsRatherThanSkippingThem() throws {
        let w = window()
        XCTAssertThrowsError(try AutoLayout.fitting([w, w], in: area))
        XCTAssertThrowsError(try AutoLayout.fitting([window(0)], in: area))
        XCTAssertThrowsError(try AutoLayout.fitting([w], in: area, gap: -1))
    }
    func testFourDirectionsAndNoDuplicates() throws {
        for direction in [Placement.left, .right, .top, .bottom] {
            let a = window(), b = window()
            let original = Workspace(roots: ["A": .window(a)])
            let next = try original.placing(b, on: "A", target: a.id, placement: direction)
            let regions = try LayoutEngine.calculate(next.roots["A"], in: area)
            assertValid(regions, in: area, count: 2)
            let incoming = regions.regions.first { $0.window.windowID == b.windowID }!.bounds
            switch direction {
            case .left: XCTAssertEqual(incoming.x, area.x)
            case .right: XCTAssertEqual(incoming.right, area.right)
            case .top: XCTAssertEqual(incoming.y, area.y)
            case .bottom: XCTAssertEqual(incoming.bottom, area.bottom)
            default: XCTFail()
            }
            XCTAssertEqual(original.windows.count, 1)
        }
    }
    func testCrossDisplaySwapAndRemoval() throws {
        let a = window(), b = window()
        let original = Workspace(roots: ["A": .window(a), "B": .window(b)])
        let swapped = try original.placing(a, on: "B", target: b.id, placement: .center)
        XCTAssertEqual(swapped.roots["A"]?.windows.first?.windowID, b.windowID)
        XCTAssertEqual(swapped.roots["B"]?.windows.first?.windowID, a.windowID)
        XCTAssertNil(swapped.removing(a.windowID).roots["B"])
        XCTAssertEqual(swapped.windows.count, 2)
    }
    func testSiblingPromotedAndInsertionPreservesRoot() throws {
        let id = UUID(), a = window(), b = window()
        let root = LayoutNode.split(id: id, axis: .horizontal, ratio: 0.65, first: .window(a), second: .window(b))
        XCTAssertEqual(root.removing(a.windowID), .window(b))
        let inserted = try AutoLayout.insert(window(), into: root, in: area)
        guard case let .split(newID, _, ratio, _, _) = inserted else { return XCTFail() }
        XCTAssertEqual(newID, id); XCTAssertEqual(ratio, 0.65)
    }
    func testUndoRedoBranchAndBound() throws {
        var history = LayoutHistory()
        let first = Workspace(roots: ["A": .window(window())]), second = Workspace(roots: ["B": .window(window())])
        history.commit(first); history.commit(second)
        XCTAssertEqual(history.undo(), first); XCTAssertEqual(history.redo(), second)
        _ = history.undo(); history.commit(Workspace()); XCTAssertEqual(history.redo(), Workspace())
        for _ in 0..<120 { history.commit(Workspace(roots: ["A": .window(window())])) }
        for _ in 0..<100 { _ = history.undo() }
        let retained = history.current; XCTAssertEqual(history.undo(), retained)
    }
    func testHoldQuickDropCancellationAndJitter() throws {
        var intent = DragIntent(); let target = UUID(), rect = Rect(0, 0, 1000, 800)
        XCTAssertEqual(try intent.update(display: "A", target: target, bounds: rect, point: Point(30, 400), now: 0, holdMilliseconds: 900).placement, .center)
        XCTAssertEqual(try intent.update(display: "A", target: target, bounds: rect, point: Point(30, 400), now: 0.899, holdMilliseconds: 900).placement, .center)
        XCTAssertEqual(try intent.update(display: "A", target: target, bounds: rect, point: Point(30, 400), now: 0.9, holdMilliseconds: 900).placement, .left)
        XCTAssertEqual(try intent.update(display: "A", target: target, bounds: rect, point: Point(253, 400), now: 1.0, holdMilliseconds: 900).placement, .left)
        intent.reset()
        XCTAssertEqual(try intent.update(display: "A", target: target, bounds: rect, point: Point(30, 400), now: 2, holdMilliseconds: 900).placement, .center)
        XCTAssertEqual(try intent.update(display: "B", target: target, bounds: rect, point: Point(30, 400), now: 3, holdMilliseconds: 900).placement, .center)
        XCTAssertEqual(try intent.update(display: "B", target: target, bounds: rect, point: Point(500, 400), now: 4, holdMilliseconds: 0).placement, .center)
    }
    func testZoneBoundsAndRoundTripPersistence() throws {
        XCTAssertEqual(try LayoutEngine.placement(in: area, at: Point(960, 540)), .center)
        XCTAssertThrowsError(try LayoutEngine.placement(in: area, at: Point(1920, 500)))
        let state = Workspace(roots: ["display": try AutoLayout.arrange([window(), window(), window()], in: area)!])
        XCTAssertEqual(try JSONDecoder().decode(Workspace.self, from: JSONEncoder().encode(state)), state)
    }
    func testSeededThousandOperationExercise() throws {
        var seed: UInt64 = 42
        func random(_ limit: Int) -> Int { seed = seed &* 6364136223846793005 &+ 1; return Int((seed >> 32) % UInt64(limit)) }
        var root = try AutoLayout.arrange([window(), window(), window()], in: area)!
        for _ in 0..<1000 {
            let leaves = root.windows
            switch random(3) {
            case 0:
                if leaves.count < 10, let candidate = try? AutoLayout.insert(window(), into: root, in: area) { root = candidate }
            case 1:
                if leaves.count > 1 { root = root.removing(leaves[random(leaves.count)].windowID)! }
            default:
                let dividers = try LayoutEngine.calculate(root, in: area).dividers
                if !dividers.isEmpty { root = root.resizing(dividers[random(dividers.count)].id, ratio: Double(random(99) + 1) / 100) }
            }
            assertValid(try LayoutEngine.calculate(root, in: area), in: area, count: root.windows.count)
        }
    }
}
