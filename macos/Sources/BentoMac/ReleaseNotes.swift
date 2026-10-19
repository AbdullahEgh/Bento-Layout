import Foundation

struct ReleaseNotes: Identifiable {
    let version: String
    let points: [String]
    var id: String { version }

    // Keep newest first; ship the log with the app so it also works offline.
    static let history: [ReleaseNotes] = [
        .init(version: "0.2.42", points: [
            "Prepare native sizes before revealing the first layout.",
            "Pause hides grips and preserves slots; Resume restores window changes.",
            "Rounded pause dimming and brighter selected drag slots.",
            "Show every drag slot, highlight the destination, and keep the dragged window above previews.",
            "One menu-bar click pauses or resumes Bento.",
        ]),
        .init(version: "0.2.41", points: [
            "Fit smaller screens with fewer retries and unnecessary minimizations.",
            "Move and resize freely while paused; Resume restores saved slots.",
        ]),
        .init(version: "0.2.40", points: [
            "Short grips resize two apps; long shared grips resize groups of slots.",
            "Updating or quitting keeps windows in place, including minimized apps.",
            "Installation no longer waits for windows to restore their old positions.",
        ]),
        .init(version: "0.2.39", points: [
            "Shared grips work across partial slot groups, from startup.",
            "Snap feedback follows your divider; full lines stay 45%, short grips 100%.",
            "Glass slots stand out above a full-screen dim.",
            "Grips hide during window drags; previews follow the committed desktop area.",
            "Full-screen apps keep macOS Dock behavior and remember their Bento slots.",
        ]),
        .init(version: "0.2.38", points: [
            "Separated full grips reveal local handles with larger grab areas.",
            "Snapping briefly lights all enabled full grips at full opacity.",
            "Grips stay hidden and inactive in Mission Control.",
            "A gentle dim layer makes destination slots stand out.",
            "Reuse unchanged grip geometry and stop pointer polling while Bento is off.",
        ]),
        .init(version: "0.2.37", points: [
            "Larger local grip targets and full-length straight grips.",
            "Pause starts with every window dimmed; one click brings an app forward.",
            "Hide Dock & Menu Bar now sits above Undo.",
            "Grips stay above dimmed background windows and below floating apps.",
        ]),
        .init(version: "0.2.36", points: [
            "Local grips respond nearby; the rest of the divider moves the full joined row or column.",
            "Snap cues highlight the full universal grip.",
        ]),
        .init(version: "0.2.35", points: [
            "Keep layouts and size limits intact across repeated Dock/menu-bar changes.",
            "Full-length shared grips with matching join cues.",
            "Independent app animations avoid pauses caused by slower windows.",
            "One click brings a paused Bento app above the dim layer.",
        ]),
        .init(version: "0.2.34", points: [
            "Joined splits reveal a gentle full-length cue and all valid shared grips.",
            "Manual resizing adjusts its local section; closed and minimized apps release space sooner.",
            "Pause Bento comes first in the menu, with a right-aligned settings switch.",
            "Smoother coordinated motion and better use of hidden menu-bar space.",
        ]),
        .init(version: "0.2.33", points: [
            "Snap nearby split sections into continuous rows and columns.",
            "Separate joined sections again with the local grips.",
            "Recover smaller window sizes and let Dock changes settle before fitting.",
        ]),
        .init(version: "0.2.32", points: [
            "Resize whole rows or columns, or just the section you hover.",
            "Keep joined boundaries aligned when Dock and menu-bar space changes.",
            "Use the shown menu bar’s actual bounds; stop repeated failed reflows.",
            "System Settings and Bento Settings stay outside the layout.",
        ]),
        .init(version: "0.2.31", points: [
            "Dock changes preserve your layout using actual available space.",
            "Stronger Pin dimming; restored apps rejoin Bento after Unpin.",
        ]),
        .init(version: "0.2.30", points: [
            "Preserve layouts through interruptions and Dock/menu-bar changes.",
            "Use hidden screen space and restore original slot proportions.",
            "Reliable menu-icon hold and longer, quicker grabbers.",
            "Pinned apps dim; click the pin icon to minimize floating apps and return.",
        ]),
        .init(version: "0.2.29", points: [
            "Separate desktop layouts remember their arrangement automatically.",
            "Pin Bento keeps newly opened apps outside the current layout.",
            "Hold the menu icon to toggle Dock and menu-bar hiding.",
            "Brighter grips, fading black backdrop, and better divider alignment.",
            "Quicker Dock and menu-bar space updates.",
        ]),
        .init(version: "0.2.28", points: [
            "Finder and other apps settle reliably into their slots.",
            "Bringing an app forward retries placement automatically.",
            "Size-limit recovery finds a fitting split without repeated shuffling.",
        ]),
        .init(version: "0.2.27", points: [
            "Drag anywhere along an exposed divider to resize its slots.",
            "Gentler window returns, cancellations, and recovery animations.",
        ]),
        .init(version: "0.2.26", points: [
            "Terminal-sized splits tolerate native text-grid rounding.",
            "Bento resumes after minimizing or restoring windows.",
            "Available apps can reshape old slots to fit the display.",
        ]),
        .init(version: "0.2.25", points: [
            "Black background dimming follows your darkness setting.",
        ]),
        .init(version: "0.2.24", points: [
            "Smarter app selection keeps more windows usable at their real size limits.",
            "Flexible splits prioritize recent apps without wasting space.",
            "Restored apps stay usable when no slot can fit them.",
        ]),
        .init(version: "0.2.23", points: [
            "Native Dock and menu-bar hiding updates usable space live.",
            "Safer size-limit handling keeps recent apps in the largest slot.",
        ]),
        .init(version: "0.2.22", points: [
            "Dock and menu-bar changes reclaim desktop space automatically.",
            "Recent apps get priority and a larger starting slot; idle apps make room.",
            "More reliable Vivaldi resizing and visible native window shadows.",
        ]),
        .init(version: "0.2.21", points: [
            "Readable title bars in dark and light modes, with glass content preserved.",
        ]),
        .init(version: "0.2.20", points: [
            "Native title bar, shorter menu and gentle glass slot outlines.",
            "Save for this session to keep windows in place when Bento turns off.",
            "Session saves and desktop hiding reset when Bento restarts.",
        ]),
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
