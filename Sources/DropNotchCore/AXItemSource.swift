import AppKit
import ApplicationServices

import os.log

/// Secondary discovery + click path via the Accessibility API.
/// Enumerates each running app's "extras menu bar" (its status items).
public final class AXItemSource {
    private let log = Logger(subsystem: DropNotchInfo.logSubsystem, category: "ax")

    public init() {}

    /// Status items discoverable via AX, frames in Cocoa coords, windowID nil.
    public func items() -> [MenuBarItemInfo] {
        let height = CGDisplayBounds(CGMainDisplayID()).height
        var result: [MenuBarItemInfo] = []
        for app in NSWorkspace.shared.runningApplications where app.activationPolicy != .prohibited && app.bundleIdentifier != nil {
            let pid = app.processIdentifier
            guard pid > 0 else { continue }
            for element in extrasChildren(pid: pid) {
                guard let cgFrame = frame(of: element) else { continue }
                result.append(MenuBarItemInfo(
                    windowID: nil,
                    ownerPID: pid,
                    ownerName: app.localizedName ?? "?",
                    frame: NotchGeometry.cocoaRect(fromCGRect: cgFrame, mainDisplayHeight: height),
                    title: title(of: element),
                    tooltip: stringAttribute(kAXHelpAttribute, of: element)))
            }
        }
        return result
    }

    /// Press the status item of `pid` whose x-center is closest to
    /// `nearCocoaX`. Tries AXPress, then AXShowMenu (some apps only
    /// implement one).
    public func pressItem(pid: pid_t, nearCocoaX: CGFloat, mainDisplayHeight: CGFloat) -> Bool {
        let children = extrasChildren(pid: pid)
        guard !children.isEmpty else {
            log.info("pressItem pid=\(pid): no AX extras children")
            return false
        }
        let target: AXUIElement
        if children.count == 1 {
            target = children[0]
        } else {
            target = children.min { a, b in
                distance(of: a, toCocoaX: nearCocoaX, mainDisplayHeight: mainDisplayHeight)
                    < distance(of: b, toCocoaX: nearCocoaX, mainDisplayHeight: mainDisplayHeight)
            } ?? children[0]
        }
        // Pressing can legitimately take a while (the app runs its menu
        // handler); don't let the discovery timeout abort it.
        AXUIElementSetMessagingTimeout(target, 2.0)
        for action in [kAXPressAction, "AXShowMenu"] {
            let result = AXUIElementPerformAction(target, action as CFString)
            log.info("pressItem pid=\(pid) action=\(action, privacy: .public) result=\(result.rawValue)")
            if result == .success { return true }
        }
        return false
    }

    // MARK: - AX plumbing

    private func extrasChildren(pid: pid_t) -> [AXUIElement] {
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.1)
        var extrasRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, "AXExtrasMenuBar" as CFString, &extrasRef) == .success,
              let extras = extrasRef, CFGetTypeID(extras) == AXUIElementGetTypeID()
        else { return [] }
        var childrenRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(extras as! AXUIElement, kAXChildrenAttribute as CFString, &childrenRef) == .success,
              let children = childrenRef as? [AXUIElement]
        else { return [] }
        return children
    }

    /// Frame in CG (top-left) coords.
    private func frame(of element: AXUIElement) -> CGRect? {
        var posRef: CFTypeRef?
        var sizeRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &posRef) == .success,
              AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &sizeRef) == .success
        else { return nil }
        guard let posRef = posRef, CFGetTypeID(posRef) == AXValueGetTypeID(),
              let sizeRef = sizeRef, CFGetTypeID(sizeRef) == AXValueGetTypeID()
        else { return nil }
        var point = CGPoint.zero
        var size = CGSize.zero
        guard AXValueGetValue(posRef as! AXValue, .cgPoint, &point),
              AXValueGetValue(sizeRef as! AXValue, .cgSize, &size)
        else { return nil }
        return CGRect(origin: point, size: size)
    }

    private func title(of element: AXUIElement) -> String? {
        stringAttribute(kAXTitleAttribute, of: element)
    }

    private func stringAttribute(_ attribute: String, of element: AXUIElement) -> String? {
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &ref) == .success else { return nil }
        let value = ref as? String
        return (value?.isEmpty ?? true) ? nil : value
    }

    private func distance(of element: AXUIElement, toCocoaX x: CGFloat, mainDisplayHeight: CGFloat) -> CGFloat {
        guard let cgFrame = frame(of: element) else { return .greatestFiniteMagnitude }
        let cocoa = NotchGeometry.cocoaRect(fromCGRect: cgFrame, mainDisplayHeight: mainDisplayHeight)
        return abs(cocoa.midX - x)
    }
}
