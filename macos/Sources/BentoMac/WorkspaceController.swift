import AppKit
import SwiftUI
import BentoCore

struct MacSettings: Codable {
    var gap = 8; var margin = 8; var splitHold = 900; var theme = "System"
    var onboardingComplete = false
    var hideDock = false; var hideMenuBar = false; var edgeSnapping = "Keep"
    var shortcut = ShortcutConfig()
    var backgroundDarkness = 50
    var minimizeOverflow = true
    var animate = true; var animationMS = 180
    init() {}
    enum CodingKeys: String, CodingKey { case minimizeOverflow, gap, margin, splitHold, theme, onboardingComplete, hideDock, hideMenuBar, edgeSnapping, shortcut, backgroundDarkness, animate, animationMS }
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        minimizeOverflow = try values.decodeIfPresent(Bool.self, forKey: .minimizeOverflow) ?? true
        gap = try values.decodeIfPresent(Int.self, forKey: .gap) ?? 8
        margin = try values.decodeIfPresent(Int.self, forKey: .margin) ?? 8
        splitHold = try values.decodeIfPresent(Int.self, forKey: .splitHold) ?? 900
        theme = try values.decodeIfPresent(String.self, forKey: .theme) ?? "System"
        onboardingComplete = try values.decodeIfPresent(Bool.self, forKey: .onboardingComplete) ?? false
        hideDock = try values.decodeIfPresent(Bool.self, forKey: .hideDock) ?? false
        hideMenuBar = try values.decodeIfPresent(Bool.self, forKey: .hideMenuBar) ?? false
        edgeSnapping = try values.decodeIfPresent(String.self, forKey: .edgeSnapping) ?? "Keep"
        shortcut = try values.decodeIfPresent(ShortcutConfig.self, forKey: .shortcut) ?? ShortcutConfig()
        backgroundDarkness = try values.decodeIfPresent(Int.self, forKey: .backgroundDarkness) ?? 50
        animate = try values.decodeIfPresent(Bool.self, forKey: .animate) ?? true
        animationMS = try values.decodeIfPresent(Int.self, forKey: .animationMS) ?? 180
    }
    static var directory: URL { FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Bento", isDirectory: true) }
    static var url: URL { directory.appendingPathComponent("settings-macos.json") }
    static func load() -> MacSettings {
        guard let data = try? Data(contentsOf: url), let settings = try? JSONDecoder().decode(MacSettings.self, from: data),
              (4...32).contains(settings.gap), (0...64).contains(settings.margin), (0...2000).contains(settings.splitHold),
              ["System", "Light", "Dark"].contains(settings.theme), ["Keep", "On", "Off"].contains(settings.edgeSnapping), settings.shortcut.valid,
              (0...100).contains(settings.backgroundDarkness), (80...400).contains(settings.animationMS) else { return MacSettings() }
        return settings
    }
    func save() throws {
        try FileManager.default.createDirectory(at: Self.directory, withIntermediateDirectories: true)
        try JSONEncoder().encode(self).write(to: Self.url, options: .atomic)
    }
}
struct SavedWorkspace: Codable {
    struct Match: Codable { let bundleID: String; let title: String }
    let version: Int; let platform: String; let workspace: Workspace; let applications: [UUID: Match]
    static var url: URL { MacSettings.directory.appendingPathComponent("saved-layout-macos.json") }
}

@MainActor final class WorkspaceController: ObservableObject {
    private enum ArrangementFailure: LocalizedError {
        case window(UUID)
        var errorDescription: String? { "A window did not accept its assigned position or size." }
    }
    let system: MacWindowSystem
    @Published var settings = MacSettings.load()
    @Published private(set) var layoutGap = 8
    @Published private(set) var layoutMargin = 8
    private var appliedDesktopOptions: [BentoCore.PreferenceKey: Data] = [:]
    private var appliedMinimizeOverflow = true
    private var settingsRevision = 0
    private var settingsTask: Task<Void, Never>?
    @Published private(set) var applyingSettings = false
    @Published var permission = false
    @Published var active = false
    @Published var busy = false
    @Published var interacting = false
    @Published var activating = false
    @Published var windows: [ManagedWindow] = []
    @Published var message: String?
    @Published var page = "Workspace"
    private(set) var history = LayoutHistory()
    private var originals: [UUID: (ManagedWindow, Rect)] = [:]
    private(set) var minimizedByBento: [UUID: ManagedWindow] = [:]
    private var reopenedWindows = Set<UUID>()
    private var interactionSequence = 0
    private var lastInteraction: [UUID: Int] = [:]
    private var lastFocusedWindow: UUID?

    func recordInteraction(_ window: ManagedWindow) {
        interactionSequence += 1
        lastInteraction[window.id] = interactionSequence
    }
    private func observeFocus(in current: [ManagedWindow]) {
        let focused = system.focusedWindow(in: current)
        if let focused, focused.id != lastFocusedWindow { recordInteraction(focused) }
        lastFocusedWindow = focused?.id
    }
    private struct ArrangementInput: Equatable {
        let ids: [UUID]
        let minima: [Size]
        let frames: [Rect]
        let displays: [DisplayArea]
        let gap: Int
    }
    private var failedAutomaticInput: ArrangementInput?
    private var pendingMembership: Set<UUID>?
    private var membershipSamples = 0
    private var reconciliationQueued = false
    private var pendingDrift: [Rect]?
    private var driftSamples = 0
    private func arrangementInput(_ current: [ManagedWindow]) -> ArrangementInput {
        let ordered = current.sorted { $0.id.uuidString < $1.id.uuidString }
        return ArrangementInput(ids: ordered.map(\.id), minima: ordered.map(\.minimum), frames: ordered.map(\.frame),
            displays: DisplayArea.all(margin: layoutMargin), gap: layoutGap)
    }
    private var timer: Timer?
    private var lastDisplays: [DisplayArea] = []
    private var released = Set<UUID>()
    private var lastBento: Workspace?
    private var lastReleased = Set<UUID>()
    private var lastMinimized = Set<UUID>()
    private var activationGeneration = 0
    private var activateAfterPermission = false
    var onStateChange: (() -> Void)?
    var onSettingsChange: (() -> Void)?
    var cancelInteraction: (() async -> Void)?
    private let trace: ((String) -> Void)?
    private let reduceMotion: () -> Bool
    private let persistSettings: (MacSettings) throws -> Void
    private let desktopPreferences: ActivationOverrides

    init(system: MacWindowSystem? = nil, settings: MacSettings? = nil, preferences: ActivationOverrides? = nil, persistSettings: @escaping (MacSettings) throws -> Void = { try $0.save() }, backgroundMonitoring: Bool = true, trace: ((String) -> Void)? = nil, reduceMotion: @escaping () -> Bool = { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }) {
        self.trace = trace ?? (backgroundMonitoring ? { InteractionDiagnostics.record($0) } : nil)
        self.reduceMotion = reduceMotion
        self.persistSettings = persistSettings
        self.system = system ?? MacWindowSystem()
        self.desktopPreferences = preferences ?? ActivationOverrides(backend: DesktopPreferenceBackend(), journal: MacSettings.directory.appendingPathComponent("desktop-preferences-session.json"))
        if let settings { self.settings = settings }
        layoutGap = self.settings.gap; layoutMargin = self.settings.margin
        appliedMinimizeOverflow = self.settings.minimizeOverflow
        permission = self.system.trusted
        if backgroundMonitoring { timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in Task { @MainActor in self?.tick() } } }
    }
    private func activateDesktop() throws {
        layoutGap = settings.gap; layoutMargin = settings.margin
        let desired = try settings.desktopOverrides()
        try desktopPreferences.activate(desired); appliedDesktopOptions = desired
        appliedMinimizeOverflow = settings.minimizeOverflow
    }
    func saveSettings() {
        guard settings.shortcut.valid else { message = "Choose at least one modifier for the shortcut."; onSettingsChange?(); return }
        do { try persistSettings(settings); scheduleSettingsUpdate(); onSettingsChange?() } catch { message = "Could not save settings: \(error.localizedDescription)" }
    }
    private var desktopPointerPressed: Bool { system.pointerPressed && system.tracksDesktopPointer }
    func scheduleSettingsUpdate() {
        settingsRevision += 1
        guard settingsTask == nil else { return }
        settingsTask = Task { @MainActor [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                let revision = self.settingsRevision
                try? await Task.sleep(for: .milliseconds(120))
                if revision != self.settingsRevision { continue }
                while self.busy || self.interacting || self.activating || self.desktopPointerPressed {
                    if Task.isCancelled { break }
                    try? await Task.sleep(for: .milliseconds(50))
                }
                guard !Task.isCancelled else { break }
                await self.applyLiveSettings()
                if revision == self.settingsRevision { break }
            }
            self.settingsTask = nil
        }
    }
    func applyLiveSettings() async {
        guard !busy, !interacting, !activating, !desktopPointerPressed else { scheduleSettingsUpdate(); return }
        applyingSettings = true; activating = true
        defer { activating = false; applyingSettings = false; onSettingsChange?(); onStateChange?() }
        let oldGap = layoutGap, oldMargin = layoutMargin
        let generation = activationGeneration
        do {
            if !active {
                try desktopPreferences.restore(); appliedDesktopOptions = [:]
                layoutGap = settings.gap; layoutMargin = settings.margin
                appliedMinimizeOverflow = settings.minimizeOverflow
                return
            }
            let desired = try settings.desktopOverrides()
            let desktopChanged = desired != appliedDesktopOptions
            if desktopChanged {
                activating = true
                do {
                    try desktopPreferences.update(desired); appliedDesktopOptions = desired
                    try await Task.sleep(for: .milliseconds(500))
                    while desktopPointerPressed { try await Task.sleep(for: .milliseconds(50)) }
                } catch { activating = false; appliedDesktopOptions = [:]; throw error }
                guard active else { return }
            }
            let overflowChanged = appliedMinimizeOverflow != settings.minimizeOverflow
            if overflowChanged && !settings.minimizeOverflow { _ = await restoreMinimized() }
            guard active, generation == activationGeneration else { return }
            appliedMinimizeOverflow = settings.minimizeOverflow
            let geometryChanged = oldGap != settings.gap || oldMargin != settings.margin
            let requestedGap = settings.gap, requestedMargin = settings.margin
            layoutGap = requestedGap; layoutMargin = requestedMargin
            if geometryChanged || desktopChanged || overflowChanged {
                activating = false
                if !(await arrange(preserving: true, skipRefusingWindows: false)) && geometryChanged {
                    layoutGap = oldGap; layoutMargin = oldMargin
                    if settings.gap == requestedGap { settings.gap = oldGap }
                    if settings.margin == requestedMargin { settings.margin = oldMargin }
                    try? persistSettings(settings)
                }
            }
        } catch { message = error.localizedDescription }
    }
    func tick() {
        refreshPermissionStatus()
        guard permission, !busy, !interacting, !activating, !reconciliationQueued, !system.pointerPressed else { return }
        if active {
            do {
                let current = try discoverWindows()
                let displaysChanged = DisplayArea.all(margin: layoutMargin) != lastDisplays
                let currentIDs = Set(current.map(\.id))
                let missing = windows.filter { !currentIDs.contains($0.id) && system.isAlive($0) }
                if !displaysChanged && !missing.isEmpty {
                    // AX and WindowServer can briefly disagree while a native app
                    // moves. Require a second observation before removing live leaves.
                    if pendingMembership == currentIDs { membershipSamples += 1 }
                    else { pendingMembership = currentIDs; membershipSamples = 1 }
                    guard membershipSamples >= 2 else { trace?("membership change awaiting confirmation"); return }
                } else { pendingMembership = nil; membershipSamples = 0 }
                var expected: [UUID: Rect] = [:]
                for display in lastDisplays {
                    for region in (try? LayoutEngine.calculate(history.current.roots[display.id], in: display.bounds, gap: layoutGap).regions) ?? [] {
                        expected[region.window.windowID] = region.bounds
                    }
                }
                let drift = current.filter { window in
                    guard let wanted = expected[window.id] else { return false }
                    let frame = window.frame
                    return abs(frame.x - wanted.x) > 2 || abs(frame.y - wanted.y) > 2 || abs(frame.width - wanted.width) > 2 || abs(frame.height - wanted.height) > 2
                }.sorted { $0.id.uuidString < $1.id.uuidString }.map(\.frame)
                if !drift.isEmpty && !displaysChanged {
                    if pendingDrift == drift { driftSamples += 1 } else { pendingDrift = drift; driftSamples = 1 }
                } else { pendingDrift = nil; driftSamples = 0 }
                if !reopenedWindows.isEmpty || displaysChanged || driftSamples >= 2 || Set(current.map(\.id)) != Set(windows.map(\.id)) {
                    guard !reopenedWindows.isEmpty || failedAutomaticInput != arrangementInput(current) else { return }
                    reconciliationQueued = true
                    Task {
                        defer { self.reconciliationQueued = false }
                        // Recheck at execution: the user may have started a drag
                        // after discovery queued this reconciliation.
                        guard !self.system.pointerPressed, !self.interacting else { return }
                        await self.arrange(preserving: true, automatic: true)
                    }
                }
            } catch { message = error.localizedDescription }
        }
    }
    private func discoverWindows() throws -> [ManagedWindow] {
        var visible = try system.discover()
        let visibleIDs = Set(visible.map(\.id))
        if active {
            // Includes newly launched, manually restored and unhidden windows,
            // even when Bento did not own their earlier minimization.
            reopenedWindows.formUnion(visibleIDs.subtracting(Set(windows.map(\.id))))
        }
        observeFocus(in: visible)
        for (id, window) in minimizedByBento {
            guard system.isAlive(window) else { minimizedByBento.removeValue(forKey: id); continue }
            if visibleIDs.contains(id) && !system.isMinimized(window) {
                reopenedWindows.insert(id); minimizedByBento.removeValue(forKey: id)
            } else if system.isMinimized(window) { visible.append(window) }
        }
        return visible
    }
    private func minimizeOverflow(included: Set<UUID>, current: [ManagedWindow]) {
        guard settings.minimizeOverflow else { return }
        for window in current where !included.contains(window.id) && minimizedByBento[window.id] == nil {
            // Only own minimizations made by Bento, never those made before activation.
            guard !system.isMinimized(window) else { continue }
            do { try system.setMinimized(window, true); minimizedByBento[window.id] = window }
            catch { /* Unsupported windows stay visible; other apps still arrange. */ }
        }
    }
    private func restoreMinimized() async -> Int {
        for (id, window) in minimizedByBento {
            if !system.isAlive(window) { minimizedByBento.removeValue(forKey: id); continue }
            try? system.setMinimized(window, false)
        }
        try? await Task.sleep(for: .milliseconds(150))
        minimizedByBento = minimizedByBento.filter { system.isAlive($0.value) && system.isMinimized($0.value) }
        return minimizedByBento.count
    }
    func deferActivationUntilPermission() { activateAfterPermission = true }
    func refreshPermissionStatus() {
        let currentPermission = system.trusted
        if permission != currentPermission {
            permission = currentPermission
            if permission && !active && !busy && !activating { refresh() }
            onStateChange?()
        }
        if active && !permission { active = false; recoverDesktopPreferences(); message = "Bento paused because Accessibility access was removed. Enable access, then arrange again."; onStateChange?() }
        if activateAfterPermission && permission && !active && !busy && !activating && !interacting {
            activateAfterPermission = false
            Task { await toggleLayout() }
        }
    }
    func refresh() {
        permission = system.trusted
        guard permission else { return }
        do { windows = try discoverWindows(); message = windows.isEmpty ? "Open an application window to begin." : nil }
        catch { message = error.localizedDescription }
    }
    func toggle() { Task { await toggleLayout() } }
    func toggleLayout() async { if active { await restore() } else { await arrange(resuming: lastBento != nil) } }
    private func display(for window: ManagedWindow, displays: [DisplayArea]) -> DisplayArea? {
        displays.max { a, b in
            func overlap(_ r: Rect) -> Int { max(0, min(r.right, window.frame.right) - max(r.x, window.frame.x)) * max(0, min(r.bottom, window.frame.bottom) - max(r.y, window.frame.y)) }
            return overlap(a.bounds) < overlap(b.bounds)
        }
    }
    var floatingWindows: [ManagedWindow] {
        let tiled = Set(history.current.windows.map(\.windowID))
        return windows.filter { !tiled.contains($0.id) }
    }
    @discardableResult func arrange(preserving: Bool = false, resuming: Bool = false, automatic: Bool = false, skipRefusingWindows: Bool = true) async -> Bool {
        guard !busy, !interacting, !activating else { return false }
        if automatic && system.pointerPressed { return false }
        activating = true; defer { activating = false }
        let previousWindows = windows
        let generation = activationGeneration
        let wasActive = active
        trace?("arrangement start preserving=\(preserving) resuming=\(resuming) active=\(wasActive)")
        do {
            if !preserving { released = resuming ? lastReleased : [] }
            let current = try discoverWindows(); windows = current
            guard !current.isEmpty else {
                if preserving && previousWindows.contains(where: { system.isAlive($0) }) {
                    windows = previousWindows; failedAutomaticInput = arrangementInput(current)
                    message = "Waiting for visible windows before updating the layout."; return false
                }
                if preserving { history.commit(Workspace()); onStateChange?() }
                message = "Open an application window to begin."; return false
            }
            if !wasActive {
                try activateDesktop(); try await Task.sleep(for: .milliseconds(500))
            }
            let displays = DisplayArea.all(margin: layoutMargin)
            let previous = preserving ? history.current : resuming ? lastBento ?? Workspace() : Workspace()
            if resuming, lastBento != nil {
                // Resume the edited tree itself. Native frames have just been restored
                // to pre-Bento positions and cannot determine saved display ownership.
                let next = previous.reconciled(with: current.map(\.leaf))
                for (id, root) in next.roots {
                    guard let area = displays.first(where: { $0.id == id }) else { throw LayoutError.missingTarget }
                    _ = try LayoutEngine.calculate(root, in: area.bounds, gap: layoutGap)
                }
                try await apply(next, displays: displays, animate: false)
                for window in current where lastMinimized.contains(window.id) && !next.windows.contains(where: { $0.windowID == window.id }) {
                    try? system.setMinimized(window, true)
                    if system.isMinimized(window) { minimizedByBento[window.id] = window }
                }
                guard generation == activationGeneration else { return false }
                history.commit(next); lastDisplays = displays; reopenedWindows.removeAll()
                active = !next.windows.isEmpty || !minimizedByBento.isEmpty
                if !active { try desktopPreferences.restore() }
                message = nil; trace?("saved arrangement resumed without automatic placement")
                onStateChange?(); return true
            }
            // Plan with known constraints first. An unknown native minimum gets one
            // correction, never a per-window series of visible layout attempts.
            let attemptLimit = 1
            var excluded = Set<UUID>()
            for attempt in 0...attemptLimit {
                guard generation == activationGeneration else { return false }
                var next = Workspace()
                for area in displays {
                    let members = current.filter { window in
                        guard !released.contains(window.id), !excluded.contains(window.id) else { return false }
                        let savedDisplay = previous.roots.first { $0.value.windows.contains { $0.windowID == window.id } }?.key
                        let owner = savedDisplay.flatMap { id in displays.first { $0.id == id } } ?? display(for: window, displays: displays)
                        return owner?.id == area.id
                    }
                    let oldestFirst = members.enumerated().sorted {
                        // Already minimized overflow gives up space before visible apps.
                        let a = minimizedByBento[$0.element.id] != nil ? -1 : lastInteraction[$0.element.id] ?? 0
                        let b = minimizedByBento[$1.element.id] != nil ? -1 : lastInteraction[$1.element.id] ?? 0
                        return a == b ? $0.offset < $1.offset : a < b
                    }.map { $0.element.id }
                    let priority = reopenedWindows.isEmpty
                        ? Set(system.focusedWindow(in: members).map { [$0.id] } ?? []) : reopenedWindows
                    next.roots[area.id] = try AutoLayout.fitting(members.map(\.leaf), in: area.bounds, gap: layoutGap, preserving: previous.roots[area.id], prioritizing: priority, leastRecentlyUsed: oldestFirst)
                }
                if automatic && system.pointerPressed {
                    windows = previousWindows; trace?("automatic arrangement deferred: pointer pressed during discovery")
                    return false
                }
                // Closing a window collapses its branch smoothly. New-window admission
                // retains the bounded final-frame path to validate native minima first.
                let closed = preserving && previousWindows.contains { window in !system.isAlive(window) && previous.windows.contains(where: { $0.windowID == window.id }) }
                do { try await apply(next, displays: displays, allowSkipping: true, animate: attempt == 0 && (!wasActive || closed)) }
                catch ArrangementFailure.window(let id) where attempt < attemptLimit && skipRefusingWindows {
                    excluded.insert(id); continue
                }
                catch WindowFailure.minimumSize where attempt < attemptLimit {
                    continue
                }
                guard generation == activationGeneration else { return false }
                let included = Set(next.windows.map(\.windowID))
                // Keep originals for overflow minimized in place. Floating exclusions
                // are forgotten so restoration cannot undo later user movement.
                let currentIDs = Set(current.map(\.id))
                originals = originals.filter { included.contains($0.key) || !currentIDs.contains($0.key) || settings.minimizeOverflow }
                minimizeOverflow(included: included, current: current.filter { !released.contains($0.id) })
                trace?("arrangement committed attempt=\(attempt + 1) tiled=\(included.count) overflow=\(current.count - included.count)")
                reopenedWindows.removeAll(); failedAutomaticInput = nil
                lastDisplays = displays; history.commit(next); active = !included.isEmpty || !minimizedByBento.isEmpty
                if !active { try desktopPreferences.restore() }
                message = active ? nil : "No windows fit on this display. Your windows were left in their original positions."
                onStateChange?(); return active
            }
        } catch {
            trace?("arrangement stopped error=\(String(reflecting: type(of: error)))")
            failedAutomaticInput = arrangementInput(windows)
            reopenedWindows.removeAll()
            message = error.localizedDescription
            if !wasActive { do { try desktopPreferences.restore() } catch { message = "\(message ?? "") \(error.localizedDescription)" } }
        }
        return false
    }
    func apply(_ workspace: Workspace, displays: [DisplayArea], allowSkipping: Bool = false, liveResize: Bool = false, animate: Bool = true) async throws {
        guard !busy else { throw LayoutError.invalidInput }; busy = true; defer { busy = false }
        func write(_ window: ManagedWindow, frame: Rect) throws {
            do { try system.write(window, frame: frame) }
            catch WindowFailure.rejected where allowSkipping { throw ArrangementFailure.window(window.id) }
            catch WindowFailure.unavailable where allowSkipping { throw ArrangementFailure.window(window.id) }
        }
        var plan: [(ManagedWindow, Rect)] = []
        for (displayID, root) in workspace.roots {
            guard let display = displays.first(where: { $0.id == displayID }) else { throw LayoutError.invalidInput }
            for region in try LayoutEngine.calculate(root, in: display.bounds, gap: layoutGap).regions {
                guard let window = windows.first(where: { $0.id == region.window.windowID }) else { throw LayoutError.missingTarget }
                plan.append((window, region.bounds))
            }
        }
        // Undoing the first arrangement or displacing a window restores it rather
        // than leaving native geometry behind after its leaf disappears.
        let included = Set(workspace.windows.map(\.windowID))
        for leaf in history.current.windows where !included.contains(leaf.windowID) {
            if !(allowSkipping && settings.minimizeOverflow), let original = originals[leaf.windowID], system.isAlive(original.0), windows.contains(where: { $0.id == leaf.windowID }) { plan.append(original) }
        }
        for (window, _) in plan where minimizedByBento[window.id] != nil {
            try system.setMinimized(window, false)
            minimizedByBento.removeValue(forKey: window.id)
        }
        // Capture all rollback rectangles before the first mutation. Never replace the
        // pre-activation snapshot during reflows or settings changes.
        var rollback: [(ManagedWindow, Rect)] = []
        for (window, _) in plan {
            guard let frame = system.frame(of: window.element) else { throw WindowFailure.unavailable(window.title) }
            rollback.append((window, frame))
            if originals[window.id] == nil { originals[window.id] = (window, frame) }
        }
        do {
            if allowSkipping && !animate {
                // Validate the incoming/shrinking windows first at their final size.
                // A refusal stops this transaction before moving unrelated neighbors.
                let priorityIDs = reopenedWindows
                let frames = Dictionary(uniqueKeysWithValues: rollback.map { ($0.0.id, $0.1) })
                let ordered = plan.enumerated().sorted {
                    func rank(_ entry: (ManagedWindow, Rect)) -> Int {
                        if priorityIDs.contains(entry.0.id) { return 0 }
                        let frame = frames[entry.0.id] ?? entry.0.frame
                        return entry.1.width < frame.width || entry.1.height < frame.height ? 1 : 2
                    }
                    let a = rank($0.element), b = rank($1.element)
                    return a == b ? $0.offset < $1.offset : a < b
                }.map(\.element)
                for entry in ordered {
                    // Validation tolerates AX rounding, but an intentional 1 pt
                    // spacing edit still needs a write at its exact target.
                    if system.frame(of: entry.0.element) == entry.1 { continue }
                    try write(entry.0, frame: entry.1)
                    await settle([entry], retry: false)
                    try validate([entry], allowSkipping: true)
                }
            } else { try await move(plan, animated: animate && !liveResize, write: write) }
            if liveResize && interacting {
                // Coalesce pointer samples at display cadence. Mouse-up performs the
                // full settled verification and rolls back if an app refused a size.
                try await Task.sleep(for: .milliseconds(16))
                return
            }
            await settle(plan)
            try validate(plan, allowSkipping: allowSkipping)
        } catch {
            for (window, frame) in rollback where system.isAlive(window) && !system.accepted(window, frame) {
                try? system.write(window, frame: frame)
            }
            await settle(rollback)
            let failed = rollback.filter { system.isAlive($0.0) && !system.accepted($0.0, $0.1) }.count
            if failed > 0 { throw NSError(domain: "Bento", code: 1, userInfo: [NSLocalizedDescriptionKey: "\(error.localizedDescription) \(failed) window(s) could not be restored."]) }
            throw error
        }
    }
    private func validate(_ plan: [(ManagedWindow, Rect)], allowSkipping: Bool) throws {
        let rejected = plan.filter { !system.accepted($0.0, $0.1) }
        if CommandLine.arguments.contains("--fixture-pid") {
            for (window, wanted) in rejected { print("Rejected fixture bounds: \(window.title), wanted=\(wanted), actual=\(String(describing: system.frame(of: window.element)))") }
        }
        for (window, wanted) in rejected { trace?("native frame rejected window=\(window.id) wanted=\(wanted) actual=\(String(describing: system.frame(of: window.element)))") }
        var constrained = Set<String>()
        for (window, wanted) in rejected {
            guard let actual = system.frame(of: window.element) else { continue }
            if actual.width > wanted.width + 2 || actual.height > wanted.height + 2 {
                if actual.width > wanted.width + 2 { window.minimum.width = max(window.minimum.width, actual.width) }
                if actual.height > wanted.height + 2 { window.minimum.height = max(window.minimum.height, actual.height) }
                constrained.insert(window.application)
            }
        }
        if !constrained.isEmpty { throw WindowFailure.minimumSize(constrained.sorted().joined(separator: ", ")) }
        if let first = rejected.first {
            if allowSkipping { throw ArrangementFailure.window(first.0.id) }
            throw WindowFailure.rejected(first.0.title)
        }
    }
    private func settle(_ plan: [(ManagedWindow, Rect)], retry: Bool = true) async {
        // AX writes may return before a remote app finishes its native animation.
        // Wait for two matching samples and retry the exact target once after the
        // intermediate writes have drained. Never learn minima from a moving frame.
        var matchingSamples = 0
        let started = ProcessInfo.processInfo.systemUptime
        var retried = false
        while !Task.isCancelled {
            try? await Task.sleep(for: .milliseconds(50))
            let pending = plan.filter { system.isAlive($0.0) && !system.accepted($0.0, $0.1) }
            matchingSamples = pending.isEmpty ? matchingSamples + 1 : 0
            if matchingSamples >= 2 { return }
            let elapsed = ProcessInfo.processInfo.systemUptime - started
            if elapsed >= 1 { return }
            if retry && elapsed >= 0.35 && !retried {
                retried = true
                for (window, target) in pending { try? system.write(window, frame: target) }
            }
        }
    }
    private func move(_ plan: [(ManagedWindow, Rect)], animated: Bool,
                      write: (ManagedWindow, Rect) throws -> Void) async throws {
        let changes = plan.compactMap { window, target -> (ManagedWindow, Rect, Rect)? in
            guard let start = system.frame(of: window.element), start != target else { return nil }
            return (window, start, target)
        }
        if animated && settings.animate && !reduceMotion() {
            let start = ProcessInfo.processInfo.systemUptime
            let duration = Double(settings.animationMS) / 1000
            // One shared clock; slow AX clients skip stale frames instead of queuing
            // per-window animations. Interactive grip samples are never animated twice.
            while true {
                let progress = (ProcessInfo.processInfo.systemUptime - start) / duration
                if progress >= 1 { break }
                for (window, from, to) in changes {
                    let frame = WindowMotion.frame(from: from, to: to, progress: progress)
                    // An intermediate AX sample can be refused while an app is
                    // laying out. Only the final target determines success.
                    if !system.accepted(window, frame) { try? write(window, frame) }
                }
                try await Task.sleep(for: .milliseconds(16))
            }
        }
        for (window, _, to) in changes { try write(window, to) }
    }
    func restore() async {
        activateAfterPermission = false
        activationGeneration += 1
        if interacting { await cancelInteraction?() }
        while busy { try? await Task.sleep(for: .milliseconds(50)) }
        busy = true; defer { busy = false }
        if active {
            lastBento = history.current
            let tiled = Set(history.current.windows.map(\.windowID))
            lastReleased = released.union(windows.map(\.id).filter { !tiled.contains($0) && minimizedByBento[$0] == nil })
            lastMinimized = Set(minimizedByBento.keys)
        }
        var remaining: [UUID: (ManagedWindow, Rect)] = [:]
        let pending = originals.filter { system.isAlive($0.value.0) }
        try? await move(Array(pending.values), animated: true) { window, frame in
            try? self.system.write(window, frame: frame)
        }
        await settle(Array(pending.values))
        for (id, entry) in pending where system.isAlive(entry.0) && !system.accepted(entry.0, entry.1) { remaining[id] = entry }
        let minimizedFailures = await restoreMinimized()
        originals = remaining; appliedDesktopOptions = [:]; released.removeAll(); reopenedWindows.removeAll(); active = false; history = LayoutHistory()
        message = remaining.isEmpty && minimizedFailures == 0 ? nil : system.trusted
            ? "\(remaining.count + minimizedFailures) window(s) could not return to their original size or position. Try Restore again after checking the app and display."
            : WindowFailure.permission.localizedDescription
        onStateChange?()
        do { try desktopPreferences.restore() } catch { message = error.localizedDescription }
    }
    func saveLayout(quiet: Bool = false) {
        guard active else { message = "Arrange windows before saving a layout."; return }
        let matches = Dictionary(uniqueKeysWithValues: windows.map { ($0.id, SavedWorkspace.Match(bundleID: $0.bundleID, title: $0.title)) })
        do {
            try FileManager.default.createDirectory(at: MacSettings.directory, withIntermediateDirectories: true)
            try JSONEncoder().encode(SavedWorkspace(version: 1, platform: "macOS", workspace: history.current, applications: matches)).write(to: SavedWorkspace.url, options: .atomic)
            if !quiet { message = "Bento layout saved on this Mac." }
        } catch { message = error.localizedDescription }
    }
    func releaseActiveWindow() async {
        guard active, !busy, !interacting, !activating else { return }
        guard let window = system.focusedWindow(in: windows) else { message = "Focus the window you want to release, then right-click Bento."; return }
        let next = history.current.removing(window.id)
        do {
            try await apply(next, displays: DisplayArea.all(margin: layoutMargin))
            released.insert(window.id); history.commit(next)
            message = "Window released. Arrange all windows to include it again."; onStateChange?()
        } catch { message = error.localizedDescription }
    }
    func loadLayout() async {
        guard !busy, !interacting, !activating else { return }
        activating = true; defer { activating = false }
        let wasActive = active, generation = activationGeneration
        do {
            let saved = try JSONDecoder().decode(SavedWorkspace.self, from: Data(contentsOf: SavedWorkspace.url))
            guard saved.version == 1, saved.platform == "macOS" else { throw LayoutError.invalidInput }
            windows = try system.discover(); var available = windows
            func remap(_ node: LayoutNode, depth: Int = 0) throws -> LayoutNode? {
                guard depth < 64 else { throw LayoutError.invalidInput }
                switch node {
                case .window(let leaf):
                    guard let match = saved.applications[leaf.windowID] else { return nil }
                    let exact = available.firstIndex { $0.bundleID == match.bundleID && $0.title == match.title }
                    guard let index = exact ?? available.firstIndex(where: { $0.bundleID == match.bundleID }) else { return nil }
                    return .window(available.remove(at: index).leaf)
                case let .split(id, axis, ratio, first, second):
                    guard ratio.isFinite && ratio > 0 && ratio < 1 else { throw LayoutError.invalidInput }
                    let a = try remap(first, depth: depth + 1), b = try remap(second, depth: depth + 1)
                    guard let a else { return b }; guard let b else { return a }
                    return .split(id: id, axis: axis, ratio: ratio, first: a, second: b)
                }
            }
            if !wasActive {
                for window in windows where originals[window.id] == nil { originals[window.id] = (window, window.frame) }
                try activateDesktop(); try await Task.sleep(for: .milliseconds(500))
            }
            guard generation == activationGeneration else { return }
            let displays = DisplayArea.all(margin: layoutMargin); var next = Workspace()
            for display in displays { if let root = saved.workspace.roots[display.id] { next.roots[display.id] = try remap(root) } }
            guard !next.windows.isEmpty else {
                if !wasActive { try desktopPreferences.restore() }
                message = "No saved windows match this display setup. Open the saved applications or arrange a new layout."; return
            }
            try await apply(next, displays: displays)
            guard generation == activationGeneration else { return }
            lastDisplays = displays; history.commit(next); active = true; onStateChange?(); message = "Saved layout restored. Unmatched windows remain floating."
        } catch {
            message = "Could not restore saved layout: \(error.localizedDescription)"
            if !wasActive { do { try desktopPreferences.restore() } catch { message = "\(message ?? "") \(error.localizedDescription)" } }
        }
    }
    func undo(redo: Bool = false) async {
        guard !busy, !interacting, !activating else { return }
        activating = true; defer { activating = false }
        let wasActive = active, generation = activationGeneration
        var candidate = history; let next = redo ? candidate.redo() : candidate.undo()
        do {
            windows = try system.discover()
            if !wasActive && !next.windows.isEmpty { try activateDesktop(); try await Task.sleep(for: .milliseconds(500)) }
            guard generation == activationGeneration else { return }
            try await apply(next, displays: DisplayArea.all(margin: layoutMargin))
            guard generation == activationGeneration else { return }
            let nextIDs = Set(next.windows.map(\.windowID))
            released.subtract(nextIDs)
            released.formUnion(history.current.windows.map(\.windowID).filter { !nextIDs.contains($0) })
            history = candidate; active = !next.windows.isEmpty
            if !active { try desktopPreferences.restore() }
            onStateChange?()
        } catch { message = error.localizedDescription; if !wasActive { try? desktopPreferences.restore() } }
    }
    func recoverDesktopPreferences() { do { try desktopPreferences.restore() } catch { message = error.localizedDescription } }
    func rememberOriginal(_ window: ManagedWindow, frame: Rect) {
        if originals[window.id] == nil { originals[window.id] = (window, frame) }
    }
    func finishInteraction(_ workspace: Workspace, commit: Bool, animate: Bool = true) async throws {
        var resolved = workspace.reconciled(with: windows.map(\.leaf))
        let displays = DisplayArea.all(margin: layoutMargin)
        do { try await apply(resolved, displays: displays, animate: animate) }
        catch WindowFailure.minimumSize {
            // One correction of this exact split tree using the native constraint.
            // Never invoke automatic arrangement during a user's gesture.
            resolved = workspace.reconciled(with: windows.map(\.leaf))
            try await apply(resolved, displays: displays, animate: false)
        }
        if commit {
            released.subtract(resolved.windows.map(\.windowID))
            history.commit(resolved); message = nil
            trace?("interaction history committed windows=\(resolved.windows.count)")
        }
    }
}
