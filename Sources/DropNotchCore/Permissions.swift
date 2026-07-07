import AppKit
import ApplicationServices
import CoreGraphics

public enum Permissions {
    public static var screenRecordingGranted: Bool { CGPreflightScreenCaptureAccess() }
    public static var accessibilityGranted: Bool { AXIsProcessTrusted() }
    public static var allGranted: Bool { screenRecordingGranted && accessibilityGranted }

    public static func requestScreenRecording() {
        CGRequestScreenCaptureAccess()
    }

    public static func promptAccessibility() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
    }

    public static func openScreenRecordingSettings() {
        open("x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")
    }

    public static func openAccessibilitySettings() {
        open("x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
    }

    private static func open(_ urlString: String) {
        guard let url = URL(string: urlString) else { return }
        NSWorkspace.shared.open(url)
    }
}
