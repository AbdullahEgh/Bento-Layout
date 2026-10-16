import SwiftUI

struct OnboardingView: View {
    @ObservedObject var model: WorkspaceController
    var finished: () -> Void
    @State var step = 0
    @State private var four = false
    @State private var swapped = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private let labels = ["Welcome", "Accessibility", "Find your flow", "Ready to begin"]
    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 10) {
                    Image(nsImage: BentoStyle.icon).resizable().frame(width: 38, height: 38)
                    VStack(alignment: .leading, spacing: 2) { Text("Bento").font(.system(size: 19, weight: .semibold)); Text("FOR MACOS").font(.system(size: 8, weight: .semibold)).tracking(1.6).foregroundStyle(BentoStyle.secondary) }
                }.padding(.bottom, 48)
                ForEach(Array(labels.enumerated()), id: \.offset) { index, title in
                    HStack(spacing: 12) {
                        ZStack {
                            Circle().fill(index <= step ? BentoStyle.accent : BentoStyle.line).frame(width: 23, height: 23)
                            if index < step { Image(systemName: "checkmark").font(.system(size: 9, weight: .bold)).foregroundStyle(.white) }
                            else { Text("\(index + 1)").font(.system(size: 10, weight: .semibold)).foregroundStyle(index == step ? .white : BentoStyle.secondary) }
                        }
                        Text(title).font(.system(size: 12, weight: index == step ? .semibold : .regular)).foregroundStyle(index == step ? BentoStyle.text : BentoStyle.secondary)
                    }.padding(.bottom, 24)
                }
                Spacer()
                BentoSymbol(name: "Workspace", size: 26).foregroundStyle(BentoStyle.accent).padding(.bottom, 12)
                Text("Your windows,\nnaturally arranged.").font(.system(size: 14, weight: .medium)).lineSpacing(4)
                Text("Made for the way you work.").font(.system(size: 10)).foregroundStyle(BentoStyle.secondary).padding(.top, 9)
            }.padding(28).frame(width: 222).background(BentoStyle.sidebar)
            VStack(alignment: .leading, spacing: 0) {
                HStack { Text("WELCOME TO A CALMER DESKTOP").font(.system(size: 9, weight: .semibold)).tracking(1.5).foregroundStyle(BentoStyle.accent); Spacer(); Text("\(step + 1) / 4").font(.system(size: 11, design: .monospaced)).foregroundStyle(BentoStyle.secondary) }.padding(.bottom, 22)
                Group {
                    switch step {
                    case 0: welcome
                    case 1: permission
                    case 2: playground
                    default: ready
                    }
                }
                Spacer(minLength: 12)
                if let message = model.message {
                    Text(message).font(.system(size: 11)).foregroundStyle(BentoStyle.secondary).fixedSize(horizontal: false, vertical: true).padding(.bottom, 12).accessibilityAddTraits(.updatesFrequently)
                }
                Divider().overlay(BentoStyle.line).padding(.bottom, 18)
                HStack {
                    if step > 0 { Button { changeStep(step - 1) } label: { HStack(spacing: 7) { BentoSymbol(name: "Back", size: 15); Text("Back") } }.buttonStyle(.plain).foregroundStyle(BentoStyle.secondary) }
                    else { Text("Local. Lightweight. Yours.").font(.system(size: 10)).foregroundStyle(BentoStyle.secondary) }
                    Spacer()
                    if step == 3 {
                        Button("Finish for now") { complete() }.buttonStyle(.plain).foregroundStyle(BentoStyle.secondary).padding(.trailing, 8)
                        Button { Task { await model.arrange(); if model.active { complete() } } } label: {
                            HStack(spacing: 10) { Text(model.busy ? "Arranging…" : "Arrange my windows"); BentoSymbol(name: "Arrow", size: 16) }
                        }.buttonStyle(PrimaryButtonStyle()).disabled(!model.permission || model.busy).opacity(model.permission ? 1 : 0.45)
                    } else {
                        Button { changeStep(step + 1) } label: {
                            HStack(spacing: 12) { Text(step == 0 ? "Let’s get started" : step == 1 && !model.permission ? "Explore the preview" : "Continue"); BentoSymbol(name: "Arrow", size: 16) }
                        }.buttonStyle(PrimaryButtonStyle()).keyboardShortcut(.defaultAction)
                    }
                }
            }.padding(.horizontal, 38).padding(.vertical, 32).frame(maxWidth: .infinity, maxHeight: .infinity)
        }.frame(width: 940, height: 650).background(BentoStyle.page).foregroundStyle(BentoStyle.text)
            .onAppear { if !CommandLine.arguments.contains("--render-preview") { model.refresh() } }
    }
    private func changeStep(_ next: Int) { withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.18)) { step = next }; if next == 3 { model.refresh() } }
    private func complete() { model.settings.onboardingComplete = true; model.saveSettings(); finished() }
    private func heading(_ title: String, _ detail: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).font(.system(size: 33, weight: .semibold)).tracking(-1).lineSpacing(1).fixedSize(horizontal: false, vertical: true)
            Text(detail).font(.system(size: 13)).lineSpacing(5).foregroundStyle(BentoStyle.secondary).fixedSize(horizontal: false, vertical: true)
        }.padding(.bottom, 25)
    }
    private var welcome: some View {
        VStack(alignment: .leading, spacing: 0) {
            heading("A little order. A lot more space.", "Bring your open windows together in a layout that feels effortless. Your apps stay right on your desktop.")
            DemoDesktop().padding(.bottom, 16)
            HStack(spacing: 22) {
                Label { Text("Real app windows") } icon: { BentoSymbol(name: "Workspace", size: 14) }
                Label { Text("Original positions restored") } icon: { Image(systemName: "arrow.uturn.backward").font(.system(size: 12)) }
            }.font(.system(size: 10)).foregroundStyle(BentoStyle.secondary)
        }
    }
    private var permission: some View {
        VStack(alignment: .leading, spacing: 0) {
            heading("Give your windows\na helping hand.", "Bento needs Accessibility access to move and resize other apps’ windows. You stay in control of when arranging begins.")
            BentoCard {
                VStack(alignment: .leading, spacing: 19) {
                    HStack(spacing: 14) {
                        Image(systemName: model.permission ? "checkmark.shield.fill" : "hand.raised").font(.system(size: 28)).foregroundStyle(BentoStyle.accent)
                        VStack(alignment: .leading, spacing: 5) { Text("Accessibility access").font(.system(size: 14, weight: .semibold)); Text(model.permission ? "Connected. You’re ready to arrange." : "One permission, for window control.").font(.system(size: 11)).foregroundStyle(BentoStyle.secondary) }
                        Spacer()
                        Circle().fill(model.permission ? BentoStyle.accent : .orange).frame(width: 7, height: 7)
                    }
                    Divider()
                    ForEach(["Open Privacy & Security → Accessibility.", "Turn on Bento in the list of apps.", "Come back here. We’ll check automatically."], id: \.self) { text in
                        Text(text).font(.system(size: 12)).foregroundStyle(BentoStyle.secondary)
                    }
                    HStack {
                        Button(model.permission ? "Open System Settings" : "Allow Accessibility") { model.system.requestPermission(); model.system.openPermissionSettings() }.buttonStyle(PrimaryButtonStyle())
                        Button("Check again") { model.permission = model.system.trusted }.buttonStyle(.plain).foregroundStyle(BentoStyle.accent)
                    }
                }
            }
            HStack(alignment: .top, spacing: 10) { Image(systemName: "lock"); Text("This build does not capture your screen, change display resolution, or upload your window information.").lineSpacing(4) }.font(.system(size: 11)).foregroundStyle(BentoStyle.secondary).padding(.top, 19)
        }
    }
    private var playground: some View {
        VStack(alignment: .leading, spacing: 0) {
            heading("Make room for your work.", "Try a Bento composition here. This preview stays inside the app and won’t move your open windows.")
            DemoDesktop(four: four, swapped: swapped, gap: CGFloat(model.settings.gap) / 1.5, windowHeight: 235).padding(.bottom, 18)
            HStack(spacing: 12) {
                Button { withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) { four.toggle() } } label: { Label(four ? "Three windows" : "Add a window", systemImage: "plus.rectangle.on.rectangle") }
                Button { withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) { swapped.toggle() } } label: { Label("Try a swap", systemImage: "arrow.left.arrow.right") }
                Spacer(); Text("PREVIEW ONLY").font(.system(size: 8, weight: .medium)).tracking(1).foregroundStyle(BentoStyle.secondary)
            }.controlSize(.large)
        }
    }
    private var ready: some View {
        VStack(alignment: .leading, spacing: 0) {
            heading("Your next workspace\nstarts here.", "Arrange eligible windows on their current displays. Toggle Bento off to return them to their original positions.")
            BentoCard {
                VStack(alignment: .leading, spacing: 18) {
                    HStack { BentoSymbol(name: "Workspace").foregroundStyle(BentoStyle.accent); Text(model.permission ? "\(model.windows.count) windows ready" : "Accessibility access needed").font(.system(size: 14, weight: .semibold)); Spacer(); Button("Refresh") { model.refresh() }.buttonStyle(.plain).foregroundStyle(BentoStyle.accent) }
                    if !model.permission { Button("Open Accessibility settings") { model.system.requestPermission(); model.system.openPermissionSettings() } }
                    else if model.windows.isEmpty { Text("Open a browser, Finder, or another application window. Bento’s own windows are excluded.").font(.system(size: 12)).foregroundStyle(BentoStyle.secondary) }
                    else { Text(model.windows.prefix(5).map(\.application).joined(separator: " · ")).font(.system(size: 12)).foregroundStyle(BentoStyle.secondary).lineLimit(2) }
                    Divider()
                    HStack { BentoSymbol(name: "Gap").foregroundStyle(BentoStyle.secondary); Text("Space between windows"); Spacer(); Picker("Space between windows", selection: $model.settings.gap) { Text("Compact · 4 pt").tag(4); Text("Balanced · 8 pt").tag(8); Text("Relaxed · 16 pt").tag(16) }.labelsHidden().frame(width: 165) }.font(.system(size: 12))
                    HStack { BentoSymbol(name: "Keyboard").foregroundStyle(BentoStyle.secondary); Text("Toggle from anywhere"); Spacer(); Text("⌃ ⌥ B").font(.system(size: 14, design: .monospaced)).foregroundStyle(BentoStyle.accent) }.font(.system(size: 12))
                }
            }
            Text("No windows move until you choose Arrange my windows. Fullscreen, hidden, minimized, and fixed-size windows are excluded.").font(.system(size: 11)).lineSpacing(4).foregroundStyle(BentoStyle.secondary).padding(.top, 18)
        }
    }
}
