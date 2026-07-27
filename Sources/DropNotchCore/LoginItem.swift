import Foundation
import ServiceManagement
import os.log

/// Launch-at-login registration, gated on running from a real .app bundle.
///
/// A bare `swift build` binary can register itself with `SMAppService.mainApp`
/// just fine — the call does *not* fail outside a bundle. macOS then launches
/// that binary at every login, where it has no Info.plist (so it takes a Dock
/// icon) and a different code identity from the signed app (so it holds none
/// of the app's TCC grants and re-asks for permissions). Only the bundled app
/// may register; a dev run cleans up any registration a past dev run left.
public enum LoginItem {
    private static let log = Logger(subsystem: DropNotchInfo.logSubsystem, category: "loginitem")
    private static let autoEnabledKey = "didAutoEnableLoginItem"

    static func isAppBundle(_ url: URL) -> Bool {
        url.pathExtension == "app"
    }

    /// True when this process runs from a .app bundle rather than a loose binary.
    public static var isBundled: Bool { isAppBundle(Bundle.main.bundleURL) }

    public static var isEnabled: Bool { SMAppService.mainApp.status == .enabled }

    @discardableResult
    public static func setEnabled(_ enabled: Bool) -> Bool {
        guard isBundled else { return false }
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            return true
        } catch {
            log.error("login item \(enabled ? "register" : "unregister") failed: \(error.localizedDescription)")
            return false
        }
    }

    /// Launch at login defaults to on, once, for the bundled app only. A user
    /// who later turns the menu toggle off stays off.
    public static func autoEnableOnFirstRun(defaults: UserDefaults = .standard) {
        guard isBundled, !defaults.bool(forKey: autoEnabledKey) else { return }
        guard setEnabled(true) else { return }
        defaults.set(true, forKey: autoEnabledKey)
    }

    /// Undo a registration a previous unbundled run created, so the loose
    /// binary stops launching at login behind the real app's back.
    public static func removeUnbundledRegistration(defaults: UserDefaults = .standard) {
        guard !isBundled else { return }
        guard SMAppService.mainApp.status != .notRegistered else { return }
        do {
            try SMAppService.mainApp.unregister()
            defaults.set(false, forKey: autoEnabledKey)
            log.info("removed stale login item for unbundled binary")
        } catch {
            log.error("stale login item cleanup failed: \(error.localizedDescription)")
        }
    }
}
