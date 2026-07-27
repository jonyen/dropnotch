import CoreGraphics

/// Proportional layout for the app icon, so every size renders from one
/// routine. All metrics are fractions of the squircle's side, which is itself
/// a fraction of the canvas (the macOS icon grid leaves a margin for shadow).
public enum IconGeometry {
    /// macOS draws app icons inset within their canvas.
    static let squircleScale: CGFloat = 824.0 / 1024.0

    static let notchWidthRatio: CGFloat = 0.52
    static let notchHeightRatio: CGFloat = 0.22
    static let notchCornerRatio: CGFloat = 0.075
    static let dotRadiusRatio: CGFloat = 0.058
    static let dotSpacingRatio: CGFloat = 0.175
    static let dotDropRatio: CGFloat = 0.24
    static let squircleCornerRatio: CGFloat = 0.225

    public static func squircleRect(in canvas: CGRect) -> CGRect {
        let side = min(canvas.width, canvas.height) * squircleScale
        return CGRect(x: canvas.midX - side / 2, y: canvas.midY - side / 2,
                      width: side, height: side)
    }

    static func side(in canvas: CGRect) -> CGFloat {
        min(canvas.width, canvas.height) * squircleScale
    }

    /// The notch hangs from the top edge of the squircle: square where it meets
    /// the bezel, rounded along the bottom — the hardware profile.
    public static func notchRect(in canvas: CGRect) -> CGRect {
        let squircle = squircleRect(in: canvas)
        let s = side(in: canvas)
        let width = s * notchWidthRatio
        let height = s * notchHeightRatio
        return CGRect(x: squircle.midX - width / 2, y: squircle.maxY - height,
                      width: width, height: height)
    }

    public static func notchCornerRadius(in canvas: CGRect) -> CGFloat {
        side(in: canvas) * notchCornerRatio
    }

    public static func squircleCornerRadius(in canvas: CGRect) -> CGFloat {
        side(in: canvas) * squircleCornerRatio
    }

    public static func dotRadius(in canvas: CGRect) -> CGFloat {
        side(in: canvas) * dotRadiusRatio
    }

    /// Menu bar items spilling out from under the notch, centred beneath it.
    public static func dotCentres(in canvas: CGRect, count: Int) -> [CGPoint] {
        guard count > 0 else { return [] }
        let squircle = squircleRect(in: canvas)
        let s = side(in: canvas)
        let notch = notchRect(in: canvas)
        let y = notch.minY - s * dotDropRatio
        let spacing = s * dotSpacingRatio
        let firstOffset = -spacing * CGFloat(count - 1) / 2
        return (0..<count).map {
            CGPoint(x: squircle.midX + firstOffset + spacing * CGFloat($0), y: y)
        }
    }

    /// Three dots merge into a smudge below 64px; drop to one so the small
    /// variants stay legible in Login Items and Finder list views.
    public static func dotCount(forPixelSize size: Int) -> Int {
        size <= 32 ? 1 : 3
    }
}
