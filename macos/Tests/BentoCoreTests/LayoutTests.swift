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
