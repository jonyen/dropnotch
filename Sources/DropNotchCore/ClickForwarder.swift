import AppKit
import CoreGraphics
import os.log

/// Activates a real status item: AXPress first, synthetic click fallback.
public final class ClickForwarder {
    private let axSource: AXItemSource
    private let log = Logger(subsystem: DropNotchInfo.logSubsystem, category: "click")

    public init(axSource: AXItemSource) {
        self.axSource = axSource
    }

    public func activate(_ item: MenuBarItemInfo) {
        // AX press can block for seconds while a stale app connection wakes
        // up; keep it off the main thread.
        DispatchQueue.global(qos: .userInitiated).async { [self] in
            let height = CGDisplayBounds(CGMainDisplayID()).height
            if axSource.pressItem(pid: item.ownerPID, nearCocoaX: item.frame.midX, mainDisplayHeight: height) {
                return
            }
            log.info("AXPress failed for \(item.ownerName), falling back to synthetic click")
            syntheticClick(at: CGPoint(x: item.frame.midX, y: item.frame.midY), mainDisplayHeight: height)
        }
    }

    private func syntheticClick(at cocoaPoint: CGPoint, mainDisplayHeight: CGFloat) {
        let point = NotchGeometry.cgPoint(fromCocoaPoint: cocoaPoint, mainDisplayHeight: mainDisplayHeight)
        guard let down = CGEvent(mouseEventSource: nil, mouseType: .leftMouseDown,
                                 mouseCursorPosition: point, mouseButton: .left),
              let up = CGEvent(mouseEventSource: nil, mouseType: .leftMouseUp,
                               mouseCursorPosition: point, mouseButton: .left)
        else {
            log.error("failed to create CGEvent for synthetic click")
            return
        }
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
    }
}
