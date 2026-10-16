import SwiftUI

struct SettingsView: View {
    @ObservedObject var model: WorkspaceController
    var showOnboarding: () -> Void
    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 9) { Image(nsImage: BentoStyle.icon).resizable().frame(width: 36, height: 36); Text("Bento").font(.system(size: 20, weight: .semibold)) }.padding(.bottom, 28)
                ForEach(["Workspace", "Gestures", "Updates", "About"], id: \.self) { page in
                    Button { model.page = page } label: {
                        HStack(spacing: 10) {
                            if page == "Workspace" || page == "Gestures" { BentoSymbol(name: page, size: 17) }
                            else { Image(systemName: page == "Updates" ? "arrow.down.circle" : "info.circle").frame(width: 17) }
                            Text(page).font(.system(size: 12, weight: .medium)); Spacer()
                        }.padding(11).background(model.page == page ? BentoStyle.selection : .clear, in: RoundedRectangle(cornerRadius: 8))
                    }.buttonStyle(.plain).foregroundStyle(model.page == page ? BentoStyle.accent : BentoStyle.secondary)
                }
                Spacer()
                Text("macOS preview · 0.1.0").font(.system(size: 10)).foregroundStyle(BentoStyle.secondary)
            }.padding(22).frame(width: 195).background(BentoStyle.sidebar)
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    Text(model.page).font(.system(size: 28, weight: .semibold)).tracking(-0.5)
                    switch model.page {
                    case "Workspace": workspace
                    case "Gestures": gestures
                    case "Updates": updates
                    default: about
                    }
                    if let message = model.message { Text(message).font(.system(size: 12)).foregroundStyle(BentoStyle.secondary).textSelection(.enabled) }
                }.padding(30).frame(maxWidth: .infinity, alignment: .leading)
            }
        }.frame(width: 820, height: 620).foregroundStyle(BentoStyle.text).background(BentoStyle.page)
            .onChange(of: model.settings.gap) { _, _ in model.saveSettings() }
            .onChange(of: model.settings.margin) { _, _ in model.saveSettings() }
            .onChange(of: model.settings.splitHold) { _, _ in model.saveSettings() }
            .onChange(of: model.settings.theme) { _, _ in model.saveSettings() }
    }
    private var workspace: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Your desktop, with a little breathing room.").font(.system(size: 13)).foregroundStyle(BentoStyle.secondary)
            BentoCard {
                VStack(alignment: .leading, spacing: 18) {
                    HStack { Circle().fill(model.active ? BentoStyle.accent : BentoStyle.secondary).frame(width: 8, height: 8); Text(model.active ? "Bento is arranging your windows" : "Bento is off").font(.system(size: 14, weight: .medium)); Spacer() }
                    Text("\(model.windows.count) eligible windows · ⌃⌥B to toggle").font(.system(size: 12)).foregroundStyle(BentoStyle.secondary)
                    HStack {
                        Button { model.toggle() } label: { Text(model.active ? "Turn Bento off" : "Arrange windows") }.buttonStyle(PrimaryButtonStyle()).disabled(model.busy || !model.permission)
                        Button("Restore originals") { Task { await model.restore() } }.disabled(model.busy)
                    }
                    if !model.permission { Button("Allow Accessibility access") { model.system.requestPermission(); model.system.openPermissionSettings() } }
                }
            }
            BentoCard {
                VStack(spacing: 20) {
                    setting("Space between windows", symbol: "Gap", value: $model.settings.gap, range: 4...32)
                    setting("Desktop margin", symbol: "Margin", value: $model.settings.margin, range: 0...64)
                    HStack { Text("Appearance"); Spacer(); Picker("Appearance", selection: $model.settings.theme) { Text("System").tag("System"); Text("Light").tag("Light"); Text("Dark").tag("Dark") }.labelsHidden().frame(width: 130) }
                    Text("Spacing changes apply the next time you arrange windows.").font(.system(size: 11)).foregroundStyle(BentoStyle.secondary).frame(maxWidth: .infinity, alignment: .leading)
                }.font(.system(size: 12))
            }
            HStack {
                Button("Save Bento") { model.saveLayout() }.disabled(!model.active || model.busy)
                Button("Restore saved layout") { Task { await model.loadLayout() } }.disabled(!model.permission || model.busy)
                Spacer(); Button("Undo") { Task { await model.undo() } }.disabled(!model.active || model.busy)
                Button("Redo") { Task { await model.undo(redo: true) } }.disabled(model.busy)
            }
        }
    }
    private func setting(_ title: String, symbol: String, value: Binding<Int>, range: ClosedRange<Int>) -> some View {
        HStack(spacing: 12) {
            BentoSymbol(name: symbol, size: 18).foregroundStyle(BentoStyle.secondary)
            Text(title); Spacer()
            Stepper("\(value.wrappedValue) pt", value: value, in: range, step: 2).frame(width: 90)
        }
    }
    private var gestures: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Small gestures. More room to work.").foregroundStyle(BentoStyle.secondary)
            BentoCard {
                VStack(alignment: .leading, spacing: 18) {
                    HStack { BentoSymbol(name: "Keyboard"); Text("Toggle Bento"); Spacer(); Text("⌃ ⌥ B").font(.system(.body, design: .monospaced)).foregroundStyle(BentoStyle.accent) }
                    Text("The menu-bar control is always available if another app has registered this shortcut.").font(.system(size: 12)).foregroundStyle(BentoStyle.secondary)
                    Divider()
                    HStack { Text("Hold to split"); Spacer(); Stepper("\(model.settings.splitHold) ms", value: $model.settings.splitHold, in: 0...2000, step: 100).frame(width: 125) }
                    Text("Native title-bar drop gestures and gap grips are in development. This preview includes automatic arrangement, restoration, saved layouts, and the shared gesture policy.").font(.system(size: 12)).lineSpacing(4).foregroundStyle(BentoStyle.secondary)
                }
            }
        }
    }
    private var updates: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Bento for macOS · Development preview").font(.system(size: 15, weight: .medium))
            Text("Download Mac builds from the same repository as Windows. Automatic installation is not included in this first Mac milestone.").font(.system(size: 13)).lineSpacing(5).foregroundStyle(BentoStyle.secondary)
            Link(destination: URL(string: "https://github.com/AbdullahEgh/Bento-Layout/releases")!) { Label("Open GitHub releases", systemImage: "arrow.up.right.square") }.buttonStyle(PrimaryButtonStyle())
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
}
