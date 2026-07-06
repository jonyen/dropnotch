import AppKit
import ServiceManagement

@MainActor
public final class StatusMenuController: NSObject {
    private var statusItem: NSStatusItem!
    private let coordinator: AppCoordinator
    private let pauseItem = NSMenuItem(title: "Pause", action: #selector(togglePause), keyEquivalent: "")
    private let loginItem = NSMenuItem(title: "Launch at Login", action: #selector(toggleLogin), keyEquivalent: "")

    public init(coordinator: AppCoordinator) {
        self.coordinator = coordinator
        super.init()

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(
            systemSymbolName: "rectangle.topthird.inset.filled",
            accessibilityDescription: "DropNotch")

        let menu = NSMenu()
        pauseItem.target = self
        loginItem.target = self
        loginItem.state = SMAppService.mainApp.status == .enabled ? .on : .off
        if !Self.hasNotchedScreen {
            let noNotch = NSMenuItem(title: "No notch on this display", action: nil, keyEquivalent: "")
            noNotch.isEnabled = false
            menu.addItem(noNotch)
            menu.addItem(.separator())
        }
        menu.addItem(pauseItem)
        menu.addItem(loginItem)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit DropNotch", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        statusItem.menu = menu
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
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
                loginItem.state = .off
            } else {
                try SMAppService.mainApp.register()
                loginItem.state = .on
            }
        } catch {
            // Registration fails when running outside an app bundle; ignore.
        }
    }
}
