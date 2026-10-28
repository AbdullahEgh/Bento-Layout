import AppKit
import ApplicationServices
import SwiftUI
import BentoCore

struct MacSettings: Codable {
    var gap = 8; var margin = 8; var splitHold = 900; var theme = "System"
    var onboardingComplete = false
    var hideDock = false; var hideMenuBar = false; var edgeSnapping = "Keep"
    var shortcut = ShortcutConfig()
    var backgroundDarkness = 50
    var minimizeOverflow = true
    var animate = true; var animationMS = 140
    init() {}
    enum CodingKeys: String, CodingKey { case minimizeOverflow, gap, margin, splitHold, theme, onboardingComplete, edgeSnapping, shortcut, backgroundDarkness, animate, animationMS }
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        minimizeOverflow = try values.decodeIfPresent(Bool.self, forKey: .minimizeOverflow) ?? true
        gap = try values.decodeIfPresent(Int.self, forKey: .gap) ?? 8
        margin = try values.decodeIfPresent(Int.self, forKey: .margin) ?? 8
        splitHold = try values.decodeIfPresent(Int.self, forKey: .splitHold) ?? 900
        theme = try values.decodeIfPresent(String.self, forKey: .theme) ?? "System"
        onboardingComplete = try values.decodeIfPresent(Bool.self, forKey: .onboardingComplete) ?? false
        // Dock and menu-bar overrides start off in every new app session.
        edgeSnapping = try values.decodeIfPresent(String.self, forKey: .edgeSnapping) ?? "Keep"
        shortcut = try values.decodeIfPresent(ShortcutConfig.self, forKey: .shortcut) ?? ShortcutConfig()
        backgroundDarkness = try values.decodeIfPresent(Int.self, forKey: .backgroundDarkness) ?? 50
        animate = try values.decodeIfPresent(Bool.self, forKey: .animate) ?? true
        animationMS = try values.decodeIfPresent(Int.self, forKey: .animationMS) ?? 140
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
    @Published private(set) var savedSessionLayout: Workspace?
    @Published var active = false
    @Published private(set) var pinned = false
    private var pinnedWindowIDs = Set<UUID>()
    private(set) var pausedFocusID: UUID?
    func canArrangeWindow(_ id: UUID) -> Bool { !pinned || pinnedWindowIDs.contains(id) }
    private var pinRequest = 0
    func setPinned(_ value: Bool) async {
        pinRequest += 1
        let request = pinRequest
        while busy || interacting || activating || switchingDesktop {
            try? await Task.sleep(for: .milliseconds(20))
            guard request == pinRequest else { return }
        }
        guard request == pinRequest, desktopIsCurrent() else { return }
        if value && !active { await arrange(resuming: lastBento != nil) }
        guard active, pinned != value else { return }
        if !value {
            activating = true
            let generation = activationGeneration
            defer {
                activating = false
                onStateChange?()
            }
            // Native edits during Pause are temporary. Restore the saved tree
            // before admitting interaction again; never derive it from moved frames.
            do {
                for id in pinnedWindowIDs {
                    if let window = originals[id]?.0, system.isAlive(window), system.isMinimized(window) {
                        try system.setMinimized(window, false)
                    }
                }
                try await settleDesktopSpace()
                let retained = pinnedWindowIDs.compactMap { originals[$0]?.0 }.filter { system.isAlive($0) }
                for _ in 0..<40 {
                    if retained.allSatisfy({ !system.isMinimized($0) }) && !system.hasMissingVisibleWindows(retained) { break }
                    guard generation == activationGeneration, desktopIsCurrent(), !shuttingDown else { throw LayoutError.invalidInput }
                    try await Task.sleep(for: .milliseconds(30))
                }
                guard retained.allSatisfy({ !system.isMinimized($0) }) && !system.hasMissingVisibleWindows(retained) else { throw WindowFailure.workAreaChanged }
                windows = try discoverWindows()
                for window in retained where !windows.contains(where: { $0.id == window.id }) { windows.append(window) }
                let members = windows.filter { pinnedWindowIDs.contains($0.id) }
                let areas = displayAreas()
                let restored = history.current.reconciled(with: members.map(\.leaf))
                try await apply(restored, displays: areas, learnMinimum: false)
                history.commit(restored); lastDisplays = areas
                pendingDrift = nil; driftSamples = 0
                failedAutomaticInput = nil
            } catch {
                message = "Could not resume the saved layout. \(error.localizedDescription)"
                onStateChange?(); return
            }
            // Return to the pinned workspace, not a newly generated layout.
            for window in (try? system.discover()) ?? [] where WindowParticipation.allows(window.bundleID) && !pinnedWindowIDs.contains(window.id) {
                do { try system.setMinimized(window, true); minimizedByBento[window.id] = window }
                catch { message = "Some floating windows could not be minimized." }
                reopenedWindows.remove(window.id)
            }
        }
        pausedFocusID = nil
        if value {
            settledValidationTask?.cancel()
            pendingDrift = nil; driftSamples = 0
            // Establish the focus baseline before the status menu closes. Restoring
            // that same focus must not uncover a window in a freshly paused layout.
            lastFocusedWindow = system.focusedWindow(in: windows)?.id ?? lastFocusedWindow
            pendingApplicationActivation = nil
        }
        pinned = value
        pinnedWindowIDs = value ? Set(history.current.windows.map(\.windowID)) : []
        onStateChange?()
    }
    private(set) var sessionSuspended = false
    private var unlockAreas: [DisplayArea] = []
    private var unlockSamples = 0
    private var unlockReadySince: Double?
    func setSessionLocked(_ locked: Bool) {
        unlockAreas = []; unlockSamples = 0; unlockReadySince = nil
        if locked {
            sessionSuspended = true
            activationGeneration += 1
            settledValidationTask?.cancel()
            pendingMembership = nil; membershipSamples = 0
            pendingDrift = nil; driftSamples = 0
        }
        onStateChange?()
    }
    private func recoverUnlockedSession() {
        // Sleep can lose or reorder the distributed unlock notification. Read
        // the console session instead of leaving the notification latch set forever.
        guard let session = CGSessionCopyCurrentDictionary() as? [String: Any],
              session[kCGSessionOnConsoleKey as String] as? Bool == true,
              session["CGSSessionScreenIsLocked"] as? Bool != true else {
            unlockReadySince = nil; return
        }
        // Reconnect/recheck Dock observation before considering its cached
        // Mission Control flag; an AXExposeExit may have been lost during sleep.
        onStateChange?()
        guard !busy, !activating, !interacting, !switchingDesktop,
              !desktopOverviewActive, system.desktopSpaceReady(),
              let identity = system.desktopIdentity else { return }
        let areas = displayAreas()
        guard !areas.isEmpty else { return }
        if areas == unlockAreas { unlockSamples += 1 }
        else { unlockAreas = areas; unlockSamples = 1 }
        guard unlockSamples >= 3 else { return }
        // A lock screen is not another Bento desktop, and temporarily absent
        // windows must never be interpreted as removals or manual resizing.
        let now = ProcessInfo.processInfo.systemUptime
        if unlockReadySince == nil { unlockReadySince = now }
        if identity == currentDesktop, active {
            // Refresh server window numbers after WindowServer/display recreation.
            // Keep membership and the saved split tree; do not admit new apps here.
            if let discovered = try? system.discover() {
                let refreshed = Dictionary(uniqueKeysWithValues: discovered.map { ($0.id, $0) })
                windows = windows.map { refreshed[$0.id] ?? $0 }
            }
            let members = Set(history.current.windows.map(\.windowID))
            let expected = windows.filter { members.contains($0.id) && !system.isMinimized($0) && system.isAlive($0) }
            if system.hasMissingVisibleWindows(expected), now - (unlockReadySince ?? now) < 2 { return }
            // A stale server number or hidden app must not disable every grip
            // indefinitely. Restore the saved layout, then let normal membership
            // reconciliation handle genuinely closed/minimized windows.
        }
        sessionSuspended = false
        pendingMembership = nil; membershipSamples = 0
        pendingDrift = nil; driftSamples = 0
        guard identity == currentDesktop, active, !pinned else { onStateChange?(); return }
        reconciliationQueued = true
        let saved = history.current
        Task { @MainActor [weak self] in
            guard let self else { return }
            defer { self.reconciliationQueued = false; self.onStateChange?() }
            do {
                try await self.apply(saved, displays: areas, animate: false, learnMinimum: false)
                self.lastDisplays = areas
            } catch { self.message = error.localizedDescription }
        }
    }
    var desktopOverviewActive = false
    private(set) var shuttingDown = false
    @Published var busy = false
    @Published var interacting = false
    private let organizingOverlay = OrganizingOverlay()
    @Published var activating = false
    var insertingOverflow = false
    @Published var windows: [ManagedWindow] = []
    @Published var message: String?
    @Published var page = "Workspace"
    private(set) var history = LayoutHistory()
    private var originals: [UUID: (ManagedWindow, Rect)] = [:]
    private(set) var minimizedByBento: [UUID: ManagedWindow] = [:]
    private(set) var waitingForInsertion = Set<UUID>()
    private(set) var waitingDismissalGeneration = 0
    private var refusedWaitingSlots: [UUID: [Rect]] = [:]
    func allowsWaitingInsertion(_ id: UUID, into bounds: Rect) -> Bool { !(refusedWaitingSlots[id]?.contains(bounds) ?? false) }
    private var reopenedWindows = Set<UUID>()
    private var floatingForSize = Set<UUID>()
    private var interactionSequence = 0
    private var lastInteraction: [UUID: Int] = [:]
    private var lastFocusedWindow: UUID?
    private var pendingApplicationActivation: pid_t?

    func recordInteraction(_ window: ManagedWindow) {
        interactionSequence += 1
        lastInteraction[window.id] = interactionSequence
        lastFocusedWindow = window.id
        if pinned && pausedFocusID != window.id {
            pausedFocusID = window.id
            onStateChange?()
        }
    }
    func applicationActivated(_ pid: pid_t) {
        guard !activating else { return }
        guard system.isLayoutApplication(pid) else { pendingApplicationActivation = nil; return }
        lastMembershipScan = 0
        pendingApplicationActivation = pid
        if let current = try? system.discover() { observeFocus(in: current) }
    }
    private func observeFocus(in current: [ManagedWindow]) {
        let focused = system.focusedWindow(in: current)
        // Dock activation can precede AXFocusedWindow or arrive during a resize.
        // Retain the latest app's intent until its focused window is available
        // and the current transaction has finished; polling consumes it once.
        let activation = focused.map { $0.pid == pendingApplicationActivation } == true
            && !busy && !interacting && !activating
        if activation { pendingApplicationActivation = nil }
        if let focused, focused.id != lastFocusedWindow || activation {
            if !(pinned && pausedFocusID == nil && focused.id == lastFocusedWindow) {
                recordInteraction(focused)
            }
            // Bringing an already-visible floating app forward is admission intent,
            // even when its window identity and frame have not changed. Consume
            // that intent once; a permanently oversized app must not cause a loop.
            if active, canArrangeWindow(focused.id), !released.contains(focused.id),
               !history.current.windows.contains(where: { $0.windowID == focused.id }) {
                reopenedWindows.insert(focused.id)
                failedAutomaticInput = nil
            }
        }
        if let focused { lastFocusedWindow = focused.id }
    }
    private struct ArrangementInput: Equatable {
        let ids: [UUID]
        let minima: [Size]
        let frames: [Rect]
        let displays: [DisplayArea]
        let gap: Int
        func sameConstraints(as other: ArrangementInput) -> Bool {
            ids == other.ids && minima == other.minima && displays == other.displays && gap == other.gap
        }
    }
    private var failedAutomaticInput: ArrangementInput?
    private var pendingMembership: Set<UUID>?
    private var membershipSamples = 0
    private var reconciliationQueued = false
    private var pendingDrift: [Rect]?
    private var driftSamples = 0
    private func arrangementInput(_ current: [ManagedWindow], areas: [DisplayArea]? = nil) -> ArrangementInput {
        let ordered = current.sorted { $0.id.uuidString < $1.id.uuidString }
        return ArrangementInput(ids: ordered.map(\.id), minima: ordered.map(\.minimum), frames: ordered.map(\.frame),
            displays: areas ?? displayAreas(), gap: layoutGap)
    }
    private struct DesktopSession {
        var active: Bool
        var history: LayoutHistory
        var windows: [ManagedWindow]
        var originals: [UUID: (ManagedWindow, Rect)]
        var minimized: [UUID: ManagedWindow]
        var waiting: Set<UUID>
        var released: Set<UUID>
        var floating: Set<UUID>
        var saved: Workspace?
        var remembered: Workspace?
        var areaLayout: Workspace?
        var areaLayoutAreas: [DisplayArea]
        var lastReleased: Set<UUID>
        var lastMinimized: Set<UUID>
        var edited: Bool
        var pinned: Bool
        var pinnedIDs: Set<UUID>
        var displays: [DisplayArea]
        var hideDock: Bool
        var hideMenu: Bool
        var fullScreenLayout: Workspace?
        var fullScreenWindows: [UUID: ManagedWindow]
    }
    private var fullScreenLayout: Workspace?
    private var fullScreenWindows: [UUID: ManagedWindow] = [:]
    private func reserveFullScreenSlots() {
        fullScreenWindows = fullScreenWindows.filter { system.isAlive($0.value) }
        if fullScreenWindows.isEmpty { fullScreenLayout = nil }
        for window in windows where history.current.windows.contains(where: { $0.windowID == window.id }) && system.isFullScreen(window) {
            if fullScreenLayout == nil { fullScreenLayout = history.current }
            fullScreenWindows[window.id] = window
        }
    }
    private var desktopSessions: [String: DesktopSession] = [:]
    private var currentDesktop: String?
    @Published private(set) var switchingDesktop = false
    private var desktopSwitchTask: Task<Void, Never>?
    func desktopDidChange() async {
        guard !shuttingDown, !sessionSuspended, !switchingDesktop else { return }
        // Duplicate Space notifications must not cancel an in-flight layout.
        if let identity = system.desktopIdentity, identity == currentDesktop { return }
        switchingDesktop = true
        defer { switchingDesktop = false; onStateChange?() }
        // Invalidate stale validation/reflow work before any other desktop writes.
        settledValidationTask?.cancel(); activationGeneration += 1
        if interacting { await cancelInteraction?() }
        while busy || activating { try? await Task.sleep(for: .milliseconds(20)) }
        guard let identity = system.desktopIdentity else {
            message = "Bento is waiting for this desktop to become available."; return
        }
        guard identity != currentDesktop else { return }
        reserveFullScreenSlots()
        if let currentDesktop {
            desktopSessions[currentDesktop] = DesktopSession(active: active, history: history, windows: windows,
                originals: originals, minimized: minimizedByBento, waiting: waitingForInsertion, released: released, floating: floatingForSize,
                saved: savedSessionLayout, remembered: lastBento, areaLayout: areaLayout, areaLayoutAreas: areaLayoutAreas, lastReleased: lastReleased, lastMinimized: lastMinimized,
                edited: editedLayout, pinned: pinned, pinnedIDs: pinnedWindowIDs, displays: lastDisplays,
                hideDock: settings.hideDock, hideMenu: settings.hideMenuBar,
                fullScreenLayout: fullScreenLayout, fullScreenWindows: fullScreenWindows)
        }
        currentDesktop = identity
        let session = desktopSessions[identity]
        fullScreenLayout = session?.fullScreenLayout; fullScreenWindows = session?.fullScreenWindows ?? [:]
        active = session?.active ?? false; history = session?.history ?? LayoutHistory()
        windows = session?.windows ?? []; originals = session?.originals ?? [:]
        waitingForInsertion = session?.waiting ?? []
        minimizedByBento = session?.minimized ?? [:]; released = session?.released ?? []
        floatingForSize = session?.floating ?? []; savedSessionLayout = session?.saved
        lastBento = session?.remembered; areaLayout = session?.areaLayout; areaLayoutAreas = session?.areaLayoutAreas ?? []; lastReleased = session?.lastReleased ?? []
        lastMinimized = session?.lastMinimized ?? []; editedLayout = session?.edited ?? false
        pausedFocusID = nil; pinned = session?.pinned ?? false; pinnedWindowIDs = session?.pinnedIDs ?? []
        lastDisplays = session?.displays ?? []; settings.hideDock = session?.hideDock ?? false
        settings.hideMenuBar = session?.hideMenu ?? false
        reopenedWindows = []; failedAutomaticInput = nil; pendingMembership = nil; membershipSamples = 0
        pendingDrift = nil; driftSamples = 0; lastFocusedWindow = nil; pendingApplicationActivation = nil
        lastMembershipScan = 0; message = nil
        // Full-screen Spaces own Dock/menu presentation. Keep the preference
        // journal for the return to a regular desktop instead of showing Dock.
        if system.fullScreenSpace {
            active = false; windows = []
            trace?("fullscreen space: desktop overrides deferred")
            return
        }
        do {
            let desired = active ? try settings.desktopOverrides() : [:]
            try desktopPreferences.update(desired); appliedDesktopOptions = desired
            if active {
                try await settleDesktopSpace()
                await arrange(preserving: true, automatic: true)
            } else { windows = try system.discover() }
            trace?("desktop session restored active=\(active) pinned=\(pinned) windows=\(history.current.windows.count)")
        } catch { message = error.localizedDescription }
    }
    func desktopIsCurrent() -> Bool {
        guard !sessionSuspended else { return false }
        guard let identity = system.desktopIdentity else { return !backgroundMonitoring }
        return identity == currentDesktop
    }
    private let backgroundMonitoring: Bool
    private var lastMembershipScan = 0.0
    private var settledValidationTask: Task<Void, Never>?
    private var activationObserver: NSObjectProtocol?
    private var timer: Timer?
    private var lastDisplays: [DisplayArea] = []
    private var released = Set<UUID>()
    private var editedLayout = false
    private var lastBento: Workspace?
    private var areaLayout: Workspace?
    private var areaLayoutAreas: [DisplayArea] = []
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
        self.backgroundMonitoring = backgroundMonitoring
        self.reduceMotion = reduceMotion
        self.persistSettings = persistSettings
        self.system = system ?? MacWindowSystem()
        self.desktopPreferences = preferences ?? ActivationOverrides(backend: DesktopPreferenceBackend(), journal: MacSettings.directory.appendingPathComponent("desktop-preferences-session.json"))
        if let settings { self.settings = settings }
        layoutGap = self.settings.gap; layoutMargin = self.settings.margin
        appliedMinimizeOverflow = self.settings.minimizeOverflow
        permission = self.system.trusted
        currentDesktop = self.system.desktopIdentity
        if backgroundMonitoring {
            timer = Timer.scheduledTimer(withTimeInterval: 0.15, repeats: true) { [weak self] _ in Task { @MainActor in self?.tick() } }
            activationObserver = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] notification in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
                    // Keep recent-use history while off, and retain Dock intent
                    // when the app has not exposed its focused AX window yet.
                    self.applicationActivated(app.processIdentifier)
                }
            }
        }
    }
    func displayAreas() -> [DisplayArea] { system.displayAreas(margin: layoutMargin) }
    func refreshInteractionConstraints() {
        // Read-only native evidence; never probe-resize while grabbing a seam.
        for window in windows {
            if let minimum = system.reportedMinimum(window.element) { window.updateReportedMinimum(minimum) }
            if let frame = system.frame(of: window.element) { window.reconcileObservedMinimum(frame) }
        }
        failedAutomaticInput = nil
    }
    /// Preview the geometry actually committed to windows, not transient Dock/menu
    /// reveal bounds. Arrangement updates this snapshot only after a successful fit.
    func interactionAreas() -> [DisplayArea] {
        active && !lastDisplays.isEmpty ? lastDisplays : displayAreas()
    }

    /// Native apps can finish their own mouse-up animation after AX first settles.
    /// Repair the committed rectangles once, never reinterpret that rebound as a
    /// request to rebuild the split tree. A newer interaction invalidates this task.
    func scheduleSettledValidation(force: Bool = false) {
        settledValidationTask?.cancel()
        guard backgroundMonitoring || force, active, !pinned else { return }
        let committed = history.current, generation = activationGeneration, areas = displayAreas()
        settledValidationTask = Task { @MainActor [weak self] in
            do { try await Task.sleep(for: .milliseconds(320)) } catch { return }
            guard let self, !Task.isCancelled, self.active, !self.pinned, self.activationGeneration == generation,
                  self.history.current == committed, self.displayAreas() == areas,
                  !self.busy, !self.activating, !self.interacting, !self.system.pointerPressed else { return }
            var drift = false
            for area in areas {
                for region in (try? LayoutEngine.calculate(committed.roots[area.id], in: area.bounds, gap: self.layoutGap).regions) ?? [] {
                    guard let window = self.windows.first(where: { $0.id == region.window.windowID }), self.system.isAlive(window) else { return }
                    if !self.system.accepted(window, region.bounds) { drift = true }
                }
            }
            guard drift else { return }
            self.trace?("late native rebound; restoring committed slots once")
            do { try await self.apply(committed, displays: areas, animate: false, learnMinimum: false) }
            catch { self.message = error.localizedDescription }
        }
    }
    private func activateDesktop() throws {
        layoutGap = settings.gap; layoutMargin = settings.margin
        let desired = try settings.desktopOverrides()
        try desktopPreferences.activate(desired); appliedDesktopOptions = desired
        appliedMinimizeOverflow = settings.minimizeOverflow
    }
    private func settleDesktopSpace() async throws {
        // A preference write is not proof that the host has applied its work area.
        // Observe a stable native area while the restarted host comes back; keep
        // polling bounded and never probe application windows for desktop geometry.
        guard backgroundMonitoring else { return }
        let started = ProcessInfo.processInfo.systemUptime
        var previous = displayAreas()
        var stableSince = started
        repeat {
            try await Task.sleep(for: .milliseconds(40))
            let current = displayAreas()
            if current != previous { stableSince = ProcessInfo.processInfo.systemUptime }
            previous = current
            let hostsReady = !NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock").isEmpty
                && !NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.controlcenter").isEmpty
            // Dock can pause at an intermediate reservation for multiple samples.
            // Require a quiet interval and allow its slide to finish before the
            // first app transaction, rather than correcting a visible first fit.
            let now = ProcessInfo.processInfo.systemUptime
            if now - started >= 0.35 && now - stableSince >= 0.16 && hostsReady && system.desktopSpaceReady() { return }
        } while ProcessInfo.processInfo.systemUptime - started < 2
        throw WindowFailure.workAreaChanged
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
                try? await Task.sleep(for: .milliseconds(60))
                if revision != self.settingsRevision { continue }
                while self.busy || self.interacting || self.activating || self.switchingDesktop || self.desktopPointerPressed {
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
        guard !shuttingDown, !system.fullScreenSpace else { return }
        guard !busy, !interacting, !activating, !switchingDesktop, desktopIsCurrent(), !desktopPointerPressed else { scheduleSettingsUpdate(); return }
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
                    try await settleDesktopSpace()
                    while desktopPointerPressed { try await Task.sleep(for: .milliseconds(50)) }
                } catch { activating = false; appliedDesktopOptions = [:]; throw error }
                guard active else { return }
            }
            let overflowChanged = appliedMinimizeOverflow != settings.minimizeOverflow
            if overflowChanged && !settings.minimizeOverflow {
                let restoredIDs = Set(minimizedByBento.keys)
                _ = await restoreMinimized()
                windows = try discoverWindows()
                // A settings-driven restoration is not a user reopening an app.
                reopenedWindows.subtract(restoredIDs)
            }
            guard active, generation == activationGeneration else { return }
            appliedMinimizeOverflow = settings.minimizeOverflow
            let geometryChanged = oldGap != settings.gap || oldMargin != settings.margin
            let requestedGap = settings.gap, requestedMargin = settings.margin
            layoutGap = requestedGap; layoutMargin = requestedMargin
            if pinned { return } // Keep paused native edits untouched; Resume uses these settings and the settled area.
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
        if sessionSuspended { recoverUnlockedSession(); return }
        guard !shuttingDown else { return }
        if desktopOverviewActive {
            // Poll the Dock observer even while layout work is suspended: a
            // missing ExposeExit must not disable interaction for the session.
            onStateChange?()
            guard !desktopOverviewActive else { return }
        }
        refreshPermissionStatus()
        if !desktopIsCurrent() {
            if desktopSwitchTask == nil {
                desktopSwitchTask = Task { [weak self] in
                    guard let self else { return }
                    await self.desktopDidChange(); self.desktopSwitchTask = nil
                }
            }
            return
        }
        guard !system.fullScreenSpace, !switchingDesktop, permission, !busy, !interacting, !activating, !reconciliationQueued, !system.pointerPressed else { return }
        if active {
            do {
                let displaysChanged = displayAreas() != lastDisplays
                let now = ProcessInfo.processInfo.systemUptime
                if backgroundMonitoring && !displaysChanged {
                    let members = Set(history.current.windows.map(\.windowID))
                    let missingVisible = system.hasMissingVisibleWindows(windows.filter { members.contains($0.id) && minimizedByBento[$0.id] == nil })
                    let interval = pendingMembership != nil || missingVisible ? 0.12 : 0.9
                    if now - lastMembershipScan < interval { return }
                }
                lastMembershipScan = now
                let current = try discoverWindows()
                if pinned {
                    windows = current
                    pendingDrift = nil; driftSamples = 0
                    onStateChange?()
                    return
                }
                let currentIDs = Set(current.map(\.id))
                let missing = windows.filter { !currentIDs.contains($0.id) && system.isAlive($0) && !system.isMinimized($0) }
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
                    return !NativeFrameFit.accepts(frame, in: wanted)
                }.sorted { $0.id.uuidString < $1.id.uuidString }.map(\.frame)
                if !drift.isEmpty && !displaysChanged {
                    if pendingDrift == drift { driftSamples += 1 } else { pendingDrift = drift; driftSamples = 1 }
                } else { pendingDrift = nil; driftSamples = 0 }
                if !reopenedWindows.isEmpty || displaysChanged || driftSamples >= 2 || Set(current.map(\.id)) != Set(windows.map(\.id)) {
                    guard !reopenedWindows.isEmpty || failedAutomaticInput?.sameConstraints(as: arrangementInput(current)) != true else { return }
                    reconciliationQueued = true
                    Task {
                        defer { self.reconciliationQueued = false }
                        // Recheck at execution: the user may have started a drag
                        // after discovery queued this reconciliation.
                        guard !self.system.pointerPressed, !self.interacting, !self.pinned else { return }
                        await self.arrange(preserving: true, automatic: true)
                    }
                }
            } catch { message = error.localizedDescription }
        }
    }
    private func discoverWindows() throws -> [ManagedWindow] {
        var visible = try system.discover().filter { WindowParticipation.allows($0.bundleID) }
        if active && desktopIsCurrent() {
            let found = Set(visible.map(\.id))
            let managed = Set(history.current.windows.map(\.windowID))
            for window in windows where WindowParticipation.allows(window.bundleID) && managed.contains(window.id) && !found.contains(window.id)
                && system.canRetainDuringInterruption(window) {
                if let frame = system.frame(of: window.element) { window.frame = frame; visible.append(window) }
            }
        }
        let visibleIDs = Set(visible.map(\.id))
        if active {
            // Includes newly launched, manually restored and unhidden windows,
            // even when Bento did not own their earlier minimization.
            reopenedWindows.formUnion(visibleIDs.subtracting(Set(windows.map(\.id))).filter { canArrangeWindow($0) })
        }
        observeFocus(in: visible)
        let restoredWaiting = waitingForInsertion.intersection(visibleIDs).filter { id in
            minimizedByBento[id].map { !system.isMinimized($0) } == true
        }
        if !restoredWaiting.isEmpty && !interacting { waitingDismissalGeneration += 1 }
        waitingForInsertion.subtract(restoredWaiting)
        for (id, window) in minimizedByBento {
            guard system.isAlive(window) else { minimizedByBento.removeValue(forKey: id); continue }
            if visibleIDs.contains(id) && !system.isMinimized(window) {
                reopenedWindows.insert(id); minimizedByBento.removeValue(forKey: id)
            }
            // Keep ownership for explicit restoration, but never add a Dock
            // window to the visible candidates used by arrangement or polling.
        }
        return visible
    }
    private func minimizeOverflow(included: Set<UUID>, current: [ManagedWindow]) {
        guard settings.minimizeOverflow else { return }
        for window in current where canArrangeWindow(window.id) && !included.contains(window.id) && minimizedByBento[window.id] == nil && !floatingForSize.contains(window.id) {
            // Only own minimizations made by Bento, never those made before activation.
            guard !system.isMinimized(window) else { continue }
            do { try system.setMinimized(window, true); minimizedByBento[window.id] = window; waitingForInsertion.insert(window.id) }
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
        waitingForInsertion.formIntersection(Set(minimizedByBento.keys))
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
        guard desktopIsCurrent(), !switchingDesktop else {
            Task { await desktopDidChange() }; return
        }
        permission = system.trusted
        guard permission else { return }
        do { windows = try discoverWindows(); message = windows.isEmpty ? "Open an application window to begin." : nil }
        catch { message = error.localizedDescription }
    }
    func toggle() { Task { await toggleLayout() } }
    func toggleLayout() async {
        guard await ensureCurrentDesktop() else { message = "Bento is waiting for this desktop to become available."; onStateChange?(); return }
        if active { await stop() } else { await arrange(resuming: lastBento != nil) }
    }
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
        guard !pinned, !shuttingDown, !system.fullScreenSpace, !desktopOverviewActive, !busy, !interacting, !activating, desktopIsCurrent() else {
            if !automatic { trace?("arrangement deferred paused=\(pinned) shutdown=\(shuttingDown) fullScreen=\(system.fullScreenSpace) overview=\(desktopOverviewActive) busy=\(busy) interacting=\(interacting) activating=\(activating) currentDesktop=\(desktopIsCurrent())") }
            return false
        }
        if automatic && system.pointerPressed { return false }
        activating = true; defer { activating = false; onStateChange?() }
        let previousWindows = windows
        let generation = activationGeneration
        let wasActive = active
        let showOrganizing = backgroundMonitoring && !automatic && (!wasActive || !preserving)
        if showOrganizing { await organizingOverlay.show() }
        defer { if showOrganizing { organizingOverlay.hide() } }
        guard generation == activationGeneration, desktopIsCurrent(), !shuttingDown else { return false }
        var attemptedInput: ArrangementInput?
        var activationRollback: [(ManagedWindow, Rect)] = []
        var activationAreas: [DisplayArea] = []
        var preparation: ActivationPreparation?
        defer { preparation?.cancel() }
        trace?("arrangement start preserving=\(preserving) resuming=\(resuming) active=\(wasActive)")
        do {
            if !preserving { released = resuming ? lastReleased : []; refusedWaitingSlots.removeAll() }
            reserveFullScreenSlots()
            var current = try discoverWindows().filter { !system.isMinimized($0) }; windows = current
            let returningFullScreen = Set(current.filter { fullScreenWindows[$0.id] != nil && !system.isFullScreen($0) }.map(\.id))
            guard !current.isEmpty else {
                if preserving && wasActive {
                    // An empty visible workspace is a normal minimize/full-screen
                    // transition. Keep monitoring, but forget its stale membership
                    // so returning windows are admitted even at identical frames.
                    windows = []; history.commit(Workspace())
                    reopenedWindows.removeAll(); failedAutomaticInput = nil
                    pendingMembership = nil; membershipSamples = 0
                    message = nil; onStateChange?(); return true
                }
                message = "Open an application window to begin."; return false
            }
            if !wasActive {
                try activateDesktop(); try await settleDesktopSpace()
                // Native limits and frames captured before a shell transition can
                // be stale. Plan only from the settled desktop's fresh snapshot.
                current = try discoverWindows().filter { !system.isMinimized($0) }; windows = current
            }
            let displays = displayAreas()
            if !wasActive {
                activationAreas = displays
                activationRollback = try current.map { window in
                    guard let frame = system.frame(of: window.element) else { throw WindowFailure.unavailable(window.title) }
                    return (window, frame)
                }
            }
            if !wasActive && system.supportsHiddenPreparation {
                for (window, frame) in activationRollback where !released.contains(window.id) { rememberOriginal(window, frame: frame) }
                let stage = ActivationPreparation(system: system)
                preparation = stage
                let recentFirst = current.filter { !released.contains($0.id) }.sorted {
                    (lastInteraction[$0.id] ?? 0) > (lastInteraction[$1.id] ?? 0)
                }
                try await stage.prepare(recentFirst) {
                    generation == self.activationGeneration && self.desktopIsCurrent() && self.displayAreas() == displays
                }
            }
            let areaChanged = preserving && displays != lastDisplays
            if !preserving { areaLayout = nil }
            if areaChanged && areaLayout == nil { areaLayout = history.current; areaLayoutAreas = lastDisplays }
            let previous = !returningFullScreen.isEmpty && preserving ? fullScreenLayout ?? history.current
                : preserving ? (areaChanged ? areaLayout ?? history.current : history.current)
                : resuming ? lastBento ?? Workspace() : Workspace()
            if resuming, lastBento != nil, preparation == nil {
                // Resume the edited tree itself. Native frames have just been restored
                // to pre-Bento positions and cannot determine saved display ownership.
                let next = previous.reconciled(with: current.map(\.leaf))
                let rememberedIDs = Set(next.windows.map(\.windowID))
                let newlyAvailable = current.contains {
                    !rememberedIDs.contains($0.id) && !released.contains($0.id) && !lastMinimized.contains($0.id)
                }
                let rememberedFits = !rememberedIDs.isEmpty && !newlyAvailable && next.roots.allSatisfy { id, root in
                    guard let area = displays.first(where: { $0.id == id }) else { return false }
                    return (try? LayoutEngine.calculate(root, in: area.bounds, gap: layoutGap)) != nil
                }
                if rememberedFits {
                    do {
                        try await apply(next, displays: displays)
                        for window in current where lastMinimized.contains(window.id) && !next.windows.contains(where: { $0.windowID == window.id }) {
                            try? system.setMinimized(window, true)
                            if system.isMinimized(window) { minimizedByBento[window.id] = window }
                        }
                        guard generation == activationGeneration else { return false }
                        history.commit(next); lastDisplays = displays; reopenedWindows.removeAll()
                        active = !next.windows.isEmpty || !minimizedByBento.isEmpty
                        if !active { try desktopPreferences.restore() }
                        message = nil; scheduleSettledValidation(); trace?("saved arrangement resumed without automatic placement")
                        onStateChange?(); return true
                    } catch WindowFailure.minimumSize {
                        trace?("remembered layout needs updated native size constraints")
                    }
                }
            }
            // Production activation measures hidden native constraints first and
            // applies one final plan. Existing desktop reflows retain bounded recovery.
            let attemptLimit = preparation == nil ? 2 : current.count + 1
            var excluded = preparation?.excluded ?? Set<UUID>()
            for attempt in 0...attemptLimit {
                guard generation == activationGeneration else { return false }
                var next = Workspace()
                var usesSizePreference = false
                for area in displays {
                    let members = current.filter { window in
                        guard canArrangeWindow(window.id), !released.contains(window.id), !excluded.contains(window.id) else { return false }
                        // A geometry repair is not a request to readmit quiet
                        // overflow. Wait for new space, an explicit arrangement,
                        // or the user restoring that app from the Dock.
                        if preserving,
                           minimizedByBento[window.id] != nil, !reopenedWindows.contains(window.id),
                           !(areaChanged && previous.windows.contains { $0.windowID == window.id }) { return false }
                        let savedDisplay = previous.roots.first { $0.value.windows.contains { $0.windowID == window.id } }?.key
                        let owner = savedDisplay.flatMap { id in displays.first { $0.id == id } } ?? display(for: window, displays: displays)
                        return owner?.id == area.id
                    }
                    let oldestFirst = members.enumerated().sorted {
                        // Already minimized overflow gives up space before visible apps.
                        let a = minimizedByBento[$0.element.id] != nil ? -1 : lastInteraction[$0.element.id] ?? 0
                        let b = minimizedByBento[$1.element.id] != nil ? -1 : lastInteraction[$1.element.id] ?? 0
                        return a == b ? $0.offset > $1.offset : a < b
                    }.map { $0.element.id }
                    let focused = system.focusedWindow(in: members)
                    let recentFocus = members.first { $0.id == lastFocusedWindow }
                    let primary = focused ?? recentFocus ?? members.first
                    var priority = reopenedWindows
                    if priority.isEmpty, let primary { priority.insert(primary.id) }
                    if previous.roots[area.id] == nil {
                        let rank = Dictionary(uniqueKeysWithValues: oldestFirst.enumerated().map { ($0.element, $0.offset) })
                        let recent = members.sorted { (rank[$0.id] ?? 0) > (rank[$1.id] ?? 0) }
                        let leaves = recent.map(\.leaf)
                        let base = try AutoLayout.activating(leaves, in: area.bounds, gap: layoutGap)
                        next.roots[area.id] = base
                        var preferredGroup = leaves
                        for index in recent.indices {
                            let native = originals[recent[index].id]?.1 ?? recent[index].frame
                            preferredGroup[index].minimum.width = max(preferredGroup[index].minimum.width, native.width)
                            preferredGroup[index].minimum.height = max(preferredGroup[index].minimum.height, native.height)
                        }
                        let selectedIDs = Set((base?.windows ?? []).map(\.windowID))
                        if let candidate = try AutoLayout.activating(preferredGroup, in: area.bounds, gap: layoutGap),
                           Set(candidate.windows.map(\.windowID)) == selectedIDs {
                            next.roots[area.id] = candidate; usesSizePreference = true
                        } else if let first = recent.first {
                            // Accepted dimensions are independent preferences.
                            // A wide old frame must not block a useful tall pane.
                            // Try both axes, then each alone, without losing apps.
                            let native = originals[first.id]?.1 ?? first.frame
                            let hints = [Size(native.width, native.height), Size(first.minimum.width, native.height), Size(native.width, first.minimum.height)]
                            let selected = Set((base?.windows ?? []).map(\.windowID))
                            for hint in hints {
                                var preferred = leaves
                                preferred[0].minimum.width = max(preferred[0].minimum.width, hint.width)
                                preferred[0].minimum.height = max(preferred[0].minimum.height, hint.height)
                                if let candidate = try AutoLayout.activating(preferred, in: area.bounds, gap: layoutGap),
                                   Set(candidate.windows.map(\.windowID)) == selected {
                                    next.roots[area.id] = candidate; usesSizePreference = true; break
                                }
                            }
                        }
                    } else if areaChanged, let reference = previous.roots[area.id],
                              Set(reference.windows.map(\.windowID)) == Set(members.map(\.id)) {
                        // A work-area change is a projection of the same layout,
                        // never an admission request. Do not rebuild or evict when
                        // an app temporarily refuses the returning Dock's bounds.
                        let retained = Workspace(roots: [area.id: reference]).reconciled(with: members.map(\.leaf))
                        guard let root = retained.roots[area.id] else { throw LayoutError.missingTarget }
                        _ = try LayoutEngine.calculate(root, in: area.bounds, gap: layoutGap)
                        next.roots[area.id] = root
                    } else {
                        next.roots[area.id] = try AutoLayout.fitting(members.map(\.leaf), in: area.bounds, gap: layoutGap, preserving: previous.roots[area.id], prioritizing: priority, leastRecentlyUsed: oldestFirst)
                    }
                }
                if usesSizePreference {
                    for area in displays {
                        if let root = next.roots[area.id] {
                            next.roots[area.id] = try LayoutEngine.measuredRatios(root, in: area.bounds, gap: layoutGap)
                        }
                    }
                    next = next.reconciled(with: current.map(\.leaf))
                }
                if areaChanged {
                    for area in displays {
                        if let root = next.roots[area.id], let reference = previous.roots[area.id],
                           let old = areaLayoutAreas.first(where: { $0.id == area.id }),
                           Set(root.windows.map(\.windowID)) == Set(reference.windows.map(\.windowID)),
                           let joined = try? LayoutReflow.preservingSeams(root, reference: reference, from: old.bounds, to: area.bounds, gap: layoutGap) {
                            next.roots[area.id] = joined
                        }
                    }
                }
                if automatic && system.pointerPressed {
                    windows = previousWindows; trace?("automatic arrangement deferred: pointer pressed during discovery")
                    return false
                }
                attemptedInput = arrangementInput(current, areas: displays)
                // One coordinated transition for normal actions; corrections are
                // bounded final-frame transactions, never repeated visible probing.
                do { try await apply(next, displays: displays, allowSkipping: true, animate: attempt == 0 && preparation == nil, validateIndividually: wasActive, learnMinimum: !areaChanged, retainForReplan: !wasActive && attempt < attemptLimit, retrySettling: true, retryExactTarget: preparation != nil) }
                catch ArrangementFailure.window(let id) where attempt < attemptLimit && (attempt == 0 || preparation != nil) && skipRefusingWindows && !areaChanged {
                    trace?("native slot refusal excluded under organizing cover=\(preparation != nil)")
                    excluded.insert(id); continue
                }
                catch WindowFailure.minimumSize where attempt < attemptLimit {
                    // Fresh activation validates the whole batch, so one app's
                    // refusal does not postpone learning the others' axis limits.
                    trace?("native axis limits updated; bounded correction=\(attempt + 1)")
                    continue
                }
                guard generation == activationGeneration else { return false }
                if preparation == nil && !pinned && displays == lastDisplays { next = await alignNativeSeams(next, displays: displays) }
                let included = Set(next.windows.map(\.windowID))
                // Keep originals for overflow minimized in place. Floating exclusions
                // are forgotten so restoration cannot undo later user movement.
                let currentIDs = Set(current.map(\.id))
                floatingForSize = floatingForSize.intersection(currentIDs).union(excluded).subtracting(included)
                for window in current where reopenedWindows.contains(window.id) && !included.contains(window.id) {
                    if let area = display(for: window, displays: displays),
                       window.minimum.width > area.bounds.width || window.minimum.height > area.bounds.height || excluded.contains(window.id) {
                        floatingForSize.insert(window.id)
                    }
                }
                originals = originals.filter { (!floatingForSize.contains($0.key) || (preparation != nil && settings.minimizeOverflow)) && (included.contains($0.key) || !currentIDs.contains($0.key) || settings.minimizeOverflow) }
                if !wasActive {
                    // A rejected size may have moved a window which the final
                    // plan leaves outside. Restore only those discarded probes.
                    for (window, frame) in activationRollback where !included.contains(window.id) && system.isAlive(window) && system.frame(of: window.element) != frame {
                        try? system.write(window, frame: frame)
                    }
                }
                if let stage = preparation {
                    let pendingOverflow = stage.finish(included: included, keepOverflow: settings.minimizeOverflow)
                    // Unhide and WindowServer visibility are asynchronous. Do not
                    // hand the revealed layout to membership polling until its
                    // included windows have appeared; this never resizes them.
                    let revealed = current.filter { included.contains($0.id) }
                    for _ in 0..<20 {
                        if !system.hasMissingVisibleWindows(revealed) { break }
                        try? await Task.sleep(for: .milliseconds(30))
                    }
                    // Minimize only after unhide completes: unhide can cancel a
                    // minimization requested while the application was concealed.
                    for window in pendingOverflow {
                        do {
                            try system.setMinimized(window, true)
                            minimizedByBento[window.id] = window; waitingForInsertion.insert(window.id)
                        } catch { /* Leave refused windows outside the layout. */ }
                    }
                    preparation = nil
                }
                minimizeOverflow(included: included, current: current.filter { !released.contains($0.id) })
                trace?("arrangement committed attempt=\(attempt + 1) tiled=\(included.count) overflow=\(current.count - included.count)")
                if !areaChanged && (!reopenedWindows.isEmpty || !preserving) { areaLayout = nil }
                reopenedWindows.removeAll(); failedAutomaticInput = nil
                if !preserving && !resuming { editedLayout = false }
                let committed = usesSizePreference ? next.reconciled(with: current.map(\.leaf)) : next
                for id in returningFullScreen where included.contains(id) { fullScreenWindows.removeValue(forKey: id) }
                if fullScreenWindows.isEmpty { fullScreenLayout = nil }
                lastDisplays = displays; history.commit(committed); active = !included.isEmpty || !minimizedByBento.isEmpty || (pinned && wasActive)
                if !active { try desktopPreferences.restore() }
                message = active ? (floatingForSize.isEmpty ? nil : "An app stays outside Bento because it could not be arranged on this display.") : "No windows fit on this display. Your windows were left in their original positions."
                scheduleSettledValidation(); onStateChange?(); return active
            }
        } catch {
            // Failed activation has one recovery boundary, not a rollback/replay
            // between each newly learned constraint. Never write on another Space.
            if !wasActive, generation == activationGeneration, desktopIsCurrent(), displayAreas() == activationAreas {
                let recovery = activationRollback.filter { system.isAlive($0.0) && system.frame(of: $0.0.element) != $0.1 }
                try? await move(recovery, animated: false) { window, frame in try self.system.write(window, frame: frame) }
            }
            trace?("arrangement stopped error=\(String(reflecting: type(of: error)))")
            // Cache only the area actually attempted. A Dock/display change
            // during an AX transaction must remain eligible for a fresh plan.
            failedAutomaticInput = attemptedInput ?? arrangementInput(windows)
            let areaChanged = attemptedInput.map { $0.displays != displayAreas() } ?? false
            if !areaChanged { reopenedWindows.removeAll() }
            message = wasActive && areaChanged ? nil : error.localizedDescription
            if areaChanged { trace?("desktop area changed during transaction; new input remains eligible") }
            if !wasActive { do { try desktopPreferences.restore() } catch { message = "\(message ?? "") \(error.localizedDescription)" } }
        }
        return false
    }
    func apply(_ workspace: Workspace, displays: [DisplayArea], allowSkipping: Bool = false, liveResize: Bool = false, animate: Bool = true, validateIndividually: Bool = true, returning: Bool = false, learnMinimum: Bool = true, retainForReplan: Bool = false, retrySettling: Bool = true, retryExactTarget: Bool = false) async throws {
        guard !busy, desktopIsCurrent() else { throw LayoutError.invalidInput }; busy = true; defer { busy = false }
        guard displayAreas() == displays else { throw WindowFailure.workAreaChanged }
        let restoreAXMode = system.beginFrameAdjustment(windows)
        defer { restoreAXMode() }
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
            if originals[window.id] == nil { originals[window.id] = desktopSessions.values.compactMap { $0.originals[window.id] }.first ?? (window, frame) }
        }
        do {
            if allowSkipping && !animate && validateIndividually {
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
                    await settle([entry], displays: displays)
                    guard displayAreas() == displays else { throw WindowFailure.workAreaChanged }
                    try validate([entry], allowSkipping: true, learnMinimum: learnMinimum)
                }
            } else { try await move(plan, animated: animate && !liveResize, returning: returning, write: write) }
            if liveResize && interacting {
                // Coalesce pointer samples at display cadence. Mouse-up performs the
                // full settled verification and rolls back if an app refused a size.
                await Task.yield()
                return
            }
            await settle(plan, retry: retrySettling, displays: displays, retryExactTarget: retryExactTarget)
            guard displayAreas() == displays else { throw WindowFailure.workAreaChanged }
            try validate(plan, allowSkipping: allowSkipping, learnMinimum: learnMinimum)
        } catch {
            if retainForReplan, case WindowFailure.minimumSize = error,
               desktopIsCurrent(), displayAreas() == displays {
                // The whole batch has already learned every observed refused axis.
                // Leave accepted frames in place for the next calculated plan.
                // The activation owner restores its original snapshot on failure.
                throw error
            }
            // Never roll old desktop windows into the newly visible desktop.
            guard desktopIsCurrent(), displayAreas() == displays else { throw WindowFailure.workAreaChanged }
            let recovery = rollback.filter { system.isAlive($0.0) }
            try? await move(recovery, animated: animate && !liveResize, returning: true) { window, frame in
                try? self.system.write(window, frame: frame)
            }
            await settle(rollback)
            let failed = rollback.filter { system.isAlive($0.0) && !system.accepted($0.0, $0.1) }.count
            if failed > 0 {
                trace?("rollback incomplete windows=\(failed); preserving original failure for bounded correction")
                // A restored frame may itself violate a newly learned minimum.
                // Keep the typed failure so admission can replan using that limit.
                if !allowSkipping {
                    throw NSError(domain: "Bento", code: 1, userInfo: [NSLocalizedDescriptionKey: "\(error.localizedDescription) \(failed) window(s) could not be restored."])
                }
            }
            throw error
        }
    }
    private func alignNativeSeams(_ workspace: Workspace, displays: [DisplayArea], affectedWindows: Set<UUID>? = nil) async -> Workspace {
        func frames() -> [UUID: Rect] {
            Dictionary(uniqueKeysWithValues: windows.compactMap { window in
                system.frame(of: window.element).map { (window.id, $0) }
            })
        }
        let before = frames()
        var candidate = workspace
        var oldScore = 0
        for display in displays {
            guard let root = workspace.roots[display.id] else { continue }
            let score = NativeSeamAlignment.score(root, area: display.bounds, gap: layoutGap, frames: before)
            guard score != Int.max else { return workspace }
            oldScore += score
            if let aligned = NativeSeamAlignment.proposal(root, area: display.bounds, gap: layoutGap, frames: before, affectedWindows: affectedWindows) {
                candidate.roots[display.id] = aligned
            }
        }
        guard candidate != workspace else { return workspace }
        do {
            try await apply(candidate, displays: displays, animate: false)
            let after = frames()
            var score = 0
            for display in displays {
                guard let root = candidate.roots[display.id] else { continue }
                let value = NativeSeamAlignment.score(root, area: display.bounds, gap: layoutGap, frames: after)
                guard value != Int.max else { throw LayoutError.invalidInput }
                score += value
            }
            if score < oldScore { trace?("native divider alignment reclaimed=\(oldScore - score) points"); return candidate }
        } catch { trace?("native divider alignment retained previous geometry") }
        // One verified proposal, at most one rollback. Never chase cell rounding.
        try? await apply(workspace, displays: displays, animate: false)
        return workspace
    }
    private func validate(_ plan: [(ManagedWindow, Rect)], allowSkipping: Bool, learnMinimum: Bool = true) throws {
        // Use one settled snapshot per window for acceptance, diagnostics and
        // size learning. Repeated AX reads can disagree and are slow on busy apps.
        var frames: [UUID: Rect] = [:]
        let rejected = plan.filter { window, wanted in
            guard let actual = system.frame(of: window.element) else { return true }
            frames[window.id] = actual
            return !NativeFrameFit.accepts(actual, in: wanted)
        }
        if CommandLine.arguments.contains("--fixture-pid") {
            for (window, wanted) in rejected { print("Rejected fixture bounds: \(window.title), wanted=\(wanted), actual=\(String(describing: frames[window.id]))") }
        }
        for (window, wanted) in rejected { trace?("native frame rejected window=\(window.id) wanted=\(wanted) actual=\(String(describing: frames[window.id]))") }
        // A displaced origin indicates positioning/desktop transition failure,
        // not proof of a minimum size. Do not poison any app limits in this batch.
        if let misplaced = rejected.first(where: { window, wanted in
            guard let actual = frames[window.id] else { return false }
            return abs(actual.x - wanted.x) > 2 || abs(actual.y - wanted.y) > 2
        }) { throw WindowFailure.rejected(misplaced.0.title) }
        var constrained = Set<String>()
        for (window, wanted) in rejected {
            guard let actual = frames[window.id] else { continue }
            let widthClamped = actual.width > wanted.width + 2
            let heightClamped = abs(actual.y - wanted.y) <= 2 && actual.height > wanted.height + 2
            if learnMinimum && (widthClamped || heightClamped) {
                // A clamp proves a minimum only on that axis. The accepted
                // other dimension is not a permanent limit.
                if widthClamped { window.learnMinimum(width: actual.width) }
                if heightClamped { window.learnMinimum(height: actual.height) }
                constrained.insert(window.application)
            }
        }
        if !constrained.isEmpty { throw WindowFailure.minimumSize(constrained.sorted().joined(separator: ", ")) }
        if let first = rejected.first {
            if allowSkipping { throw ArrangementFailure.window(first.0.id) }
            throw WindowFailure.rejected(first.0.title)
        }
    }
    private func settle(_ plan: [(ManagedWindow, Rect)], retry: Bool = true, displays: [DisplayArea]? = nil, retryExactTarget: Bool = false) async {
        // AX writes may return before a remote app finishes its native animation.
        // Wait for two accepted samples and retry a contained target once after the
        // intermediate writes have drained. Never learn minima from a moving frame.
        var matchingSamples = 0
        let started = ProcessInfo.processInfo.systemUptime
        var retried = false
        while !Task.isCancelled {
            guard desktopIsCurrent(), displays == nil || displays == displayAreas() else { return }
            let frames = Dictionary(uniqueKeysWithValues: plan.compactMap { window, _ in
                system.frame(of: window.element).map { (window.id, $0) }
            })
            let pending = plan.filter { window, target in
                system.isAlive(window) && frames[window.id].map { !NativeFrameFit.accepts($0, in: target) } != false
            }
            matchingSamples = pending.isEmpty ? matchingSamples + 1 : 0
            if matchingSamples >= 2 { return }
            try? await Task.sleep(for: .milliseconds(30))
            let elapsed = ProcessInfo.processInfo.systemUptime - started
            if elapsed >= 1 { return }
            if retry && elapsed >= 0.35 && !retried {
                retried = true
                for (window, target) in pending {
                    guard let actual = frames[window.id] else { continue }
                    let fitted = NativeFrameFit.inwardTarget(actual: actual, slot: target)
                    // Never repeat the target an app has already refused. Only
                    // a different inward target can solve whole-cell rounding.
                    if fitted != target || retryExactTarget { try? system.write(window, frame: fitted) }
                }
            }
        }
    }
    private func move(_ plan: [(ManagedWindow, Rect)], animated: Bool, returning: Bool = false,
                      write: (ManagedWindow, Rect) throws -> Void) async throws {
        let changes = plan.compactMap { window, target -> (ManagedWindow, Rect, Rect)? in
            guard let start = system.frame(of: window.element), start != target else { return nil }
            return (window, start, target)
        }
        guard !changes.isEmpty else { return }
        if animated && settings.animate && !reduceMotion() {
            let duration = max(returning ? 0.32 : 0, Double(settings.animationMS) / 1000)
            if !changes.isEmpty { trace?("motion batch started windows=\(changes.count) durationMS=\(Int(duration * 1000)) returning=\(returning)") }
            let start = ProcessInfo.processInfo.systemUptime
            // Each app has one in-flight sample and a common deadline. A busy
            // process cannot hold up responsive apps; missed frames are skipped,
            // not queued, and a transient timeout does not disable its animation.
            let batches = Dictionary(grouping: changes, by: { $0.0.pid })
            let tasks = batches.values.map { batch in
                Task { @MainActor in
                    var sent = Dictionary(uniqueKeysWithValues: batch.map { ($0.0.id, $0.1) })
                    var samples = 0, failures = 0
                    while !Task.isCancelled && self.desktopIsCurrent() {
                        let sampleStart = ProcessInfo.processInfo.systemUptime
                        guard sampleStart - start < duration else { break }
                        let requests = batch.compactMap { window, from, to -> MotionWrite? in
                            let previous = sent[window.id] ?? from
                            let frame = WindowMotion.frame(from: from, to: to, progress: (sampleStart - start) / duration)
                            return frame == previous ? nil : MotionWrite(window, frame: frame, previous: previous)
                        }
                        let failed = await self.system.writeMotionFrames(requests)
                        failures += failed.count
                        if !requests.isEmpty { samples += 1 }
                        for request in requests where !failed.contains(request.id) { sent[request.id] = request.frame }
                        let remaining = max(0.001, 1.0 / 60 - (ProcessInfo.processInfo.systemUptime - sampleStart))
                        try? await Task.sleep(for: .seconds(remaining))
                    }
                    return (samples, failures)
                }
            }
            var counts: [Int] = [], failures = 0
            for task in tasks { let result = await task.value; counts.append(result.0); failures += result.1 }
            trace?("motion appSamples=\(counts.sorted()) elapsedMS=\(Int((ProcessInfo.processInfo.systemUptime - start) * 1000)) failedSamples=\(failures)")
        }
        guard desktopIsCurrent() else { throw LayoutError.invalidInput }
        for (window, _, to) in changes { try write(window, to) }
    }
    private func ensureCurrentDesktop() async -> Bool {
        while switchingDesktop { try? await Task.sleep(for: .milliseconds(20)) }
        if !desktopIsCurrent() { await desktopDidChange() }
        return desktopIsCurrent()
    }
    func stop() async {
        guard await ensureCurrentDesktop() else { return }
        await deactivate(restorePositions: savedSessionLayout == nil)
    }
    func restore() async {
        guard await ensureCurrentDesktop() else { return }
        await deactivate(restorePositions: true)
    }
    private func deactivate(restorePositions: Bool) async {
        settledValidationTask?.cancel()
        activateAfterPermission = false
        activationGeneration += 1
        if interacting { await cancelInteraction?() }
        while busy { try? await Task.sleep(for: .milliseconds(50)) }
        busy = true; defer { busy = false }
        if active {
            lastBento = areaLayout ?? history.current
            // Remember intentionally floating members as well as explicit releases.
            // Hidden preparation must not readmit them when resuming the saved tree.
            let arranged = Set(history.current.windows.map(\.windowID))
            lastReleased = released.union(Set(windows.map(\.id)).subtracting(arranged).subtracting(Set(minimizedByBento.keys)))
            lastMinimized = Set(minimizedByBento.keys)
        }
        var remaining = originals
        if restorePositions {
            remaining = [:]
            let pending = originals.filter { system.isAlive($0.value.0) }
            let restoreAXMode = system.beginFrameAdjustment(pending.values.map { $0.0 })
            defer { restoreAXMode() }
            try? await move(Array(pending.values), animated: true, returning: true) { window, frame in
                try? self.system.write(window, frame: frame)
            }
            await settle(Array(pending.values))
            for (id, entry) in pending where system.isAlive(entry.0) && !system.accepted(entry.0, entry.1) { remaining[id] = entry }
        }
        let minimizedFailures = await restoreMinimized()
        originals = remaining; appliedDesktopOptions = [:]; released.removeAll(); reopenedWindows.removeAll(); floatingForSize.removeAll(); active = false; pinned = false; pinnedWindowIDs.removeAll(); history = LayoutHistory()
        let failures = (restorePositions ? remaining.count : 0) + minimizedFailures
        message = failures == 0 ? nil : system.trusted
            ? "\(failures) window(s) could not return to their original size or position. Try Restore again after checking the app and display."
            : WindowFailure.permission.localizedDescription
        onStateChange?()
        do { try desktopPreferences.restore() } catch { message = error.localizedDescription }
    }
    func beginShutdownKeepingWindows() {
        shuttingDown = true; activationGeneration += 1
        timer?.invalidate(); timer = nil
        settingsTask?.cancel(); settledValidationTask?.cancel()
        activateAfterPermission = false
    }
    func resumeAfterShutdownFailure() {
        shuttingDown = false
        if backgroundMonitoring && timer == nil {
            timer = Timer.scheduledTimer(withTimeInterval: 0.15, repeats: true) { [weak self] _ in Task { @MainActor in self?.tick() } }
        }
    }
    /// Quit/update is not Bento Off: never restore, resize, unminimize or move
    /// windows on this or another desktop. Only release session-owned helpers/preferences.
    func finishShutdownKeepingWindows() async {
        beginShutdownKeepingWindows()
        while busy || activating || switchingDesktop { try? await Task.sleep(for: .milliseconds(20)) }
        active = false; interacting = false; pinned = false
        originals.removeAll(); minimizedByBento.removeAll(); waitingForInsertion.removeAll(); desktopSessions.removeAll()
        fullScreenWindows.removeAll(); fullScreenLayout = nil
        appliedDesktopOptions = [:]; message = nil
        onStateChange?()
        do { try desktopPreferences.restore() } catch { message = error.localizedDescription }
    }
    func stopAllDesktops() async {
        await stop()
        var failures = 0
        var restored = Set<UUID>()
        for (key, session) in desktopSessions where key != currentDesktop {
            if session.saved == nil {
                for (id, entry) in session.originals where restored.insert(id).inserted && system.isAlive(entry.0) {
                    do { try system.write(entry.0, frame: entry.1) } catch { failures += 1 }
                }
            }
            for window in session.minimized.values where system.isAlive(window) {
                do { try system.setMinimized(window, false) } catch { failures += 1 }
            }
        }
        desktopSessions.removeAll()
        if failures > 0 { message = "\(failures) window(s) on other desktops could not be restored." }
    }
    func saveLayout() {
        guard active, !busy, !interacting, !activating else { return }
        savedSessionLayout = history.current
        message = "Saved for this session. Turning Bento off keeps windows in place."
        onStateChange?()
    }
    func clearSavedLayout() {
        savedSessionLayout = nil
        message = "Session save cleared. Turning Bento off restores original window positions."
        onStateChange?()
    }
    func releaseActiveWindow() async {
        guard active, !busy, !interacting, !activating else { return }
        guard let window = system.focusedWindow(in: windows) ?? windows.first(where: { $0.id == lastFocusedWindow }) else { message = "Select an app window, then choose Stop Arranging Selected Window from Bento’s menu."; return }
        let next = history.current.removing(window.id)
        do {
            try await apply(next, displays: displayAreas())
            released.insert(window.id); areaLayout = nil; editedLayout = true; history.commit(next)
            message = "Window excluded from automatic layout. Choose Arrange All Windows to include it again."; scheduleSettledValidation(); onStateChange?()
        } catch { message = error.localizedDescription }
    }
    func loadLayout() async {
        guard !busy, !interacting, !activating else { return }
        activating = true; defer { activating = false }
        let wasActive = active, generation = activationGeneration
        do {
            guard let saved = savedSessionLayout else { message = "Save a layout during this session first."; return }
            windows = try discoverWindows()
            if !wasActive {
                for window in windows where originals[window.id] == nil { originals[window.id] = (window, window.frame) }
                try activateDesktop(); try await settleDesktopSpace()
            }
            guard generation == activationGeneration else { return }
            let displays = displayAreas()
            var next = saved.reconciled(with: windows.map(\.leaf))
            next.roots = next.roots.filter { id, _ in displays.contains { $0.id == id } }
            guard !next.windows.isEmpty else {
                if !wasActive { try desktopPreferences.restore() }
                message = "The saved windows are no longer available on these displays."; return
            }
            do { try await apply(next, displays: displays) }
            catch WindowFailure.minimumSize {
                next = next.reconciled(with: windows.map(\.leaf))
                try await apply(next, displays: displays, animate: false)
            }
            guard generation == activationGeneration else { return }
            areaLayout = nil; lastDisplays = displays; history.commit(next); active = true
            released = Set(windows.map(\.id)).subtracting(next.windows.map(\.windowID)).subtracting(minimizedByBento.keys)
            scheduleSettledValidation(); onStateChange?(); message = "Session layout restored."
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
            if !wasActive && !next.windows.isEmpty { try activateDesktop(); try await settleDesktopSpace() }
            guard generation == activationGeneration else { return }
            try await apply(next, displays: displayAreas())
            guard generation == activationGeneration else { return }
            let nextIDs = Set(next.windows.map(\.windowID))
            released.subtract(nextIDs)
            released.formUnion(history.current.windows.map(\.windowID).filter { !nextIDs.contains($0) })
            areaLayout = nil; history = candidate; active = !next.windows.isEmpty
            if !active { try desktopPreferences.restore() }
            scheduleSettledValidation(); onStateChange?()
        } catch { message = error.localizedDescription; if !wasActive { try? desktopPreferences.restore() } }
    }
    func recoverDesktopPreferences() { do { try desktopPreferences.restore() } catch { message = error.localizedDescription } }
    func rememberOriginal(_ window: ManagedWindow, frame: Rect) {
        if originals[window.id] == nil { originals[window.id] = desktopSessions.values.compactMap { $0.originals[window.id] }.first ?? (window, frame) }
    }
    /// Explicit insertion is the only path that restores a waiting Dock window.
    /// The existing workspace stays intact until both placement and displacement succeed.
    func insertOverflow(_ id: UUID, into next: Workspace, from snapshot: Workspace) async -> Bool {
        guard active, !pinned, !busy, !activating, !shuttingDown, desktopIsCurrent(),
              !desktopOverviewActive, history.current == snapshot,
              waitingForInsertion.contains(id), let source = minimizedByBento[id], system.isMinimized(source),
              next.windows.contains(where: { $0.windowID == id }) else { return false }
        let beforeWindows = windows, areas = displayAreas()
        var attemptedBounds: Rect?
        var placementStarted = false
        var placementAccepted = false
        let generation = activationGeneration
        let displaced = windows.filter { window in
            snapshot.windows.contains { $0.windowID == window.id } && !next.windows.contains { $0.windowID == window.id }
        }
        if !windows.contains(where: { $0.id == id }) { windows.append(source) }
        interacting = true
        defer { interacting = false; onStateChange?() }
        do {
            // Reject invalid geometries before restoring anything from the Dock.
            for (display, root) in next.roots {
                guard let area = areas.first(where: { $0.id == display }) else { throw LayoutError.invalidInput }
                let result = try LayoutEngine.calculate(root, in: area.bounds, gap: layoutGap)
                if let destination = result.regions.first(where: { $0.window.windowID == id }) {
                    guard allowsWaitingInsertion(id, into: destination.bounds) else { throw LayoutError.cannotFit }
                    attemptedBounds = destination.bounds
                }
            }
            try system.setMinimized(source, false)
            var ready = false
            for sample in 0..<30 {
                guard !shuttingDown, generation == activationGeneration, desktopIsCurrent(), displayAreas() == areas, system.isAlive(source) else { throw LayoutError.invalidInput }
                if sample >= 7, !system.isMinimized(source), system.frame(of: source.element) != nil,
                   !system.hasMissingVisibleWindows([source]) { ready = true; break }
                try await Task.sleep(for: .milliseconds(30))
            }
            guard ready else {
                trace?("waiting restore timeout minimized=\(system.isMinimized(source)) hidden=\(system.applicationHidden(source.pid)) missing=\(system.hasMissingVisibleWindows([source]))")
                throw WindowFailure.rejected(source.title)
            }
            minimizedByBento.removeValue(forKey: id)
            placementStarted = true
            try await apply(next, displays: areas, allowSkipping: true)
            placementAccepted = true
            guard !shuttingDown, generation == activationGeneration, desktopIsCurrent() else { throw LayoutError.invalidInput }
            for window in displaced {
                try system.setMinimized(window, true)
                for _ in 0..<30 {
                    if system.isMinimized(window) { break }
                    guard !shuttingDown, generation == activationGeneration, desktopIsCurrent() else { throw LayoutError.invalidInput }
                    try await Task.sleep(for: .milliseconds(30))
                }
                guard system.isMinimized(window) else { throw WindowFailure.rejected(window.title) }
                minimizedByBento[window.id] = window; waitingForInsertion.insert(window.id)
            }
            minimizedByBento.removeValue(forKey: id); waitingForInsertion.remove(id)
            refusedWaitingSlots.removeValue(forKey: id)
            floatingForSize.remove(id); released.remove(id)
            windows.removeAll { window in displaced.contains(where: { $0.id == window.id }) }
            history.commit(next); areaLayout = nil; lastDisplays = areas; editedLayout = true
            message = nil
            return true
        } catch {
            trace?("waiting insertion failed: \(error)")
            if !shuttingDown, generation == activationGeneration, desktopIsCurrent(), displayAreas() == areas {
                for window in displaced where system.isMinimized(window) {
                    try? system.setMinimized(window, false); minimizedByBento.removeValue(forKey: window.id); waitingForInsertion.remove(window.id)
                }
                try? await apply(snapshot, displays: areas, allowSkipping: true, animate: false)
                do {
                    try system.setMinimized(source, true)
                    // Keep ownership on accepted AX requests, before Dock publishes state.
                    minimizedByBento[id] = source; waitingForInsertion.insert(id)
                    for _ in 0..<30 {
                        if system.isMinimized(source) { break }
                        try await Task.sleep(for: .milliseconds(30))
                    }
                } catch { trace?("failed insertion could not return source to Dock") }
                if placementStarted && !placementAccepted, let bounds = attemptedBounds {
                    refusedWaitingSlots[id, default: []].append(bounds)
                }
            }
            windows = beforeWindows
            message = "This app could not fit there. Try another slot."
            return false
        }
    }
    func finishInteraction(_ workspace: Workspace, commit: Bool, animate: Bool = true) async throws {
        guard !pinned, workspace.windows.allSatisfy({ canArrangeWindow($0.windowID) }) else { throw LayoutError.invalidInput }
        var resolved = workspace.reconciled(with: windows.map(\.leaf))
        let displays = displayAreas()
        do { try await apply(resolved, displays: displays, animate: animate, returning: !commit) }
        catch WindowFailure.minimumSize {
            // One correction of this exact split tree using the native constraint.
            // Never invoke automatic arrangement during a user's gesture.
            resolved = workspace.reconciled(with: windows.map(\.leaf))
            try await apply(resolved, displays: displays, animate: false)
        }
        if commit {
            var affected = Set<UUID>()
            for display in displays {
                let old = (try? LayoutEngine.calculate(history.current.roots[display.id], in: display.bounds, gap: layoutGap).regions) ?? []
                let previous = Dictionary(uniqueKeysWithValues: old.map { ($0.window.windowID, $0.bounds) })
                for region in (try? LayoutEngine.calculate(resolved.roots[display.id], in: display.bounds, gap: layoutGap).regions) ?? [] {
                    if previous[region.window.windowID] != region.bounds { affected.insert(region.window.windowID) }
                }
            }
            resolved = await alignNativeSeams(resolved, displays: displays, affectedWindows: affected)
            released.subtract(resolved.windows.map(\.windowID))
            guard displayAreas() == displays else { throw WindowFailure.workAreaChanged }
            areaLayout = nil; lastDisplays = displays; editedLayout = true; history.commit(resolved); message = nil
            trace?("interaction history committed windows=\(resolved.windows.count)")
        }
        message = nil
        scheduleSettledValidation()
    }
}
