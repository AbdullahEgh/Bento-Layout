import AppKit
import ApplicationServices
import BentoCore

@MainActor enum DesktopSessionSmoke {
    static func run(system: FixtureWindowSystem, initial: [Rect], output: URL) async throws -> [String] {
        var passed: [String] = []
        func check(_ condition: Bool, _ label: String) throws {
            guard condition else { throw NSError(domain: "BentoDesktopSmoke", code: 1, userInfo: [NSLocalizedDescriptionKey: label]) }
            passed.append(label)
        }
        try check(DesktopIdentity.current() != nil, "The running macOS resolves a stable read-only desktop identity")
        try check(["power", "arrow.uturn.backward", "menubar.dock.rectangle", "pin", "gearshape", "xmark.circle"].allSatisfy {
            NSImage(systemSymbolName: $0, accessibilityDescription: nil) != nil
        }, "Every menu action has an available native symbol")
        for _ in 0..<20 {
            if DesktopIdentity.containsWindow(system.records[0].1.windowNumber) == true { break }
            try? await Task.sleep(for: .milliseconds(25))
        }
        try check(DesktopIdentity.containsWindow(system.records[0].1.windowNumber) == true,
            "Read-only membership resolves a native window on the current desktop")
        var settings = MacSettings(); settings.animate = false; settings.minimizeOverflow = true
        let preferences = FixturePreferences()
        let model = WorkspaceController(system: system, settings: settings,
            preferences: ActivationOverrides(backend: preferences, journal: output.appendingPathComponent("desktop-sessions.json")),
            persistSettings: { _ in }, backgroundMonitoring: false)
        await model.arrange()
        let remembered = model.history.current
        await model.stop()
        try check(system.records.map { DesktopCoordinates.engine($0.1.frame) } == initial, "Automatic layout memory restores normal frames when Bento stops")
        await model.toggleLayout()
        try check(model.history.current == remembered, "An unedited automatically remembered layout resumes without an explicit save")
        let fullScreenMember = system.records[0].0
        let beforeFullScreen = model.history.current
        system.fullScreenWindows = [fullScreenMember.id]; system.writes.removeAll()
        await model.arrange(preserving: true)
        try check(!model.history.current.windows.contains { $0.windowID == fullScreenMember.id }
            && model.history.current.windows.count == beforeFullScreen.windows.count - 1 && system.writes[fullScreenMember.id] == nil,
            "Returning to the desktop reflows visible apps while preserving a full-screen app's slot separately")
        system.fullScreenWindows.removeAll(); system.writes.removeAll()
        await model.arrange(preserving: true)
        try check(model.history.current == beforeFullScreen,
            "Exiting full screen restores the reserved slot and original split layout")
        await model.stop()
        let incoming = system.records[2].0
        system.undiscovered = [incoming.id]
        await model.arrange()
        let nativeArea = model.displayAreas()[0]
        let cellHeight = max(150, ((nativeArea.bounds.height - model.layoutGap) / 2 / 15 - 1) * 15 + 5)
        let alignmentArea = Rect(nativeArea.bounds.x, nativeArea.bounds.y, nativeArea.bounds.width, cellHeight * 2 + model.layoutGap)
        system.areaOverride = [DisplayArea(id: nativeArea.id, name: nativeArea.name, bounds: alignmentArea)]
        let first = system.records[0].0, second = system.records[1].0
        system.nativeGrid[first.id] = Size(1, 15)
        let split = LayoutNode.split(id: UUID(), axis: .vertical, ratio: 0.5, first: .window(first.leaf), second: .window(second.leaf))
        try await model.finishInteraction(Workspace(roots: [nativeArea.id: split]), commit: true)
        let firstFrame = system.frame(of: first.element)!, secondFrame = system.frame(of: second.element)!
        try check(secondFrame.y - firstFrame.bottom == model.layoutGap,
            "Cell-sized native windows align the shared divider and give spare pixels to their neighbor")
        system.nativeGrid.removeAll(); system.areaOverride = nil
        await model.arrange(preserving: true)
        system.focused = second
        let pauseInteractions = DesktopInteractions(model: model, automaticSampling: false, observeOverview: false)
        pauseInteractions.synchronize()
        try check(pauseInteractions.visibleGripCount > 0, "Active fixture exposes resize grips before Pause")
        await model.setPinned(true)
        pauseInteractions.synchronize()
        try check(pauseInteractions.visibleGripCount == 0 && system.dividerWindowNumbers.isEmpty,
            "Pause hides every grip and removes divider hit surfaces")
        try check(model.pausedFocusID == nil, "Pause starts with every Bento window dimmed")
        model.applicationActivated(second.pid)
        try check(model.pausedFocusID == nil, "Restoring the existing focus after Pause keeps every window dimmed")
        model.recordInteraction(second)
        try check(model.pausedFocusID == second.id, "The first explicit click uncovers the initially focused paused window")
        var pinRefreshes = 0
        model.onStateChange = { pinRefreshes += 1 }
        system.focused = first
        model.applicationActivated(first.pid)
        try check(pinRefreshes > 0, "Focusing a pinned app refreshes its dim layer without moving windows")
        model.onStateChange = nil; system.focused = nil
        try check(model.pausedFocusID == first.id, "The first paused app focus removes its tint immediately")
        model.recordInteraction(second)
        try check(model.pausedFocusID == second.id, "A single click switches the clear paused window without a second activation")
        let pinned = model.history.current, incomingFrame = system.frame(of: incoming.element)
        system.undiscovered.removeAll(); system.writes.removeAll()
        await model.arrange(preserving: true)
        try check(model.history.current == pinned && system.frame(of: incoming.element) == incomingFrame
            && system.writes[incoming.id] == nil && !system.isMinimized(incoming), "Pin Bento leaves newly visible apps floating without moving or minimizing them")
        try check(!model.canArrangeWindow(incoming.id), "Pin Bento excludes floating windows from drag admission")
        let savedFrames = Dictionary(uniqueKeysWithValues: [first, second].map { ($0.id, system.frame(of: $0.element)!) })
        var temporary = savedFrames[first.id]!
        temporary.x += 27; temporary.y += 19; temporary.width -= 40; temporary.height -= 25
        try system.write(first, frame: temporary)
        system.writes.removeAll()
        model.tick(); model.tick()
        await model.arrange(preserving: true)
        do {
            try await model.finishInteraction(pinned, commit: true)
            try check(false, "Paused interaction unexpectedly accepted")
        } catch LayoutError.invalidInput { }
        model.scheduleSettledValidation(force: true)
        try? await Task.sleep(for: .milliseconds(400))
        try check(model.history.current == pinned && system.writes.isEmpty && system.frame(of: first.element) == temporary,
            "Paused native size and position edits leave the saved layout and other apps untouched")
        try system.setMinimized(first, true)
        model.tick()
        try check(model.history.current == pinned, "Minimizing a paused member preserves its saved slot")
        await model.setPinned(false)
        pauseInteractions.synchronize()
        try check(!system.isMinimized(first), "Resume brings minimized paused members back to their saved slots")
        try check(pauseInteractions.visibleGripCount > 0, "Resume restores active grips")
        try check([first, second].allSatisfy { system.frame(of: $0.element) == savedFrames[$0.id] },
            "Resume restores the saved positions and sizes after temporary paused edits")
        try check(model.history.current == pinned && system.isMinimized(incoming), "Unpinning minimizes floating windows and preserves the pinned layout")
        let compactArea = model.displayAreas()[0]
        let originalTree = model.history.current
        system.areaOverride = [DisplayArea(id: compactArea.id, name: compactArea.name,
            bounds: Rect(compactArea.bounds.x, compactArea.bounds.y + 25, compactArea.bounds.width, 200))]
        await model.arrange(preserving: true)
        try check(Set(model.history.current.windows.map(\.windowID)) == Set(originalTree.windows.map(\.windowID)) && system.isMinimized(incoming),
            "A tighter work area keeps existing membership without readmitting minimized windows")
        system.areaOverride = nil
        await model.arrange(preserving: true)
        try check(model.history.current == originalTree, "Restoring usable space restores the original split ratios and membership")
        let limitsBeforeTransition = system.records.map { $0.0.minimum }
        system.areaOverride = [DisplayArea(id: compactArea.id, name: compactArea.name,
            bounds: Rect(compactArea.bounds.x, compactArea.bounds.y, compactArea.bounds.width, compactArea.bounds.height - 40))]
        system.areaChangeOnWrite = [DisplayArea(id: compactArea.id, name: compactArea.name,
            bounds: Rect(compactArea.bounds.x, compactArea.bounds.y + 30, compactArea.bounds.width, compactArea.bounds.height - 85))]
        system.nativeMinimum[first.id] = Size(compactArea.bounds.width, compactArea.bounds.height)
        await model.arrange(preserving: true)
        try check(model.history.current == originalTree && system.records.map { $0.0.minimum } == limitsBeforeTransition,
            "A work-area change during native clamping preserves the tree and does not learn false size limits")
        system.nativeMinimum.removeAll()
        await model.arrange(preserving: true)
        try check(model.history.current == originalTree,
            "The next settled work area reuses the saved split instead of replacing the layout")
        system.areaOverride = nil
        await model.arrange(preserving: true)
        // A settled display can still have an app carrying its expanded size.
        // Such refusals must not poison minima or trigger a different topology.
        let stableLimits = system.records.map { $0.0.minimum }
        let reduced = DisplayArea(id: compactArea.id, name: compactArea.name,
            bounds: Rect(compactArea.bounds.x, compactArea.bounds.y + 30, compactArea.bounds.width, compactArea.bounds.height - 90))
        for cycle in 1...2 {
            system.areaOverride = [reduced]
            system.nativeMinimum[first.id] = Size(compactArea.bounds.width, compactArea.bounds.height)
            await model.arrange(preserving: true)
            try check(model.history.current == originalTree && system.records.map { $0.0.minimum } == stableLimits,
                "Dock cycle \(cycle) refuses transient expanded sizes without learning limits or rebuilding")
            system.nativeMinimum.removeAll()
            await model.arrange(preserving: true)
            try check(model.history.current.windows.count == originalTree.windows.count && model.message == nil,
                "Dock cycle \(cycle) fits the same members after the app releases its transient size")
            system.areaOverride = nil
            await model.arrange(preserving: true)
            try check(model.history.current == originalTree,
                "Dock cycle \(cycle) restores exact saved topology and ratios")
        }
        system.undiscovered = Set(model.history.current.windows.map(\.windowID))
        await model.arrange(preserving: true)
        try check(model.history.current == originalTree, "Temporary discovery loss preserves live nonminimized layout members")
        system.undiscovered.removeAll()
        try check(model.canArrangeWindow(incoming.id), "Unpin immediately restores drag admission for floating apps")
        try system.setMinimized(incoming, false)
        system.focused = incoming
        model.applicationActivated(incoming.pid)
        await model.arrange(preserving: true)
        try check(model.history.current.windows.contains { $0.windowID == incoming.id }
            && !system.isMinimized(incoming), "An app restored after Unpin joins the active Bento layout")
        try check(model.history.current.windows.count == 3 && model.canArrangeWindow(incoming.id),
            "Restored apps and existing members all remain interactive after Unpin")
        let newlyOpened = NSWindow(contentRect: NSRect(x: 300, y: 100, width: 420, height: 320),
            styleMask: [.titled, .resizable, .closable], backing: .buffered, defer: false)
        newlyOpened.isReleasedWhenClosed = false; newlyOpened.title = "Bento post-unpin fixture"
        newlyOpened.orderFrontRegardless()
        let newRecord = ManagedWindow(element: AXUIElementCreateApplication(-1004),
            pid: ProcessInfo.processInfo.processIdentifier, title: newlyOpened.title,
            application: "Bento Fixture", bundleID: "com.abdullahegh.bento.fixture",
            frame: DesktopCoordinates.engine(newlyOpened.frame))
        system.records.append((newRecord, newlyOpened)); system.focused = newRecord
        model.applicationActivated(newRecord.pid)
        await model.arrange(preserving: true)
        try check(model.history.current.windows.contains { $0.windowID == newRecord.id }
            && model.canArrangeWindow(newRecord.id) && !system.isMinimized(newRecord),
            "A newly opened app after Unpin joins Bento without inheriting the old pin restriction")
        system.records.removeLast(); newlyOpened.close()
        system.focused = nil
        await model.arrange(preserving: true)
        system.outsideDesktop = [first.id]; system.undiscovered = [first.id]
        await model.arrange(preserving: true)
        try check(!model.history.current.windows.contains { $0.windowID == first.id },
            "A window moved to another desktop is not retained as a transient interruption")
        system.outsideDesktop.removeAll(); system.undiscovered.removeAll()
        await model.stop()
        system.undiscovered = [incoming.id]
        await model.arrange(); await model.setPinned(true)
        model.settings.hideDock = true; model.settings.hideMenuBar = true
        await model.applyLiveSettings()
        let desktopA = model.history.current
        let desktopPreferences = preferences.values
        system.fixtureDesktop = "fixture-fullscreen"; system.fixtureFullScreen = true; system.writes.removeAll()
        await model.desktopDidChange()
        try check(!model.active && preferences.values == desktopPreferences && system.writes.isEmpty,
            "Entering a full-screen Space defers Dock/menu restoration and never moves windows")
        await model.applyLiveSettings()
        let arrangedFullScreen = await model.arrange()
        try check(!arrangedFullScreen && preferences.values == desktopPreferences && system.writes.isEmpty,
            "Full-screen settings and activation leave native presentation untouched")
        system.fixtureDesktop = "fixture-main"; system.fixtureFullScreen = false
        await model.desktopDidChange()
        try check(model.active && model.pinned && model.history.current == desktopA && model.settings.hideDock && model.settings.hideMenuBar,
            "Leaving full screen resumes the original desktop layout and session visibility choices")

        system.writes.removeAll()
        await model.desktopDidChange()
        try check(model.history.current == desktopA && system.writes.isEmpty,
            "Duplicate desktop notifications do not reset history or rewrite windows")
        system.writes.removeAll(); system.fixtureDesktop = "fixture-second"
        system.undiscovered = Set(system.records.prefix(2).map { $0.0.id })
        await model.desktopDidChange()
        try check(!model.active && !model.pinned && model.history.current.windows.isEmpty && system.writes.isEmpty,
            "A new desktop starts independently without restoring or moving the previous desktop's windows")
        await model.arrange()
        try check(model.history.current.windows.map(\.windowID) == [incoming.id], "The second desktop arranges only its own visible windows")
        system.fixtureDesktop = "fixture-main"; system.undiscovered = [incoming.id]; system.writes.removeAll()
        await model.desktopDidChange()
        try check(model.active && model.pinned && model.history.current == desktopA && system.writes[incoming.id] == nil,
            "Returning to a desktop restores its own layout and Pin state without touching another desktop")
        await model.stopAllDesktops()
        system.undiscovered.removeAll()
        try check(system.records.map { DesktopCoordinates.engine($0.1.frame) } == initial, "Ending all desktop sessions restores each window's own original geometry")
        model.busy = true
        let queuedPin = Task { await model.setPinned(true) }
        await Task.yield()
        try check(!model.active && !model.pinned, "Pin waits for an in-progress transaction instead of overlapping it")
        model.busy = false
        await queuedPin.value
        try check(model.active && model.pinned, "A queued Pin request can activate Bento from off without being discarded")
        system.fixtureDesktop = "fixture-quit-second"
        await model.desktopDidChange(); await model.arrange()
        let quitFrames = system.records.map { DesktopCoordinates.engine($0.1.frame) }
        let quitMinimized = system.minimized
        system.writes.removeAll()
        model.beginShutdownKeepingWindows()
        await model.finishShutdownKeepingWindows()
        model.tick(); _ = await model.arrange()
        try check(system.writes.isEmpty && system.records.map { DesktopCoordinates.engine($0.1.frame) } == quitFrames
            && system.minimized == quitMinimized && !model.active,
            "Quit/update preserves all window frames and minimized states across desktops with no late rearrangement")
        // Clean up disposable fixtures explicitly; production shutdown never does this.
        system.fixtureDesktop = "fixture-main"
        for (index, entry) in system.records.enumerated() { try system.write(entry.0, frame: initial[index]) }
        let backdrop = DesktopBackdrop()
        backdrop.show(darkness: 90, animated: false)
        try check(backdrop.opacity == 0.9, "Black backdrop uses the requested darkness")
        backdrop.hide(animated: true)
        backdrop.show(darkness: 50, animated: false)
        try check(backdrop.opacity == 0.5, "A new backdrop appearance cancels an interrupted fade-out")
        backdrop.hide(animated: false)
        try check(backdrop.opacity == 0, "Backdrop removal completes without leaving a dark panel")
        system.hiddenPreparation = true
        system.minimized.removeAll(); system.writes.removeAll(); system.nativeMinimum.removeAll()
        for (record, _) in system.records { system.nativeMinimum[record.id] = Size(320, 240) }
        var preparationTrace: [String] = []
        let prepared = WorkspaceController(system: system, settings: settings,
            preferences: ActivationOverrides(backend: FixturePreferences(), journal: output.appendingPathComponent("prepared-activation.json")),
            persistSettings: { _ in }, backgroundMonitoring: false, trace: { preparationTrace.append($0) })
        await prepared.arrange()
        try check(prepared.active && preparationTrace.filter { $0.contains("arrangement committed attempt=1") }.count == 1
            && !preparationTrace.contains { $0.contains("bounded correction=") },
            "Hidden preparation measures native limits before committing one final activation plan")
        try check(system.records.allSatisfy { $0.0.minimum == Size(320, 240) }
            && prepared.history.current.windows.allSatisfy { !system.minimized.contains($0.windowID) },
            "Prepared members are revealed only after final placement with measured current-display limits")
        try check(system.writes.values.allSatisfy { $0 == 2 },
            "Prepared activation writes one hidden measurement and one final frame per window without fitting retries")
        await prepared.restore()
        try check(system.records.enumerated().allSatisfy { system.frame(of: $0.element.0.element) == initial[$0.offset] },
            "Hidden measurement never replaces the original frames used by Bento Off")
        let previousAreas = system.areaOverride
        let actualArea = prepared.displayAreas()[0]
        system.areaOverride = [DisplayArea(id: actualArea.id, name: actualArea.name, bounds: Rect(0, 30, 800, 600))]
        for (record, _) in system.records { system.nativeMinimum[record.id] = Size(240, 160) }
        await prepared.arrange()
        try check(prepared.active && prepared.history.current.windows.count == 3
            && system.records.allSatisfy { $0.0.minimum == Size(240, 160) },
            "Smaller remote display activation remeasures current constraints rather than reusing old accepted sizes")
        await prepared.restore()
        system.areaOverride = previousAreas
        let dockWindow = system.records[0].0
        system.minimized.insert(dockWindow.id)
        system.writes.removeAll()
        await prepared.arrange()
        try check(prepared.active && !prepared.history.current.windows.contains { $0.windowID == dockWindow.id }
            && system.minimized.contains(dockWindow.id) && system.writes[dockWindow.id] == nil,
            "Organizing only uses current desktop windows and leaves pre-minimized apps untouched")
        await prepared.arrange()
        try check(system.minimized.contains(dockWindow.id) && system.writes[dockWindow.id] == nil,
            "Arrange All does not reopen a minimized app")
        await prepared.restore()
        system.minimized.removeAll()
        system.denyMinimize = true; system.writes.removeAll()
        await prepared.arrange()
        try check(!prepared.active && system.writes.isEmpty && system.minimized.isEmpty,
            "Apps refusing hidden preparation remain untouched instead of receiving visible size trials")
        system.denyMinimize = false
        for (record, _) in system.records {
            let frame = system.frame(of: record.element)!
            system.nativeMinimum[record.id] = Size(frame.width, frame.height)
        }
        await prepared.arrange()
        try check(prepared.active && prepared.history.current.windows.isEmpty && system.minimized.count == system.records.count,
            "Unmeasurable activation windows minimize to Dock instead of remaining outside Bento")
        await prepared.restore()
        try check(system.minimized.isEmpty, "Turning Bento off restores excluded activation windows from Dock")
        let organizing = OrganizingOverlay()
        await organizing.show()
        try check(organizing.visibleCount == NSScreen.screens.count, "Organizing blur covers every connected display")
        organizing.hide(animated: false)
        try check(organizing.visibleCount == 0, "Organizing cover is removed on completion")
        system.hiddenPreparation = false; system.nativeMinimum.removeAll()
        for (record, _) in system.records { record.minimum = Size(160, 120) }
        return passed
    }
}
