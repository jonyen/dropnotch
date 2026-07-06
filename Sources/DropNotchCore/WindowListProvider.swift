import AppKit
import CoreGraphics

public protocol WindowListProviding {
    /// All windows sitting at the menu bar's status level, frames in Cocoa coords.
    func menuBarItemWindows() -> [MenuBarItemInfo]
    /// False while a fullscreen app hides the menu bar.
    func isMenuBarVisible() -> Bool
}

public final class CGWindowListProvider: WindowListProviding {
    public init() {}

    private var mainDisplayHeight: CGFloat {
        CGDisplayBounds(CGMainDisplayID()).height
    }

    public func menuBarItemWindows() -> [MenuBarItemInfo] {
        let statusLevel = Int(CGWindowLevelForKey(.statusWindow))
        guard let list = CGWindowListCopyWindowInfo(
            [.optionAll], kCGNullWindowID) as? [[String: Any]] else { return [] }
        let height = mainDisplayHeight

        return list.compactMap { info in
            guard let layer = info[kCGWindowLayer as String] as? Int, layer == statusLevel,
                  let windowID = info[kCGWindowNumber as String] as? UInt32,
                  let pid = info[kCGWindowOwnerPID as String] as? pid_t,
                  let boundsDict = info[kCGWindowBounds as String] as? [String: CGFloat]
            else { return nil }
            let cgFrame = CGRect(x: boundsDict["X"] ?? 0, y: boundsDict["Y"] ?? 0,
                                 width: boundsDict["Width"] ?? 0, height: boundsDict["Height"] ?? 0)
            return MenuBarItemInfo(
                windowID: windowID,
                ownerPID: pid,
                ownerName: info[kCGWindowOwnerName as String] as? String ?? "?",
                frame: NotchGeometry.cocoaRect(fromCGRect: cgFrame, mainDisplayHeight: height),
                title: info[kCGWindowName as String] as? String)
        }
    }

    public func isMenuBarVisible() -> Bool {
        guard let list = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] else { return true }
        return list.contains { info in
            (info[kCGWindowOwnerName as String] as? String) == "Window Server"
                && (info[kCGWindowName as String] as? String) == "Menubar"
        }
    }
}
