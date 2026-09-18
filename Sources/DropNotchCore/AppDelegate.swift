import AppKit
import os.log

public final class AppDelegate: NSObject, NSApplicationDelegate {
    private var coordinator: AppCoordinator?
    private let log = Logger(subsystem: DropNotchInfo.logSubsystem, category: "app")

    public override init() { super.init() }

    public func applicationDidFinishLaunching(_ notification: Notification) {
        log.info("didFinishLaunching: bundled=\(LoginItem.isBundled, privacy: .public) screenRecording=\(Permissions.screenRecordingGranted, privacy: .public) accessibility=\(Permissions.accessibilityGranted, privacy: .public)")

        // Belt and braces with the bundle's LSUIElement: a loose dev binary
        // has no Info.plist and would otherwise take a Dock icon.
        NSApp.setActivationPolicy(.accessory)
        LoginItem.removeUnbundledRegistration()
        LoginItem.autoEnableOnFirstRun()

        // No status item: on a full menu bar macOS parks it under the notch,
        // invisible and unclickable, so it only adds clutter. The panel is
        // the app's only surface.
        let coordinator = AppCoordinator()
        self.coordinator = coordinator
        log.info("coordinator created")

        // Start regardless of permissions: launch stays silent, and the
        // feature degrades on its own (AX-less scanning, bundle-icon
        // fallbacks) until the user grants.
        coordinator.start()

        // The status item used to be the ask surface; with it gone the
        // system prompts fire here instead. They're per-identity: each
        // shows once per app identity and silently no-op afterwards, so a
        // declined prompt re-fires on the next launch and ad-hoc rebuilds
        // (fresh identity) re-prompt automatically.
        if !Permissions.allGranted {
            Permissions.grantAll()
        }
    }
}
