import AppKit
import CoreGraphics

/// Draws the DropNotch app icon: the physical notch, rendered.
///
/// A graphite squircle stands in for the MacBook display, a pure-black notch
/// hangs from its top edge, and white menu bar dots drop out beneath — the
/// items DropNotch reveals.
public enum IconRenderer {
    public static func render(pixelSize: Int) -> CGImage? {
        let canvas = CGRect(x: 0, y: 0, width: CGFloat(pixelSize), height: CGFloat(pixelSize))
        guard let ctx = CGContext(
            data: nil, width: pixelSize, height: pixelSize,
            bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }

        drawBody(in: ctx, canvas: canvas)
        drawNotch(in: ctx, canvas: canvas)
        drawDots(in: ctx, canvas: canvas, pixelSize: pixelSize)
        return ctx.makeImage()
    }

    /// The display: a graphite squircle, lit slightly from the top the way a
    /// screen bezel catches light.
    private static func drawBody(in ctx: CGContext, canvas: CGRect) {
        let squircle = IconGeometry.squircleRect(in: canvas)
        let radius = IconGeometry.squircleCornerRadius(in: canvas)
        let path = CGPath(roundedRect: squircle, cornerWidth: radius,
                          cornerHeight: radius, transform: nil)
        ctx.saveGState()
        ctx.addPath(path)
        ctx.clip()
        let colors = [
            CGColor(red: 0.29, green: 0.31, blue: 0.34, alpha: 1),
            CGColor(red: 0.11, green: 0.12, blue: 0.13, alpha: 1),
        ] as CFArray
        if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                     colors: colors, locations: [0, 1]) {
            ctx.drawLinearGradient(gradient,
                                   start: CGPoint(x: squircle.midX, y: squircle.maxY),
                                   end: CGPoint(x: squircle.midX, y: squircle.minY),
                                   options: [])
        }
        ctx.restoreGState()
    }

    /// Square top corners, rounded bottom ones — matching both the hardware
    /// and the dropdown panel's shape.
    private static func drawNotch(in ctx: CGContext, canvas: CGRect) {
        let notch = IconGeometry.notchRect(in: canvas)
        let r = IconGeometry.notchCornerRadius(in: canvas)
        let path = CGMutablePath()
        path.move(to: CGPoint(x: notch.minX, y: notch.maxY))
        path.addLine(to: CGPoint(x: notch.minX, y: notch.minY + r))
        path.addArc(tangent1End: CGPoint(x: notch.minX, y: notch.minY),
                    tangent2End: CGPoint(x: notch.minX + r, y: notch.minY), radius: r)
        path.addLine(to: CGPoint(x: notch.maxX - r, y: notch.minY))
        path.addArc(tangent1End: CGPoint(x: notch.maxX, y: notch.minY),
                    tangent2End: CGPoint(x: notch.maxX, y: notch.minY + r), radius: r)
        path.addLine(to: CGPoint(x: notch.maxX, y: notch.maxY))
        path.closeSubpath()
        ctx.addPath(path)
        ctx.setFillColor(CGColor(red: 0.03, green: 0.03, blue: 0.04, alpha: 1))
        ctx.fillPath()
    }

    private static func drawDots(in ctx: CGContext, canvas: CGRect, pixelSize: Int) {
        let count = IconGeometry.dotCount(forPixelSize: pixelSize)
        let radius = IconGeometry.dotRadius(in: canvas)
        ctx.setFillColor(CGColor(red: 0.96, green: 0.96, blue: 0.97, alpha: 1))
        for centre in IconGeometry.dotCentres(in: canvas, count: count) {
            ctx.fillEllipse(in: CGRect(x: centre.x - radius, y: centre.y - radius,
                                       width: radius * 2, height: radius * 2))
        }
    }
}
