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
                }.padding(.horizontal, 16).padding(.top, 24).padding(.bottom, 12).background(BentoStyle.sidebar)
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
            }.padding(22).frame(width: 195).background(BentoStyle.sidebar) }
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
        }.frame(minWidth: 340, minHeight: 420).foregroundStyle(BentoStyle.text).background(BentoStyle.page)
            .disabled(model.interacting || (!model.applyingSettings && (model.busy || model.activating)))
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
                    HStack { Circle().fill(!model.permission ? .orange : model.active ? BentoStyle.accent : BentoStyle.secondary).frame(width: 8, height: 8); Text(!model.permission ? "Accessibility access needed" : model.active ? "Bento is arranging your windows" : "Bento is off").font(.system(size: 14, weight: .medium)); Spacer() }
                    Text(model.active ? "\(model.history.current.windows.count) arranged · \(model.minimizedByBento.count) in Dock · \(model.floatingWindows.count - model.minimizedByBento.count) left alone · \(model.settings.shortcut.label)" : "\(model.windows.count) eligible windows · \(model.settings.shortcut.label)").font(.system(size: 12)).foregroundStyle(BentoStyle.secondary)
                    rowLayout {
                        Button {
                            if model.permission { model.toggle() }
                            else { model.system.requestPermission(); model.system.openPermissionSettings() }
                        } label: { Text(!model.permission ? "Enable Accessibility" : model.active ? "Turn Bento off" : "Arrange windows") }.buttonStyle(PrimaryButtonStyle()).disabled(model.busy)
                        Button { Task { await model.restore() } } label: { settingLabel("Restore originals", symbol: "Restore") }.disabled(model.busy)
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
                            Text("Open a minimized window from the Dock to give it priority in the layout. Turning Bento off brings back windows minimized by Bento.").font(.system(size: 11))
                        }.foregroundStyle(BentoStyle.secondary)
                    }
                }
            }
            activationOptions
            BentoCard {
                VStack(alignment: .leading, spacing: 12) {
                    Toggle(isOn: Binding(get: { loginStartup.enabled }, set: { loginStartup.setEnabled($0) })) { settingLabel("Start at login", symbol: "Startup") }.toggleStyle(.switch)
                    Text("Open Bento in the menu bar when you sign in to this Mac.").font(.system(size: 11)).foregroundStyle(BentoStyle.secondary)
                    if loginStartup.needsApproval { Button("Approve in Login Items") { loginStartup.openSettings() } }
                    if let message = loginStartup.message { Text(message).font(.system(size: 11)).foregroundStyle(BentoStyle.secondary) }
                }.font(.system(size: 12))
            }
            BentoCard {
                VStack(spacing: 20) {
                    setting("Space between windows", symbol: "Gap", value: $model.settings.gap, range: 4...32)
                    setting("Desktop margin", symbol: "Margin", value: $model.settings.margin, range: 0...64)
                    rowLayout { settingLabel("Background darkness", symbol: "Darkness"); Slider(value: Binding(get: { Double(model.settings.backgroundDarkness) }, set: { model.settings.backgroundDarkness = Int($0) }), in: 0...100, step: 5); Text("\(model.settings.backgroundDarkness)%").monospacedDigit().frame(width: 36) }
                    Toggle(isOn: $model.settings.animate) { settingLabel("Smooth window transitions", symbol: "Animation") }.toggleStyle(.switch)
                    if model.settings.animate { rowLayout { settingLabel("Animation duration", symbol: "Duration"); Spacer(); Stepper("\(model.settings.animationMS) ms", value: $model.settings.animationMS, in: 80...400, step: 20).frame(width: 120) } }
                    Text("Motion follows macOS Reduce Motion. Background darkness applies while Bento is on.").font(.system(size: 11)).foregroundStyle(BentoStyle.secondary)
                    rowLayout { settingLabel("Appearance", symbol: "Appearance"); Spacer(); Picker("Appearance", selection: $model.settings.theme) { Text("System").tag("System"); Text("Light").tag("Light"); Text("Dark").tag("Dark") }.labelsHidden().frame(width: 130) }
                    Text("Spacing updates live while Bento is on.").font(.system(size: 11)).foregroundStyle(BentoStyle.secondary).frame(maxWidth: .infinity, alignment: .leading)
                }.font(.system(size: 12))
            }
            rowLayout {
                Button("Restore saved layout") { Task { await model.loadLayout() } }.disabled(!model.permission || model.busy)
                Spacer(); Button("Undo") { Task { await model.undo() } }.disabled(!model.active || model.busy)
                Button("Redo") { Task { await model.undo(redo: true) } }.disabled(model.busy)
            }
        }
    }
    private var activationOptions: some View {
        BentoCard {
                VStack(alignment: .leading, spacing: 18) {
                    Text("Desktop behavior").font(.system(size: 14, weight: .semibold))
                    Toggle(isOn: $model.settings.minimizeOverflow) { settingLabel("Minimize windows that do not fit", symbol: "Restore") }.toggleStyle(.switch)
                    Toggle(isOn: $model.settings.hideDock) { settingLabel("Automatically hide the Dock", symbol: "Dock") }.toggleStyle(.switch)
                    Toggle(isOn: $model.settings.hideMenuBar) { settingLabel("Automatically hide the menu bar", symbol: "MenuBar") }.toggleStyle(.switch)
                    rowLayout {
                        settingLabel("macOS screen-edge snapping", symbol: "Snap"); Spacer()
                        Picker("macOS screen-edge snapping", selection: $model.settings.edgeSnapping) {
                            Text("Keep current setting").tag("Keep"); Text("On while active").tag("On"); Text("Off while active").tag("Off")
                        }.labelsHidden().frame(width: 175)
                    }
                    Text("Changes apply live while Bento is on. Turning an option off restores your previous macOS setting. Dock and menu-bar changes briefly refresh the desktop.").font(.system(size: 11)).lineSpacing(4).foregroundStyle(BentoStyle.secondary)
                }.font(.system(size: 12))
        }
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
                    Toggle(isOn: $model.settings.shortcut.enabled) { settingLabel("Enable keyboard shortcut", symbol: "Keyboard") }.toggleStyle(.switch)
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
                    Text("Drag a real window onto another region to swap. Hold at its edge until the frosted slot divides, then release to split. Drag a gap grip to resize neighbors. Escape cancels and restores the committed layout.").font(.system(size: 12)).lineSpacing(4).foregroundStyle(BentoStyle.secondary)
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
    private var whatsNew: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Bento for macOS \(updater.version)").font(.system(size: 18, weight: .semibold))
            BentoCard {
                VStack(alignment: .leading, spacing: 14) {
                    ForEach(["Grabbers stay hidden until hovered or held, below your windows and above the dark background.", "Smooth window transitions animate activation, restoration and layout changes, respecting Reduce Motion.", "Extra windows minimize to the Dock. Reopen one to give it priority in the split layout; Bento brings back the windows it minimized when you turn it off.", "Swap, split and conflict previews use symbols instead of text and match the final slot geometry.", "Settings and layouts save automatically. Updates keep the permanent app identity introduced in 0.2.5."], id: \.self) { Text($0).font(.system(size: 12)).lineSpacing(4) }
                }
            }
            DisclosureGroup("Update Log") {
                VStack(alignment: .leading, spacing: 12) {
                    Text("0.2.0 · Real-window layout, swaps, edge splits, resizing, edited-layout resume, saved layouts, configurable shortcut, background darkness, login startup and signed GitHub OTA.")
                    Text("0.1.0 · Native Mac preview, onboarding, layout engine and original Bento artwork.")
                    ForEach(updater.installationHistory, id: \.self) { Text($0) }
                }.font(.system(size: 11)).foregroundStyle(BentoStyle.secondary).padding(.top, 12)
            }
        }
    }
}
