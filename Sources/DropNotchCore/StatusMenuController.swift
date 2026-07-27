import AppKit

@MainActor
public final class StatusMenuController: NSObject, NSMenuDelegate {
    private var statusItem: NSStatusItem!
    private let coordinator: AppCoordinator
    private let pauseItem = NSMenuItem(title: "Pause", action: #selector(togglePause), keyEquivalent: "")
    private let loginItem = NSMenuItem(title: "Launch at Login", action: #selector(toggleLogin), keyEquivalent: "")
    private let permissionsItem = NSMenuItem(title: "Grant Permissions…", action: #selector(grantPermissions), keyEquivalent: "")
    private let permissionsSeparator = NSMenuItem.separator()

    public init(coordinator: AppCoordinator) {
        self.coordinator = coordinator
        super.init()

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(
            systemSymbolName: "rectangle.topthird.inset.filled",
            accessibilityDescription: "DropNotch")

        let menu = NSMenu()
        menu.delegate = self
        pauseItem.target = self
        loginItem.target = self
        permissionsItem.target = self
        LoginItem.autoEnableOnFirstRun()
        loginItem.state = LoginItem.isEnabled ? .on : .off
        loginItem.isEnabled = LoginItem.isBundled
        if !Self.hasNotchedScreen {
            let noNotch = NSMenuItem(title: "No notch on this display", action: nil, keyEquivalent: "")
            noNotch.isEnabled = false
            menu.addItem(noNotch)
            menu.addItem(.separator())
        }
        menu.addItem(permissionsItem)
        menu.addItem(permissionsSeparator)
        menu.addItem(pauseItem)
        menu.addItem(loginItem)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit DropNotch", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        statusItem.menu = menu
        refreshPermissionsItem()
    }

    // MARK: - Menu state

    public func menuNeedsUpdate(_ menu: NSMenu) {
        refreshPermissionsItem()
        loginItem.state = LoginItem.isEnabled ? .on : .off
    }

    /// The permissions entry is the only place DropNotch ever asks, so it
    /// stays out of the menu entirely once both grants are in place.
    private func refreshPermissionsItem() {
        let missing = !Permissions.allGranted
        permissionsItem.isHidden = !missing
        permissionsSeparator.isHidden = !missing
    }

    /// Asking is user-initiated: the system dialogs only fire from this menu
    /// item, never at launch. `CGRequestScreenCaptureAccess` shows its dialog
    /// once per app identity and silently returns false afterwards, so the
    /// alert offers the System Settings panes as the durable fallback.
    @objc private func grantPermissions() {
        Permissions.requestScreenRecording()
        Permissions.promptAccessibility()

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
        case .alertFirstButtonReturn: Permissions.openScreenRecordingSettings()
        case .alertSecondButtonReturn: Permissions.openAccessibilitySettings()
        default: break
        }
    }

    private static var hasNotchedScreen: Bool {
        NSScreen.screens.contains { screen in
            NotchGeometry.notchRect(screenFrame: screen.frame,
                                    auxLeft: screen.auxiliaryTopLeftArea,
                                    auxRight: screen.auxiliaryTopRightArea) != nil
        }
    }

    @objc private func togglePause() {
        coordinator.isPaused.toggle()
        pauseItem.state = coordinator.isPaused ? .on : .off
    }

    @objc private func toggleLogin() {
        let wantEnabled = !LoginItem.isEnabled
        guard LoginItem.setEnabled(wantEnabled) else { return }
        loginItem.state = wantEnabled ? .on : .off
    }
}
