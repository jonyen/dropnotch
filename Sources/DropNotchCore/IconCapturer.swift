import AppKit
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
            return icon
        }
        return NSImage(systemSymbolName: "questionmark.circle", accessibilityDescription: item.ownerName)
            ?? NSImage()
    }
}
