import XCTest
import CryptoKit
@testable import BentoCore

final class InteractionAndUpdateTests: XCTestCase {
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
        XCTAssertEqual(armed.bounds, InteractionGeometry.preview(target.bounds, placement: .left, gap: 8))
        XCTAssertEqual(try LayoutEngine.calculate(state.roots["A"], in: area).regions, regions)
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
