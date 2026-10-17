import SwiftUI
import AppKit

// Color values and vector paths are copied from Windows Theme.xaml/AppTheme.cs
// and Symbols.cs. Native macOS typography and controls share the same artwork.
enum BentoStyle {
    static func color(_ light: UInt32, _ dark: UInt32) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let v = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
            return NSColor(srgbRed: CGFloat((v >> 16) & 255) / 255, green: CGFloat((v >> 8) & 255) / 255, blue: CGFloat(v & 255) / 255, alpha: 1)
        })
    }
    static let page = color(0xF6F7F9, 0x202428), sidebar = color(0xEEF0F3, 0x191D21)
    static let surface = color(0xFFFFFF, 0x2A3035), text = color(0x20262C, 0xEEF3F4)
    static let secondary = color(0x6E7782, 0xA3AFB7), line = color(0xE2E6EA, 0x394249)
    static let accent = color(0x168574, 0x41AD98), selection = color(0xDCEEE9, 0x243F39)
    static var icon: NSImage { NSImage(contentsOf: Bundle.module.url(forResource: "bento", withExtension: "png")!)! }
}

struct BentoSymbol: View {
    let name: String
    var size: CGFloat = 20
    private static let paths = [
        "Workspace": "M4,3 L20,3 Q22,3 22,5 L22,19 Q22,21 20,21 L4,21 Q2,21 2,19 L2,5 Q2,3 4,3 M10,3 L10,21 M10,12 L22,12",
        "Gestures": "M8,12 L8,5 Q8,2 10,2 Q12,2 12,5 L12,10 M12,8 Q16,7 16,11 M16,10 Q20,9 20,13 L20,16 Q20,22 14,22 L11,22 Q8,22 6,18 L3,13 Q2,11 4,10 Q6,9 8,12",
        "Arrow": "M5,12 L19,12 M13,6 L19,12 L13,18",
        "Back": "M19,12 L5,12 M11,6 L5,12 L11,18",
        "Gap": "M2,4 L7,4 L7,20 L2,20 Z M17,4 L22,4 L22,20 L17,20 Z M10,12 L14,12 M11,10 L9,12 L11,14 M13,10 L15,12 L13,14",
        "Margin": "M2,7 L2,2 L7,2 M17,2 L22,2 L22,7 M22,17 L22,22 L17,22 M7,22 L2,22 L2,17 M7,7 L17,7 L17,17 L7,17 Z",
        "Keyboard": "M3,5 L21,5 Q23,5 23,7 L23,18 L1,18 L1,7 Q1,5 3,5 M5,9 L7,9 M11,9 L13,9 M17,9 L19,9 M5,13 L7,13 M10,14 L18,14",
        "Save": "M3,3 L18,3 L21,6 L21,21 L3,21 Z M7,3 L7,9 L17,9 L17,3 M7,21 L7,14 L17,14 L17,21",
        "Resume": "M6,3 L21,12 L6,21 Z",
        "Pause": "M7,4 L7,20 M17,4 L17,20",
        "Darkness": "M4,3 L20,3 Q21,3 21,4 L21,20 Q21,21 20,21 L4,21 Q3,21 3,20 L3,4 Q3,3 4,3 M7,7 L17,7 L17,17 L7,17 Z M9,9 L9,15 M12,9 L12,15 M15,9 L15,15",
        "Animation": "M2,17 C7,17 7,7 13,7 L21,7 M17,3 L21,7 L17,11 M3,21 L7,21 M2,12 L5,12",
        "Snap": "M3,4 L21,4 L21,20 L3,20 Z M12,4 L12,20 M6,9 L9,12 L6,15 M18,9 L15,12 L18,15",
        "Dock": "M3,3 L21,3 L21,21 L3,21 Z M6,16 L18,16 L18,19 L6,19 Z M10,16 L10,19 M14,16 L14,19",
        "MenuBar": "M3,3 L21,3 L21,21 L3,21 Z M3,8 L21,8 M6,5.5 L9,5.5 M16,5.5 L18,5.5",
        "Startup": "M12,2 L12,11 M7,5 C-2,11 3,22 12,22 C21,22 26,11 17,5",
        "Appearance": "M12,2 C25,2 25,22 12,22 C-1,22 -1,2 12,2 M12,2 L12,22 M15,5 L15,19 M18,8 L18,16",
        "Duration": "M12,6 C23,6 23,22 12,22 C1,22 1,6 12,6 M12,10 L12,14 L16,14 M9,2 L15,2 M12,2 L12,6",
        "Restore": "M4,8 C8,-2 23,3 22,13 C21,24 6,25 3,17 M4,2 L4,9 L11,9"
    ]
    var body: some View {
        OriginalPath(data: Self.paths[name] ?? Self.paths["Workspace"]!)
            .stroke(style: StrokeStyle(lineWidth: 1.6, lineCap: .round, lineJoin: .round))
            .frame(width: size, height: size).accessibilityHidden(true)
    }
    private struct OriginalPath: Shape {
        let data: String
        func path(in rect: CGRect) -> Path {
            let expression = try! NSRegularExpression(pattern: "[MLQCZ]|-?[0-9]+(?:\\.[0-9]+)?")
            let tokens = expression.matches(in: data, range: NSRange(data.startIndex..., in: data)).map { String(data[Range($0.range, in: data)!]) }
            var result = Path(), i = 0
            func point() -> CGPoint { defer { i += 2 }; return CGPoint(x: Double(tokens[i])!, y: Double(tokens[i + 1])!) }
            while i < tokens.count {
                let command = tokens[i]; i += 1
                switch command {
                case "M": result.move(to: point())
                case "L": result.addLine(to: point())
                case "Q": let c = point(); result.addQuadCurve(to: point(), control: c)
                case "C": let a = point(), b = point(); result.addCurve(to: point(), control1: a, control2: b)
                case "Z": result.closeSubpath()
                default: break
                }
            }
            return result.applying(CGAffineTransform(scaleX: rect.width / 24, y: rect.height / 24))
        }
    }
}

struct PrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.system(size: 13, weight: .semibold)).foregroundStyle(.white)
            .padding(.horizontal, 20).padding(.vertical, 12)
            .bentoGlass(radius: 12, tint: BentoStyle.accent, prominent: true)
            .opacity(configuration.isPressed ? 0.8 : 1)
    }
}
struct BentoCard<Content: View>: View {
    @ViewBuilder let content: Content
    var body: some View {
        content.frame(maxWidth: .infinity, alignment: .leading).padding(20)
            .bentoGlass(radius: 18)
    }
}

struct DemoDesktop: View {
    var four = false
    var swapped = false
    var gap: CGFloat = 8
    var windowHeight: CGFloat = 258
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 5) {
                Image(nsImage: BentoStyle.icon).resizable().frame(width: 15, height: 15)
                Text("Bento").font(.system(size: 10, weight: .semibold))
                Spacer(); Text("Your workspace").font(.system(size: 9))
            }.foregroundStyle(BentoStyle.text.opacity(0.7)).padding(.horizontal, 14).frame(height: 28)
            HStack(spacing: gap) {
                demoWindow(swapped ? "Notes" : "Browser", kind: swapped ? 1 : 0)
                    .frame(maxWidth: .infinity)
                VStack(spacing: gap) {
                    demoWindow(swapped ? "Browser" : "Notes", kind: swapped ? 0 : 1)
                    demoWindow("Finder", kind: 2)
                    if four { demoWindow("Calendar", kind: 3) }
                }.frame(maxWidth: .infinity)
            }.padding(gap).frame(height: windowHeight)
            HStack(spacing: 6) {
                ForEach(0..<6) { i in RoundedRectangle(cornerRadius: 5).fill(i == 2 ? BentoStyle.accent.opacity(0.7) : BentoStyle.surface.opacity(0.8)).frame(width: 23, height: 23) }
            }.padding(6).background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10)).padding(.bottom, 10)
        }
        .background(LinearGradient(colors: [BentoStyle.selection, BentoStyle.accent.opacity(0.16), BentoStyle.sidebar], startPoint: .topLeading, endPoint: .bottomTrailing))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(BentoStyle.line))
        .shadow(color: .black.opacity(0.07), radius: 16, y: 8)
        .accessibilityLabel("Illustration of a Bento workspace with \(four ? 4 : 3) windows")
    }
    private func demoWindow(_ title: String, kind: Int) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 3) {
                ForEach(0..<3) { _ in Circle().fill(BentoStyle.secondary.opacity(0.23)).frame(width: 5, height: 5) }
                Spacer(); Text(title).font(.system(size: 8, weight: .medium)).foregroundStyle(BentoStyle.secondary)
            }
            if kind == 0 {
                RoundedRectangle(cornerRadius: 5).fill(BentoStyle.accent.opacity(0.14)).frame(maxHeight: .infinity)
                ForEach(0..<3) { i in Capsule().fill(BentoStyle.line).frame(width: CGFloat(70 + i * 16), height: 4) }
            } else if kind == 1 {
                Text("A little room to think.").font(.system(size: 10, weight: .medium)).foregroundStyle(BentoStyle.text)
                ForEach(0..<2) { _ in Capsule().fill(BentoStyle.line).frame(height: 4) }
                Spacer(minLength: 0)
            } else {
                HStack(spacing: 8) { ForEach(0..<3) { _ in RoundedRectangle(cornerRadius: 4).fill(BentoStyle.accent.opacity(0.16)).frame(maxWidth: .infinity, maxHeight: .infinity) } }
            }
        }.padding(11).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(BentoStyle.surface, in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(BentoStyle.line.opacity(0.7)))
    }
}

@MainActor enum BentoWindowChrome {
    static func configure(_ window: NSWindow, onboarding: Bool, theme: String) {
        window.title = onboarding ? "Bento" : "Bento Settings"
        // Reserve the native title bar instead of extending glass content beneath it.
        window.styleMask = [.titled, .closable, .miniaturizable]
        if !onboarding { window.styleMask.insert(.resizable); window.contentMinSize = NSSize(width: 340, height: 420) }
        window.titleVisibility = .visible; window.titlebarAppearsTransparent = false
        window.titlebarSeparatorStyle = .none
        window.isOpaque = true; window.backgroundColor = .windowBackgroundColor
        updateAppearance(window, theme: theme)
    }
    static func updateAppearance(_ window: NSWindow, theme: String) {
        window.appearance = theme == "Dark" ? NSAppearance(named: .darkAqua) : theme == "Light" ? NSAppearance(named: .aqua) : nil
    }
}
