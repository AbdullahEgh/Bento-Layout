import SwiftUI

struct SettingsView: View {
    @ObservedObject var model: WorkspaceController
    @ObservedObject var updater: MacUpdater
    @StateObject private var loginStartup = LoginStartup()
    @Environment(\.scenePhase) private var scenePhase
    @State private var compact = false
    private let pages = ["Workspace", "Gestures", "Updates", "What's New", "About"]
    private var rowLayout: AnyLayout { compact ? AnyLayout(VStackLayout(alignment: .leading, spacing: 10)) : AnyLayout(HStackLayout(spacing: 12)) }
    var showOnboarding: () -> Void
    var body: some View {
        GeometryReader { geometry in
          VStack(spacing: 0) {
            if compact {
                HStack(spacing: 12) {
                    Image(nsImage: BentoStyle.icon).resizable().frame(width: 28, height: 28)
                    Text("Bento").font(.headline)
                    Spacer()
                    Picker("Settings page", selection: $model.page) {
                        ForEach(pages, id: \.self) { Text($0).tag($0) }
                    }.labelsHidden().frame(maxWidth: 180)
                }.padding(.horizontal, 16).padding(.top, 24).padding(.bottom, 12).bentoGlass(radius: 18)
            }
            HStack(spacing: 0) {
            if !compact { VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 9) { Image(nsImage: BentoStyle.icon).resizable().frame(width: 36, height: 36); Text("Bento").font(.system(size: 20, weight: .semibold)) }.padding(.bottom, 28)
                ForEach(pages, id: \.self) { page in
                    Button { model.page = page } label: {
                        HStack(spacing: 10) {
                            if page == "Workspace" || page == "Gestures" { BentoSymbol(name: page, size: 17) }
                            else { Image(systemName: page == "Updates" ? "arrow.down.circle" : page == "What's New" ? "sparkles" : "info.circle").frame(width: 17) }
                            Text(page).font(.system(size: 12, weight: .medium)); Spacer()
                        }.padding(11).background(model.page == page ? BentoStyle.selection : .clear, in: RoundedRectangle(cornerRadius: 8))
                    }.buttonStyle(.plain).foregroundStyle(model.page == page ? BentoStyle.accent : BentoStyle.secondary)
                }
                Spacer()
                Text("macOS · \(updater.version)").font(.system(size: 10)).foregroundStyle(BentoStyle.secondary)
            }.padding(22).frame(width: 195).bentoGlass(radius: 18) }
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    Text(model.page).font(.system(size: 28, weight: .semibold)).tracking(-0.5)
                    switch model.page {
                    case "Workspace": workspace
                    case "Gestures": gestures
                    case "Updates": UpdatesView(updater: updater)
                    case "What's New": whatsNew
                    default: about
                    }
                    if model.page != "Workspace", let message = model.message { Text(message).font(.system(size: 12)).foregroundStyle(BentoStyle.secondary).textSelection(.enabled) }
                }.padding(compact ? 16 : 30).frame(maxWidth: .infinity, alignment: .leading)
            }
            }
          }.onAppear { compact = geometry.size.width < 680 }
           .onChange(of: geometry.size.width) { _, width in compact = width < 680 }
        }.bentoGlassContainer().frame(minWidth: 340, minHeight: 420).foregroundStyle(BentoStyle.text).background(BentoWindowSurface())

            .onChange(of: model.settings.minimizeOverflow) { _, _ in model.saveSettings() }
            .onChange(of: model.settings.gap) { _, _ in model.saveSettings() }
            .onChange(of: model.settings.margin) { _, _ in model.saveSettings() }
            .onChange(of: model.settings.splitHold) { _, _ in model.saveSettings() }
            .onChange(of: model.settings.theme) { _, _ in model.saveSettings() }
            .onChange(of: model.settings.hideDock) { _, _ in model.saveSettings() }
            .onChange(of: model.settings.hideMenuBar) { _, _ in model.saveSettings() }
            .onChange(of: model.settings.edgeSnapping) { _, _ in model.saveSettings() }
            .onChange(of: model.settings.shortcut) { _, _ in model.saveSettings() }
            .onChange(of: model.settings.backgroundDarkness) { _, _ in model.saveSettings() }
            .onChange(of: model.settings.animate) { _, _ in model.saveSettings() }
            .onChange(of: model.settings.animationMS) { _, _ in model.saveSettings() }
            .onAppear { model.refresh() }
            .onChange(of: scenePhase) { _, phase in if phase == .active { loginStartup.refresh() } }
    }
    private var workspace: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Your desktop, with a little breathing room.").font(.system(size: 13)).foregroundStyle(BentoStyle.secondary)
            BentoCard {
                VStack(alignment: .leading, spacing: 18) {
                    HStack { Circle().fill(!model.permission ? .orange : model.active ? BentoStyle.accent : BentoStyle.secondary).frame(width: 8, height: 8); Text(!model.permission ? "Accessibility access needed" : model.active ? (model.pinned ? "Bento is paused on this desktop" : "Bento is arranging this desktop") : "Bento is off on this desktop").font(.system(size: 14, weight: .medium)); Spacer() }
                    Text(model.active ? "\(model.history.current.windows.count) arranged · \(model.minimizedByBento.count) minimized · \(model.floatingWindows.count - model.minimizedByBento.count) outside layout · \(model.settings.shortcut.label)" : "\(model.windows.count) available windows · \(model.settings.shortcut.label)").font(.system(size: 12)).foregroundStyle(BentoStyle.secondary)
                    rowLayout {
                        Button {
                            if model.permission { model.toggle() }
                            else { model.system.requestPermission(); model.system.openPermissionSettings() }
                        } label: { Text(!model.permission ? "Enable Accessibility" : model.active ? "Turn Bento off" : "Arrange windows") }.buttonStyle(PrimaryButtonStyle()).disabled(model.busy)
                        Button { Task { await model.restore() } } label: { settingLabel("Restore Window Positions", symbol: "Restore") }.help("Turn Bento off and restore window positions from before it was enabled.").disabled(model.busy)
                    }
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Pause Bento").font(.system(size: 13, weight: .medium))
                            Text("New apps float above Bento. Resume minimizes them and returns to your layout.").font(.system(size: 11)).foregroundStyle(BentoStyle.secondary)
                        }
                        Spacer(minLength: 16)
                        Toggle("Pause Bento", isOn: Binding(get: { model.pinned }, set: { value in Task { await model.setPinned(value) } })).labelsHidden().toggleStyle(.switch)
                    }
                    if !model.permission { Text("In System Settings → Privacy & Security → Accessibility, enable this copy: \(Bundle.main.bundlePath). If access stays blocked after an update, remove the old Bento entry and add this app again.").font(.system(size: 11)).lineSpacing(3).foregroundStyle(BentoStyle.secondary).textSelection(.enabled) }
                    else { rowLayout { Text("Accessibility connected").foregroundStyle(BentoStyle.accent); Spacer(); Button("Refresh windows") { model.refresh() } }.font(.system(size: 11)) }
                    if let message = model.message { Text(message).font(.system(size: 12)).foregroundStyle(BentoStyle.secondary).textSelection(.enabled) }
                    if model.active && !model.floatingWindows.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Windows outside the layout").font(.system(size: 12, weight: .medium))
                            ForEach(model.floatingWindows, id: \.id) { window in
                                Text("\(window.application) — \(window.title)\(model.minimizedByBento[window.id] == nil ? "" : " · In Dock")").font(.system(size: 11)).lineLimit(2)
                            }
                            Text(model.pinned ? "Resume Bento to minimize these windows and return to your layout." : "Open a minimized window from the Dock to give it priority in the layout. Turning Bento off brings back windows minimized by Bento.").font(.system(size: 11))
                        }.foregroundStyle(BentoStyle.secondary)
                    }
                }
            }
            layoutOptions
            activationOptions
            appearanceOptions
            BentoCard {
                VStack(alignment: .leading, spacing: 14) {
                    cardHeading("General")
                    switchSetting("Start at login", symbol: "Startup", detail: "Open Bento in the menu bar when you sign in.", isOn: Binding(get: { loginStartup.enabled }, set: { loginStartup.setEnabled($0) }))
                    if loginStartup.needsApproval { Button("Approve in Login Items") { loginStartup.openSettings() } }
                    if let message = loginStartup.message { Text(message).font(.system(size: 11)).foregroundStyle(BentoStyle.secondary) }
                }
            }
            BentoCard {
                VStack(alignment: .leading, spacing: 12) {
                    cardHeading("Session layout")
                    Text(model.savedSessionLayout == nil ? "Bento remembers this desktop’s layout automatically for this session. Turning it off restores original positions; turning it on reuses the closest fitting layout. Save explicitly only to keep windows in place while off." : "Saved for this session. Turning Bento off keeps windows in place. The save clears when Bento quits.")
                        .font(.system(size: 11)).foregroundStyle(BentoStyle.secondary)
                    rowLayout {
                        Button("Save for This Session") { model.saveLayout() }.disabled(!model.active || model.busy)
                        Button("Use Saved Layout") { Task { await model.loadLayout() } }.disabled(!model.permission || model.savedSessionLayout == nil || model.busy)
                    }
                    if model.savedSessionLayout != nil { Button("Clear Session Save") { model.clearSavedLayout() }.buttonStyle(.plain).font(.system(size: 11)) }
                }
            }
            rowLayout {
                Button("Arrange All Windows") { Task { await model.arrange() } }.disabled(!model.permission || model.busy)
                Spacer(); Button("Undo") { Task { await model.undo() } }.disabled(!model.active || model.busy)
                Button("Redo") { Task { await model.undo(redo: true) } }.disabled(model.busy)
            }
        }
    }
    private var layoutOptions: some View {
        BentoCard {
            VStack(alignment: .leading, spacing: 18) {
                cardHeading("Layout & spacing", detail: "Keep windows usable as your workspace changes.")
                switchSetting("Minimize windows that do not fit", symbol: "Restore", detail: "Make room by minimizing the least recently used windows.", isOn: $model.settings.minimizeOverflow)
                Divider()
                setting("Space between windows", symbol: "Gap", value: $model.settings.gap, range: 4...32)
                setting("Desktop margin", symbol: "Margin", value: $model.settings.margin, range: 0...64)
                Text("Spacing updates live while Bento is on.").font(.system(size: 11)).foregroundStyle(BentoStyle.secondary)
            }
        }
    }
    private var activationOptions: some View {
        BentoCard {
            VStack(alignment: .leading, spacing: 18) {
                cardHeading("Desktop space", detail: "Applied automatically while Bento is on.")
                switchSetting("Hide Dock", symbol: "Dock", detail: "This session only.", isOn: $model.settings.hideDock)
                Divider()
                switchSetting("Hide Menu Bar", symbol: "MenuBar", detail: "This session only.", isOn: $model.settings.hideMenuBar)
                Divider()
                rowLayout {
                    settingLabel("macOS Window Snapping", symbol: "Snap"); Spacer()
                    Picker("macOS Window Snapping", selection: $model.settings.edgeSnapping) {
                        Text("Use macOS setting").tag("Keep"); Text("Enabled with Bento").tag("On"); Text("Disabled with Bento").tag("Off")
                    }.labelsHidden().frame(width: 175)
                }
                Text("Move to a screen edge to reveal hidden controls. Turning these options off restores your macOS preferences.").font(.system(size: 11)).lineSpacing(4).foregroundStyle(BentoStyle.secondary)
            }.font(.system(size: 12))
        }
    }
    private var appearanceOptions: some View {
        BentoCard {
            VStack(alignment: .leading, spacing: 18) {
                cardHeading("Appearance & motion")
                VStack(alignment: .leading, spacing: 10) {
                    HStack { settingLabel("Background darkness", symbol: "Darkness"); Spacer(); Text("\(model.settings.backgroundDarkness)%").monospacedDigit().foregroundStyle(BentoStyle.secondary) }
                    Slider(value: Binding(get: { Double(model.settings.backgroundDarkness) }, set: { model.settings.backgroundDarkness = Int($0) }), in: 0...100, step: 5).accessibilityLabel("Background darkness")
                }
                Divider()
                switchSetting("Smooth window transitions", symbol: "Animation", isOn: $model.settings.animate)
                if model.settings.animate { rowLayout { settingLabel("Animation duration", symbol: "Duration"); Spacer(); Stepper("\(model.settings.animationMS) ms", value: $model.settings.animationMS, in: 80...400, step: 20).frame(width: 120) } }
                Text("Motion follows macOS Reduce Motion.").font(.system(size: 11)).foregroundStyle(BentoStyle.secondary)
                Divider()
                rowLayout { settingLabel("Appearance", symbol: "Appearance"); Spacer(); Picker("Appearance", selection: $model.settings.theme) { Text("System").tag("System"); Text("Light").tag("Light"); Text("Dark").tag("Dark") }.labelsHidden().frame(width: 130) }
            }.font(.system(size: 12))
        }
    }
    private func cardHeading(_ title: String, detail: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title).font(.system(size: 14, weight: .semibold))
            if let detail { Text(detail).font(.system(size: 11)).foregroundStyle(BentoStyle.secondary) }
        }
    }
    private func switchSetting(_ title: String, symbol: String, detail: String? = nil, isOn: Binding<Bool>) -> some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 5) {
                settingLabel(title, symbol: symbol).font(.system(size: 12, weight: .medium))
                if let detail { Text(detail).font(.system(size: 11)).lineSpacing(3).foregroundStyle(BentoStyle.secondary).padding(.leading, 28) }
            }.frame(maxWidth: .infinity, alignment: .leading)
            Toggle(title, isOn: isOn).labelsHidden().toggleStyle(.switch).fixedSize()
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
    private func settingLabel(_ title: String, symbol: String) -> some View {
        HStack(spacing: 10) {
            BentoSymbol(name: symbol, size: 18).foregroundStyle(BentoStyle.secondary)
            Text(title)
        }
    }
    private func setting(_ title: String, symbol: String, value: Binding<Int>, range: ClosedRange<Int>) -> some View {
        rowLayout {
            settingLabel(title, symbol: symbol); Spacer()
            Stepper("\(value.wrappedValue) pt", value: value, in: range, step: 2).frame(width: 90)
        }
    }
    private var gestures: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Small gestures. More room to work.").foregroundStyle(BentoStyle.secondary)
            BentoCard {
                VStack(alignment: .leading, spacing: 18) {
                    HStack { BentoSymbol(name: "Keyboard"); Text("Toggle Bento"); Spacer(); Text(model.settings.shortcut.label).font(.system(.body, design: .monospaced)).foregroundStyle(BentoStyle.accent) }
                    switchSetting("Enable keyboard shortcut", symbol: "Keyboard", isOn: $model.settings.shortcut.enabled)
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 100))], alignment: .leading, spacing: 12) {
                        Toggle("Control", isOn: $model.settings.shortcut.control)
                        Toggle("Option", isOn: $model.settings.shortcut.option)
                        Toggle("Shift", isOn: $model.settings.shortcut.shift)
                        Toggle("Command", isOn: $model.settings.shortcut.command)
                        Picker("Key", selection: $model.settings.shortcut.key) { ForEach(ShortcutConfig.keys, id: \.self) { Text($0).tag($0) } }.labelsHidden().frame(width: 60)
                    }.toggleStyle(.checkbox).font(.system(size: 11)).disabled(!model.settings.shortcut.enabled)
                    Text("Choose a letter or number with at least one modifier. Click the menu-bar icon to toggle Bento; right-click for its menu.").font(.system(size: 12)).foregroundStyle(BentoStyle.secondary)
                    Divider()
                    HStack { settingLabel("Hold to split", symbol: "Gestures"); Spacer(); Stepper("\(model.settings.splitHold) ms", value: $model.settings.splitHold, in: 0...2000, step: 100).frame(width: 125) }
                    Text("Drag a real window onto another region to swap. Drag to the outer screen edge to move its whole section, keeping stacked windows together. Hold at a slot edge to split. Drag a gap grip to resize neighbors. Escape cancels and restores the committed layout.").font(.system(size: 12)).lineSpacing(4).foregroundStyle(BentoStyle.secondary)
                }
            }
        }
    }
    private var about: some View {
        VStack(alignment: .leading, spacing: 20) {
            Image(nsImage: BentoStyle.icon).resizable().frame(width: 96, height: 96)
            Text("Your windows, naturally arranged.").font(.system(size: 20, weight: .medium))
            Text("Native on Windows. Native on Mac. The same adaptive layout rules, the same original Bento artwork.").font(.system(size: 13)).lineSpacing(5).foregroundStyle(BentoStyle.secondary)
            Button("View onboarding") { showOnboarding() }
            Link("Bento Layout on GitHub", destination: URL(string: "https://github.com/AbdullahEgh/Bento-Layout")!)
        }
    }
    private func releasePoints(_ points: [String]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(points, id: \.self) { point in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("•").foregroundStyle(BentoStyle.secondary)
                    Text(point).frame(maxWidth: .infinity, alignment: .leading)
                }.fixedSize(horizontal: false, vertical: true)
            }
        }.font(.system(size: 12)).lineSpacing(2)
    }
    private var whatsNew: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Bento for macOS \(updater.version)").font(.system(size: 18, weight: .semibold))
            if let current = ReleaseNotes.history.first(where: { $0.version == updater.version }) {
                BentoCard { releasePoints(current.points) }
            }
            DisclosureGroup("Update Log") {
                VStack(alignment: .leading, spacing: 18) {
                    ForEach(ReleaseNotes.history) { release in
                        VStack(alignment: .leading, spacing: 8) {
                            Text(release.version).font(.system(size: 13, weight: .semibold))
                            releasePoints(release.points).foregroundStyle(BentoStyle.secondary)
                        }
                    }
                }.padding(.top, 12)
            }
            if !updater.installationHistory.isEmpty {
                DisclosureGroup("Installation History") {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(updater.installationHistory, id: \.self) { Text($0) }
                    }.font(.system(size: 11)).foregroundStyle(BentoStyle.secondary).padding(.top, 12)
                }
            }
        }
    }
}
