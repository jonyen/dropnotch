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

    /// Fire both system prompts, then offer the Settings panes as the
    /// durable fallback. The prompts only show once per app identity and
    /// silently no-op afterwards, so calling on every launch costs nothing
    /// once granted and re-prompts after ad-hoc rebuilds (new identity).
    public static func grantAll() {
        // This is an LSUIElement app that never otherwise activates; the
        // system permission dialogs and the alert would silently fail to
        // appear without an explicit activation.
        NSApp.activate()
        requestScreenRecording()
        promptAccessibility()

        let alert = NSAlert()
        alert.messageText = "DropNotch needs two permissions"
        alert.informativeText = """
        • Screen Recording — to show live images of hidden menu bar icons
        • Accessibility — to click them for you

        Grant both in System Settings, then relaunch DropNotch.
        """
        alert.addButton(withTitle: "Open Screen Recording Settings")
        alert.addButton(withTitle: "Open Accessibility Settings")
        alert.addButton(withTitle: "Later")
        switch alert.runModal() {
        case .alertFirstButtonReturn: openScreenRecordingSettings()
        case .alertSecondButtonReturn: openAccessibilitySettings()
        default: break
        }
        NSApp.hide(nil)
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
