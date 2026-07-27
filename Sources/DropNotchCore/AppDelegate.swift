import AppKit
import os.log

public final class AppDelegate: NSObject, NSApplicationDelegate {
    private var coordinator: AppCoordinator?
    private var statusMenu: StatusMenuController?
    private let log = Logger(subsystem: DropNotchInfo.logSubsystem, category: "app")

    public override init() { super.init() }

    public func applicationDidFinishLaunching(_ notification: Notification) {
        log.info("didFinishLaunching: bundled=\(LoginItem.isBundled, privacy: .public) screenRecording=\(Permissions.screenRecordingGranted, privacy: .public) accessibility=\(Permissions.accessibilityGranted, privacy: .public)")

        // Belt and braces with the bundle's LSUIElement: a loose dev binary
        // has no Info.plist and would otherwise take a Dock icon.
        NSApp.setActivationPolicy(.accessory)
        LoginItem.removeUnbundledRegistration()

        let coordinator = AppCoordinator()
        self.coordinator = coordinator
        statusMenu = StatusMenuController(coordinator: coordinator)
        log.info("status item created")

        // Start regardless of permissions: launch stays silent, and the
        // feature degrades on its own (AX-less scanning, bundle-icon
        // fallbacks) until the user grants from the status menu.
        coordinator.start()
    }
}
