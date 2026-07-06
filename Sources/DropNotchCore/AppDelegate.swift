import AppKit
import os.log

public final class AppDelegate: NSObject, NSApplicationDelegate {
    private var coordinator: AppCoordinator?
    private var statusMenu: StatusMenuController?
    private var onboardingWindow: NSWindow?
    private let log = Logger(subsystem: DropNotchInfo.logSubsystem, category: "app")

    public override init() { super.init() }

    public func applicationDidFinishLaunching(_ notification: Notification) {
        log.info("didFinishLaunching: screenRecording=\(Permissions.screenRecordingGranted, privacy: .public) accessibility=\(Permissions.accessibilityGranted, privacy: .public)")
        let coordinator = AppCoordinator()
        self.coordinator = coordinator
        statusMenu = StatusMenuController(coordinator: coordinator)
        log.info("status item created")

        if Permissions.allGranted {
            log.info("permissions granted, starting coordinator")
            coordinator.start()
        } else {
            log.info("permissions missing, showing onboarding")
            showOnboarding()
        }
    }

    public func applicationDidBecomeActive(_ notification: Notification) {
        // Re-check after the user visits System Settings.
        log.info("didBecomeActive: allGranted=\(Permissions.allGranted, privacy: .public)")
        if Permissions.allGranted, let coordinator {
            onboardingWindow?.close()
            onboardingWindow = nil
            coordinator.start()
        }
    }

    private func showOnboarding() {
        Permissions.requestScreenRecording()
        Permissions.promptAccessibility()

        let alertText = """
        DropNotch needs two permissions:

        • Screen Recording — to show live images of hidden menu bar icons
        • Accessibility — to click them for you

        Grant both in System Settings, then relaunch DropNotch.
        """
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 220),
            styleMask: [.titled, .closable],
            backing: .buffered, defer: false)
        window.title = "DropNotch Permissions"
        // ARC owns this window via `onboardingWindow`; the AppKit default
        // (release-when-closed) would double-release it on close.
        window.isReleasedWhenClosed = false
        window.center()

        let text = NSTextField(wrappingLabelWithString: alertText)
        let screenButton = NSButton(title: "Open Screen Recording Settings",
                                    target: self, action: #selector(openScreenSettings))
        let axButton = NSButton(title: "Open Accessibility Settings",
                                target: self, action: #selector(openAXSettings))
        let stack = NSStackView(views: [text, screenButton, axButton])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 12
        stack.edgeInsets = NSEdgeInsets(top: 20, left: 20, bottom: 20, right: 20)
        window.contentView = stack

        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        onboardingWindow = window
    }

    @objc private func openScreenSettings() { Permissions.openScreenRecordingSettings() }
    @objc private func openAXSettings() { Permissions.openAccessibilitySettings() }
}
