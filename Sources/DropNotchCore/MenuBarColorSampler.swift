import AppKit
import ScreenCaptureKit
import os.log

/// Samples the menu bar's rendered color (blurred wallpaper) so the panel
/// can match it. Reads a small strip just right of the notch — usually free
/// of icons.
public final class MenuBarColorSampler {
    private let log = Logger(subsystem: DropNotchInfo.logSubsystem, category: "sampler")

    public init() {}

    /// Average color of the menu bar strip beside the notch. `notch` in
    /// Cocoa coords; x values are shared between coordinate systems.
    public func sample(notch: CGRect) async -> NSColor? {
        // See SCKIconCapturer: never let a capture attempt raise the
        // permission dialog. Untinted panel is the graceful degradation.
        guard Permissions.screenRecordingGranted else { return nil }
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            guard let display = content.displays.first(where: { $0.displayID == CGMainDisplayID() }) else {
                return nil
            }
            let filter = SCContentFilter(display: display, excludingWindows: [])
            let config = SCStreamConfiguration()
            // Strip just right of the notch, a few points into the menu bar.
            config.sourceRect = CGRect(x: notch.maxX + 8, y: 6, width: 40, height: 16)
            config.width = 8
            config.height = 3
            config.showsCursor = false
            let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
            return Self.averageColor(of: image)
        } catch {
            log.info("menu bar sample failed: \(error.localizedDescription)")
            return nil
        }
    }

    static func averageColor(of image: CGImage) -> NSColor? {
        guard let ctx = CGContext(
            data: nil, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        ctx.interpolationQuality = .medium
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: 1, height: 1))
        guard let data = ctx.data else { return nil }
        let p = data.bindMemory(to: UInt8.self, capacity: 4)
        return NSColor(red: CGFloat(p[0]) / 255, green: CGFloat(p[1]) / 255,
                       blue: CGFloat(p[2]) / 255, alpha: 1)
    }
}
