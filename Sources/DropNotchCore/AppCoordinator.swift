import AppKit
import os.log

/// Wires mouse monitoring, the hover state machine, scanning, capture,
/// the panel, and click forwarding.
@MainActor
public final class AppCoordinator {
    private let stateMachine = HoverStateMachine()
    private let windowList: WindowListProviding
    private let axSource: AXItemSource
    private let capturer: IconCapturing
    private let panelController = NotchPanelController()
    private let clickForwarder: ClickForwarder
    private let colorSampler = MenuBarColorSampler()
    private let log = Logger(subsystem: DropNotchInfo.logSubsystem, category: "coordinator")

    private var globalMouseMonitor: Any?
    private var localMouseMonitor: Any?
    private var graceTimer: Timer?
    private var refreshTimer: Timer?
    private var refreshTask: Task<Void, Never>?
    private var lastPanelItems: [PanelItem] = []

    public var isPaused = false {
        didSet { if isPaused { hidePanel() } }
    }

    public init(windowList: WindowListProviding = CGWindowListProvider(),
                axSource: AXItemSource = AXItemSource(),
                capturer: IconCapturing = SCKIconCapturer()) {
        self.windowList = windowList
        self.axSource = axSource
        self.capturer = capturer
        self.clickForwarder = ClickForwarder(axSource: axSource)
        panelController.onItemClick = { [weak self] entry in
            self?.log.debug("panel click: \(entry.info.ownerName, privacy: .public)")
            // Vanish instantly so the item's real menu opens into clear
            // space instead of behind a sliding panel.
            self?.hidePanel(animated: false)
            self?.clickForwarder.activate(entry.info)
        }
        panelController.onReorder = { [weak self] items in
            PanelOrder.save(items.compactMap { $0.info.ownerName })
            self?.lastPanelItems = items
        }
        panelController.onDragToMenuBar = { [weak self] item, target in
            self?.log.debug("drag to menu bar: \(item.ownerName, privacy: .public) x=\(target.x)")
            self?.hidePanel(animated: false)
            self?.clickForwarder.moveItem(item, toCocoa: target)
        }
    }

    public func start() {
        guard globalMouseMonitor == nil else { return }
        // Global monitor misses events over our own panel; local monitor covers those.
        globalMouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: .mouseMoved) { [weak self] event in
            Task { @MainActor in self?.handleMouseMoved() }
        }
        localMouseMonitor = NSEvent.addLocalMonitorForEvents(matching: .mouseMoved) { [weak self] event in
            Task { @MainActor in self?.handleMouseMoved() }
            return event
        }
    }

    public func stop() {
        if let monitor = globalMouseMonitor { NSEvent.removeMonitor(monitor) }
        if let monitor = localMouseMonitor { NSEvent.removeMonitor(monitor) }
        globalMouseMonitor = nil
        localMouseMonitor = nil
        hidePanel()
    }

    // MARK: - Hover handling

    private var builtInScreen: NSScreen? {
        NSScreen.screens.first {
            CGDisplayIsBuiltin($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID ?? 0) != 0
        }
    }

    private var notchRect: CGRect? {
        guard let screen = builtInScreen else { return nil }
        return NotchGeometry.notchRect(
            screenFrame: screen.frame,
            auxLeft: screen.auxiliaryTopLeftArea,
            auxRight: screen.auxiliaryTopRightArea)
    }

    private func handleMouseMoved() {
        guard !isPaused, let notch = notchRect else { return }
        if stateMachine.isIdle {
            guard notch.contains(NSEvent.mouseLocation) else { return }
            guard windowList.isMenuBarVisible() else { return }
            // Don't drop the panel on top of an open menu (e.g. the one the
            // user just opened from the panel).
            guard !windowList.isPopUpMenuOpen() else { return }
        }
        // Pad the panel's hover region so grazing its edge doesn't hide it.
        let action = stateMachine.mouseMoved(
            to: NSEvent.mouseLocation,
            notch: notch,
            panel: panelController.panelFrame?.insetBy(dx: -12, dy: -12),
            now: Date())
        perform(action, notch: notch)
    }

    private func perform(_ action: HoverAction, notch: CGRect) {
        switch action {
        case .show: showPanel(notch: notch)
        case .hide: hidePanel()
        case .none: break
        }
    }

    // MARK: - Panel lifecycle

    private func showPanel(notch: CGRect) {
        // Show instantly with the last known items so the panel exists (and
        // its frame joins the hover region) before captures finish; the
        // refresh below replaces the content when ready.
        if !lastPanelItems.isEmpty {
            panelController.show(items: lastPanelItems, notch: notch)
        }
        refreshPanel(notch: notch)

        graceTimer?.invalidate()
        refreshTimer?.invalidate()
        graceTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, let notch = self.notchRect else { return }
                self.perform(self.stateMachine.tick(now: Date()), notch: notch)
            }
        }
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, let notch = self.notchRect else { return }
                self.refreshPanel(notch: notch)
            }
        }
    }

    private func refreshPanel(notch: CGRect) {
        refreshTask?.cancel()
        // Tint independently: SCShareableContent cold-starts slowly and must
        // not delay the panel.
        Task { @MainActor [weak self] in
            guard let self, let tint = await self.colorSampler.sample(notch: notch) else { return }
            self.panelController.setTint(tint)
        }
        refreshTask = Task { @MainActor [weak self] in
            guard let self else { return }
            let items = self.scanHiddenItems(notch: notch)
            var panelItems: [PanelItem] = []
            for (index, item) in items.enumerated() {
                let image = await self.capturer.captureIcon(for: item)
                panelItems.append(PanelItem(id: index, info: item, image: image))
            }
            guard !Task.isCancelled, !self.stateMachine.isIdle else { return }
            self.lastPanelItems = panelItems
            // Nothing hidden: no panel at all. Stay in the showing state so
            // the 1s refresh keeps scanning while the mouse lingers, and the
            // panel appears if an item gets hidden.
            if panelItems.isEmpty {
                self.panelController.hide()
                return
            }
            self.panelController.show(items: panelItems, notch: notch)
        }
    }

    private func scanHiddenItems(notch: CGRect) -> [MenuBarItemInfo] {
        guard let screen = builtInScreen else { return [] }
        let ownPID = pid_t(ProcessInfo.processInfo.processIdentifier)
        let otherScreens = NSScreen.screens.filter { $0 != screen }.map(\.frame)
        let menuBarBand = CGRect(x: screen.frame.minX, y: notch.minY,
                                 width: screen.frame.width, height: notch.height)
        let windows = windowList.menuBarItemWindows()

        // AX is the authoritative source when we're trusted: it lists each
        // real status item exactly once at its current position. CGWindowList
        // also contains stale layout copies and popover windows (observed on
        // macOS 26), which show items the user can already see.
        let result: [MenuBarItemInfo]
        if AXIsProcessTrusted() {
            let axHidden = StatusItemScanner.hiddenItems(
                windows: axSource.items(), notch: notch, screenFrame: screen.frame,
                ownPID: ownPID, otherScreens: otherScreens, menuBarBand: menuBarBand)
            // Borrow window IDs from CGWindowList (matched by owner + overlap)
            // so the capturer can grab live pixels.
            result = axHidden.map { item in
                // Same owner isn't enough: apps park popover windows at the
                // status level too. Insist on menu-bar-item geometry.
                let match = windows.first {
                    $0.ownerPID == item.ownerPID
                        && $0.frame.intersects(item.frame)
                        && $0.frame.height <= 40
                        && abs($0.frame.width - item.frame.width) <= 8
                }
                return item.withWindowID(match?.windowID)
            }
        } else {
            result = StatusItemScanner.hiddenItems(
                windows: windows, notch: notch, screenFrame: screen.frame,
                ownPID: ownPID, otherScreens: otherScreens, menuBarBand: menuBarBand)
        }
        for item in result {
            log.debug("hidden item: \(item.ownerName, privacy: .public) pid=\(item.ownerPID) windowID=\(item.windowID.map(String.init) ?? "ax", privacy: .public) frame=\(String(describing: item.frame), privacy: .public)")
        }
        return PanelOrder.apply(saved: PanelOrder.saved(), to: result)
    }

    private func hidePanel(animated: Bool = true) {
        stateMachine.reset()
        graceTimer?.invalidate()
        refreshTimer?.invalidate()
        graceTimer = nil
        refreshTimer = nil
        refreshTask?.cancel()
        panelController.hide(animated: animated)
    }
}
