import CoreGraphics

/// Pure geometry. All rects Cocoa coordinates (global, bottom-left origin)
/// unless a name says otherwise.
public enum NotchGeometry {
    /// Notch rect = horizontal gap between the two auxiliary top areas.
    /// Returns nil when the screen has no notch.
    public static func notchRect(screenFrame: CGRect, auxLeft: CGRect?, auxRight: CGRect?) -> CGRect? {
        guard let left = auxLeft, let right = auxRight else { return nil }
        let width = right.minX - left.maxX
        guard width > 0 else { return nil }
        return CGRect(x: left.maxX, y: left.minY, width: width, height: left.height)
    }

    /// CGWindowList/CGEvent use top-left-origin global coords; Cocoa uses
    /// bottom-left. Both are anchored to the main display.
    public static func cocoaRect(fromCGRect r: CGRect, mainDisplayHeight: CGFloat) -> CGRect {
        CGRect(x: r.origin.x,
               y: mainDisplayHeight - r.origin.y - r.height,
               width: r.width,
               height: r.height)
    }

    public static func cgPoint(fromCocoaPoint p: CGPoint, mainDisplayHeight: CGFloat) -> CGPoint {
        CGPoint(x: p.x, y: mainDisplayHeight - p.y)
    }
}
