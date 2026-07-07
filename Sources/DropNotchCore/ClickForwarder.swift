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

    /// Synthesize a cmd+drag of the real status item to a new menu bar
    /// position — the same gesture the user would make in the menu bar.
    /// Only effective when the item still has a window to hit-test.
    public func moveItem(_ item: MenuBarItemInfo, toCocoa target: CGPoint) {
        DispatchQueue.global(qos: .userInitiated).async { [self] in
            let height = CGDisplayBounds(CGMainDisplayID()).height
            let start = NotchGeometry.cgPoint(
                fromCocoaPoint: CGPoint(x: item.frame.midX, y: item.frame.midY),
                mainDisplayHeight: height)
            let end = NotchGeometry.cgPoint(fromCocoaPoint: target, mainDisplayHeight: height)
            guard let down = CGEvent(mouseEventSource: nil, mouseType: .leftMouseDown,
                                     mouseCursorPosition: start, mouseButton: .left) else { return }
            down.flags = .maskCommand
            down.post(tap: .cghidEventTap)
            let steps = 12
            for i in 1...steps {
                let t = CGFloat(i) / CGFloat(steps)
                let p = CGPoint(x: start.x + (end.x - start.x) * t,
                                y: start.y + (end.y - start.y) * t)
                let drag = CGEvent(mouseEventSource: nil, mouseType: .leftMouseDragged,
                                   mouseCursorPosition: p, mouseButton: .left)
                drag?.flags = .maskCommand
                drag?.post(tap: .cghidEventTap)
                usleep(16_000)
            }
            let up = CGEvent(mouseEventSource: nil, mouseType: .leftMouseUp,
                             mouseCursorPosition: end, mouseButton: .left)
            up?.flags = .maskCommand
            up?.post(tap: .cghidEventTap)
            log.info("synthetic cmd-drag of \(item.ownerName, privacy: .public) to x=\(target.x)")
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
