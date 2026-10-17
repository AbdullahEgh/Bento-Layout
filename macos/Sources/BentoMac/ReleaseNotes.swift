import Foundation

struct ReleaseNotes: Identifiable {
    let version: String
    let points: [String]
    var id: String { version }

    // Keep newest first; ship the log with the app so it also works offline.
    static let history: [ReleaseNotes] = [
        .init(version: "0.2.19", points: [
            "Frosted previews, brighter splits and amber conflict feedback.",
            "Liquid Glass across the app, with blur on older systems.",
            "Responsive desktop space and compact release history.",
        ]),
        .init(version: "0.2.18", points: [
            "Soft animated previews without text, icons or hard borders.",
            "Layouts adapt to Dock and menu-bar changes.",
            "Quicker transitions and clearer window controls.",
        ]),
        .init(version: "0.2.17", points: [
            "Move whole sections between screen edges.",
            "Closing a window smoothly expands the remaining slots.",
            "Quieter grabbers, clearer menu states and grouped settings.",
        ]),
        .init(version: "0.2.16", points: [
            "Dock, menu-bar, gaps and margins update live.",
            "Preserve edited slots as desktop space changes.",
            "Make room for new apps with fewer repeated layout attempts.",
        ]),
        .init(version: "0.2.15", points: [
            "Fix Install and Relaunch getting stuck.",
            "Keep edited layouts when turning Bento off and on.",
            "More reliable slot drops, splits and divider limits.",
        ]),
        .init(version: "0.2.14", points: [
            "Resume edited layouts and minimized overflow windows.",
            "Drop floating windows into slots or empty displays.",
            "Respect app size limits during splits and resizing.",
        ]),
        .init(version: "0.2.13", points: [
            "Keep completed moves from snapping back.",
            "Stabilize fast drags, split previews and window changes.",
            "Reduce repeated window reads and redraws.",
        ]),
        .init(version: "0.2.12", points: [
            "Calculate available space before moving windows.",
            "Reuse the least recently used slot when space runs out.",
            "Improve update relaunch and show release notes in the popup.",
        ]),
        .init(version: "0.2.11", points: [
            "Reveal grabbers on hover and keep them visible while held.",
            "Make room for apps opened from the Dock.",
            "Preserve edited layouts when windows fit.",
        ]),
        .init(version: "0.2.10", points: [
            "Resize anywhere in a gap without jumping.",
            "Keep the final position on quick release.",
            "Smoother grabber movement and fewer overlay redraws.",
        ]),
        .init(version: "0.2.9", points: [
            "Reveal hidden grabbers on hover or press.",
            "Settings adapt to narrow windows and displays.",
        ]),
        .init(version: "0.2.8", points: [
            "Wait for apps to finish resizing before checking layouts.",
            "Retry delayed window positions once.",
            "Keep valid layouts when an animation frame is refused.",
        ]),
        .init(version: "0.2.7", points: [
            "Show grabbers on hover, below app windows.",
            "Animate layout changes together.",
            "Minimize overflow windows and save changes automatically.",
        ]),
        .init(version: "0.2.6", points: [
            "Preserve Accessibility approval across signed updates.",
            "Continue verifying update downloads.",
        ]),
        .init(version: "0.2.5", points: [
            "Keep a permanent app identity for future updates.",
            "Verify signing identity before publishing releases.",
        ]),
        .init(version: "0.2.4", points: [
            "Toggle from the menu bar and preview the resulting split.",
            "Faster arrangement and clearer resize grips.",
            "Arrange fitting windows while leaving oversized windows alone.",
        ]),
        .init(version: "0.2.3", points: [
            "Recover when an app refuses resizing.",
            "Preserve valid splits and leave skipped windows untouched.",
        ]),
        .init(version: "0.2.2", points: [
            "Arrange windows that fit without blocking the whole layout.",
            "Show windows left outside the layout.",
            "Limit retries when app size restrictions prevent placement.",
        ]),
        .init(version: "0.2.1", points: [
            "Settings behave like a normal app window.",
            "Clearer Accessibility guidance and activation errors.",
        ]),
        .init(version: "0.2.0", points: [
            "Native window layouts, swaps, splits and gap resizing.",
            "Saved layouts, undo, shortcuts and desktop controls.",
            "Universal Mac app with signed automatic updates.",
        ]),
        .init(version: "0.1.0", points: [
            "Native Mac preview and onboarding.",
            "Layout engine and original Bento artwork.",
        ]),
    ]
}
