import AppKit
import CoreImage
import ScreenCaptureKit
import os.log

public protocol IconCapturing {
    /// Live pixels of the item's window; bundle icon if capture impossible.
    func captureIcon(for item: MenuBarItemInfo) async -> NSImage
}

public final class SCKIconCapturer: IconCapturing {
    private let log = Logger(subsystem: DropNotchInfo.logSubsystem, category: "capture")

    public init() {}

    public func captureIcon(for item: MenuBarItemInfo) async -> NSImage {
        if let windowID = item.windowID, let image = await captureWindow(windowID: windowID) {
            return image
        }
        return fallbackIcon(for: item)
    }

    private func captureWindow(windowID: UInt32) async -> NSImage? {
        // Touching ScreenCaptureKit without the grant makes macOS raise the
        // permission dialog. Asking is the status menu's job, so fall back to
        // bundle icons instead.
        guard Permissions.screenRecordingGranted else { return nil }
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
            guard let window = content.windows.first(where: { $0.windowID == windowID }) else {
                log.info("window \(windowID) not in shareable content")
                return nil
            }
            let filter = SCContentFilter(desktopIndependentWindow: window)
            let config = SCStreamConfiguration()
            let scale: CGFloat = 2 // capture at retina scale
            config.width = max(1, Int(window.frame.width * scale))
            config.height = max(1, Int(window.frame.height * scale))
            config.showsCursor = false
            let cgImage = try await SCScreenshotManager.captureImage(
                contentFilter: filter, configuration: config)
            return NSImage(cgImage: cgImage,
                           size: NSSize(width: window.frame.width, height: window.frame.height))
        } catch {
            log.error("capture failed for window \(windowID): \(error.localizedDescription)")
            return nil
        }
    }

    private func fallbackIcon(for item: MenuBarItemInfo) -> NSImage {
        if let app = NSRunningApplication(processIdentifier: item.ownerPID), let icon = app.icon {
            return MenuBarStyle.monochrome(icon)
        }
        return NSImage(systemSymbolName: "questionmark.circle", accessibilityDescription: item.ownerName)
            ?? NSImage()
    }
}

/// Renders fallback app icons the way the menu bar would draw them: as
/// white template glyphs. Grayscale the icon, flip polarity so the glyph
/// reads bright, then turn luminance into alpha — a white glyph that keeps
/// the icon's internal detail.
enum MenuBarStyle {
    static func monochrome(_ icon: NSImage) -> NSImage {
        let size = NSSize(width: 36, height: 36)
        guard let tiff = icon.tiffRepresentation, let input = CIImage(data: tiff),
              let noirFilter = CIFilter(name: "CIPhotoEffectNoir"),
              let maskFilter = CIFilter(name: "CIMaskToAlpha")
        else { return icon }

        noirFilter.setValue(input, forKey: kCIInputImageKey)
        var gray = noirFilter.outputImage ?? input

        // Predominantly light icons (dark glyph on light tile) must invert,
        // or MaskToAlpha would keep the tile and cut out the glyph.
        if meanLuminance(of: icon) > 0.5, let invert = CIFilter(name: "CIColorInvert") {
            invert.setValue(gray, forKey: kCIInputImageKey)
            gray = invert.outputImage ?? gray
        }

        maskFilter.setValue(gray, forKey: kCIInputImageKey)
        guard let out = maskFilter.outputImage else { return icon }
        let rep = NSCIImageRep(ciImage: out)
        let rendered = NSImage(size: rep.size)
        rendered.addRepresentation(rep)
        return NSImage(size: size, flipped: false) { rect in
            rendered.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 0.95)
            return true
        }
    }

    /// Average brightness of meaningfully-opaque pixels, sampled at 32x32.
    private static func meanLuminance(of icon: NSImage) -> CGFloat {
        let sample = 32
        guard let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: sample, pixelsHigh: sample,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)
        else { return 0 }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        icon.draw(in: NSRect(x: 0, y: 0, width: sample, height: sample))
        NSGraphicsContext.restoreGraphicsState()
        var total: CGFloat = 0
        var count = 0
        for y in 0..<sample {
            for x in 0..<sample {
                guard let color = bitmap.colorAt(x: x, y: y), color.alphaComponent > 0.1 else { continue }
                total += color.brightnessComponent
                count += 1
            }
        }
        return count > 0 ? total / CGFloat(count) : 0
    }
}
