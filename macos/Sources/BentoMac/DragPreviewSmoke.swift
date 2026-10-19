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
            // WindowServer publishes newly ordered windows after AppKit flushes
            // the current event. Wait for those fixture panels, then check order.
            var previewOrder: [Int] = []
            let deadline = Date(timeIntervalSinceNow: 0.5)
            repeat {
                RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.02))
                previewOrder = (CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []).compactMap { ($0[kCGWindowNumber as String] as? NSNumber)?.intValue }
                if softPreview.previewWindowNumbers.allSatisfy({ previewOrder.contains($0) }) { break }
            } while Date() < deadline
            let dragIndex = previewOrder.firstIndex(of: draggedPanel.windowNumber)
            try check(dragIndex != nil && softPreview.previewWindowNumbers.allSatisfy { number in
                previewOrder.firstIndex(of: number).map { $0 > dragIndex! } == true
            }, "The dragged native window stays above every blurred destination panel")
            softPreview.hideImmediately()
        return passed
    }
}
