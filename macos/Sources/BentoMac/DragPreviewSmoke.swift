import AppKit
import BentoCore

@MainActor enum DragPreviewSmoke {
    static func run(system: FixtureWindowSystem) throws -> [String] {
        var passed: [String] = []
        func check(_ condition: Bool, _ label: String) throws {
            guard condition else { throw NSError(domain: "BentoPreviewSmoke", code: 1, userInfo: [NSLocalizedDescriptionKey: label]) }
            passed.append(label)
        }
            let softPreview = DestinationPanel()
            let allPreviewSlots = [Rect(40, 40, 240, 220), Rect(290, 40, 240, 220), Rect(40, 270, 490, 220)]
            softPreview.animate = false
            let draggedPanel = system.records[0].1
            draggedPanel.orderFrontRegardless()
            softPreview.presentSlots(allPreviewSlots, belowWindow: draggedPanel.windowNumber)
            try check(softPreview.visibleSlotFrames == allPreviewSlots && softPreview.selectedSlotCount == 0,
                "Dragging shows every slot even without a selected destination")
            softPreview.presentConflict(allPreviewSlots[1], slots: allPreviewSlots, belowWindow: draggedPanel.windowNumber)
            try check(softPreview.visibleSlotFrames.count == 3 && softPreview.selectedSlotCount == 1,
                "Selecting a destination keeps unchanged slots visible and highlights only the selected slot")
            softPreview.animate = true
            softPreview.presentConflict(allPreviewSlots[2], slots: allPreviewSlots, belowWindow: draggedPanel.windowNumber)
            try check(softPreview.visibleSlotFrames.count == allPreviewSlots.count && allPreviewSlots.allSatisfy { softPreview.visibleSlotFrames.contains($0) },
                "Changing selected slots never moves previews through unrelated positions")
            let exactSlot = PreviewSlotView(frame: NSRect(x: 0, y: 0, width: 320, height: 240))
            try check(exactSlot.materialBounds == exactSlot.bounds,
                "Slot material fills the exact native window bounds without an inset")
            // WindowServer publishes newly ordered windows after AppKit flushes
            // the current event. Wait for those fixture panels, then check order.
            var previewOrder: [Int] = []
            let deadline = Date(timeIntervalSinceNow: 0.5)
            repeat {
                RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.02))
                previewOrder = (CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []).compactMap { ($0[kCGWindowNumber as String] as? NSNumber)?.intValue }
                if let dragIndex = previewOrder.firstIndex(of: draggedPanel.windowNumber),
                   softPreview.previewWindowNumbers.allSatisfy({ number in previewOrder.firstIndex(of: number).map { $0 > dragIndex } == true }) { break }
            } while Date() < deadline
            let dragIndex = previewOrder.firstIndex(of: draggedPanel.windowNumber)
            try check(dragIndex != nil && softPreview.previewWindowNumbers.allSatisfy { number in
                previewOrder.firstIndex(of: number).map { $0 > dragIndex! } == true
            }, "The dragged native window stays above every blurred destination panel")
            softPreview.hideImmediately()
        let resizing = DestinationPanel(reduceMotion: { false })
        let firstID = UUID(), secondID = UUID()
        let left = Rect(40, 40, 240, 220), right = Rect(290, 40, 240, 220)
        resizing.animate = false
        resizing.windowFrames = [firstID: left, secondID: right]
        resizing.presentSlots([left, right])
        resizing.animate = true
        resizing.windowFrames = [firstID: right, secondID: left]
        resizing.presentSlots([right, left])
        try check(Set(resizing.visibleSlotFrames.map { "\($0)" }) == Set([left, right].map { "\($0)" }),
            "Swapping window identities keeps slot surfaces at their destinations without travel")
        let smaller = Rect(290, 40, 180, 220)
        resizing.windowFrames[firstID] = smaller
        resizing.presentSlots([smaller, left])
        try check(resizing.visibleSlotFrames.contains(smaller), "Slot resize immediately shows exact final bounds with animations enabled")
        let stablePanels = Set(resizing.previewWindowNumbers)
        for index in 0..<4 {
            resizing.presentConflict(index.isMultiple(of: 2) ? smaller : left, slots: [smaller, left])
            try check(resizing.visibleSlotFrames.contains(smaller) && resizing.visibleSlotFrames.contains(left),
                "Selection changes preserve exact static slot bounds \(index)")
        }
        try check(Set(resizing.previewWindowNumbers) == stablePanels && resizing.visibleSlotFrames.count == 2,
            "Repeated highlights reuse panels without ghost slots")
        resizing.windowFrames[firstID] = right
        resizing.presentSlots([right, left])
        try check(resizing.visibleSlotFrames.contains(right), "A reversed resize applies immediately")
        resizing.windowFrames[firstID] = smaller
        resizing.presentSlots([smaller, left])
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.35))
        try check(resizing.visibleSlotFrames.contains(smaller), "No delayed preview animation overwrites the latest geometry")
        let merged = Rect(40, 40, 490, 220)
        resizing.windowFrames = [firstID: merged]
        resizing.presentSlots([merged])
        try check(resizing.visibleSlotFrames.count == 1, "Merging removes obsolete slot surfaces without overlapping ghosts")
        resizing.hideImmediately()
        let tint = PausedTintView(frame: NSRect(x: 0, y: 0, width: 80, height: 80))
        let bitmap = tint.bitmapImageRepForCachingDisplay(in: tint.bounds)!
        tint.cacheDisplay(in: tint.bounds, to: bitmap)
        try check((bitmap.colorAt(x: 0, y: 0)?.alphaComponent ?? 1) < 0.01
            && (bitmap.colorAt(x: 40, y: 40)?.alphaComponent ?? 0) > 0.25,
            "Paused tint keeps rounded corners transparent while dimming window content")
        return passed
    }
}
