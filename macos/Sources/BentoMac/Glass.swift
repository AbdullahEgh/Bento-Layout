import AppKit
import SwiftUI

/// A native backdrop, shared by desktop previews and SwiftUI window backgrounds.
@MainActor final class BentoFrostView: NSView {
    enum Kind { case liquidGlass, blur, opaque }
    private(set) var kind = Kind.blur
    let ink = NSView()
    private var backdrop: NSView?
    private let radius: CGFloat
    private let allowGlass: Bool
    private let transparencyOverride: Bool?
    private var observer: NSObjectProtocol?
    var tint: NSColor? { didSet { applyTint() } }
    init(radius: CGFloat, allowGlass: Bool = true, reduceTransparency: Bool? = nil) {
        self.radius = radius; self.allowGlass = allowGlass; self.transparencyOverride = reduceTransparency
        super.init(frame: .zero)
        wantsLayer = true; ink.wantsLayer = true
        ink.autoresizingMask = [.width, .height]
        rebuild()
        observer = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.rebuild() }
        }
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is unsupported") }
    deinit { if let observer { NSWorkspace.shared.notificationCenter.removeObserver(observer) } }
    private func rebuild() {
        ink.removeFromSuperview(); backdrop?.removeFromSuperview()
        let reduced = transparencyOverride ?? NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency
        let view: NSView
        if reduced {
            kind = .opaque; view = NSView(); view.wantsLayer = true
            view.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
            view.addSubview(ink)
        } else if #available(macOS 26.0, *), allowGlass {
            kind = .liquidGlass
            let glass = NSGlassEffectView(); glass.style = .regular; glass.cornerRadius = radius
            glass.contentView = ink; view = glass
        } else {
            kind = .blur
            let blur = NSVisualEffectView(); blur.material = .hudWindow
            blur.blendingMode = .behindWindow; blur.state = .active
            blur.addSubview(ink); view = blur
        }
        view.wantsLayer = true; view.layer?.cornerRadius = radius; view.layer?.masksToBounds = true
        view.frame = bounds; view.autoresizingMask = [.width, .height]
        ink.frame = view.bounds; addSubview(view); backdrop = view
        applyTint()
    }
    private func applyTint() {
        if #available(macOS 26.0, *), let glass = backdrop as? NSGlassEffectView { glass.tintColor = tint }
    }
    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        if kind == .opaque { backdrop?.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor }
    }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

struct BentoWindowBackdrop: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView(); view.material = .underWindowBackground
        view.blendingMode = .behindWindow; view.state = .active
        return view
    }
    func updateNSView(_ view: NSVisualEffectView, context: Context) {}
}

struct BentoGlassSurface: View {
    var radius: CGFloat = 18
    var tint: Color = .clear
    var prominent = false
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    var body: some View {
        if reduceTransparency {
            RoundedRectangle(cornerRadius: radius).fill(prominent ? tint : BentoStyle.surface)
        } else if #available(macOS 26.0, *) {
            RoundedRectangle(cornerRadius: radius).fill(.clear)
                .glassEffect(.regular.tint(tint), in: RoundedRectangle(cornerRadius: radius))
        } else {
            if prominent { RoundedRectangle(cornerRadius: radius).fill(tint) }
            else { RoundedRectangle(cornerRadius: radius).fill(.regularMaterial) }
        }
    }
}

struct BentoWindowSurface: View {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    var body: some View {
        if reduceTransparency { BentoStyle.page }
        else {
            BentoWindowBackdrop()
                .overlay(BentoStyle.page.opacity(0.24))
                .overlay(alignment: .topLeading) {
                    LinearGradient(colors: [BentoStyle.accent.opacity(0.07), .clear], startPoint: .topLeading, endPoint: .bottomTrailing)
                }
        }
    }
}

extension View {
    @ViewBuilder func bentoGlassContainer() -> some View {
        if #available(macOS 26.0, *) { GlassEffectContainer(spacing: 12) { self } }
        else { self }
    }
}
