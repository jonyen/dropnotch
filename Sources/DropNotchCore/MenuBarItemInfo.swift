import CoreGraphics

/// One status-item window in the menu bar. `frame` is Cocoa coordinates.
/// `windowID` is nil for items discovered only via Accessibility.
public struct MenuBarItemInfo: Equatable, Hashable {
    public let windowID: UInt32?
    public let ownerPID: pid_t
    public let ownerName: String
    public let frame: CGRect
    public let title: String?
    /// The item's own help/tooltip text (AX "AXHelp"), when the source knows it.
    public let tooltip: String?

    public init(windowID: UInt32?, ownerPID: pid_t, ownerName: String, frame: CGRect, title: String?,
                tooltip: String? = nil) {
        self.windowID = windowID
        self.ownerPID = ownerPID
        self.ownerName = ownerName
        self.frame = frame
        self.title = title
        self.tooltip = tooltip
    }

    /// Same item, with a window ID discovered later (e.g. matched from CGWindowList).
    public func withWindowID(_ id: UInt32?) -> MenuBarItemInfo {
        MenuBarItemInfo(windowID: id, ownerPID: ownerPID, ownerName: ownerName,
                        frame: frame, title: title, tooltip: tooltip)
    }
}
