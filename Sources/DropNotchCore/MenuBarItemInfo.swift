import CoreGraphics

/// One status-item window in the menu bar. `frame` is Cocoa coordinates.
/// `windowID` is nil for items discovered only via Accessibility.
public struct MenuBarItemInfo: Equatable, Hashable {
    public let windowID: UInt32?
    public let ownerPID: pid_t
    public let ownerName: String
    public let frame: CGRect
    public let title: String?

    public init(windowID: UInt32?, ownerPID: pid_t, ownerName: String, frame: CGRect, title: String?) {
        self.windowID = windowID
        self.ownerPID = ownerPID
        self.ownerName = ownerName
        self.frame = frame
        self.title = title
    }
}
