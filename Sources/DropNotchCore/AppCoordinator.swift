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
    private let log = Logger(subsystem: DropNotchInfo.logSubsystem, category: "coordinator")

    private var globalMouseMonitor: Any?
    private var localMouseMonitor: Any?
    private var graceTimer: Timer?
    private var refreshTimer: Timer?
    private var refreshTask: Task<Void, Never>?

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
        panelController.onItemClick = { [weak self] item in
            self?.hidePanel()
            self?.clickForwarder.activate(item)
        }
    }

    public func start() {
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
        if stateMachine.isIdle && !windowList.isMenuBarVisible() { return }
        let action = stateMachine.mouseMoved(
            to: NSEvent.mouseLocation,
            notch: notch,
            panel: panelController.panelFrame,
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
        refreshPanel(notch: notch)

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
        refreshTask = Task { @MainActor [weak self] in
            guard let self else { return }
            let items = self.scanHiddenItems(notch: notch)
            var panelItems: [PanelItem] = []
            for (index, item) in items.enumerated() {
                let image = await self.capturer.captureIcon(for: item)
                panelItems.append(PanelItem(id: index, info: item, image: image))
            }
            guard !Task.isCancelled, !self.stateMachine.isIdle else { return }
            self.panelController.show(items: panelItems, notch: notch)
        }
    }

    private func scanHiddenItems(notch: CGRect) -> [MenuBarItemInfo] {
        guard let screen = builtInScreen else { return [] }
        let ownPID = ProcessInfo.processInfo.processIdentifier
        let windows = windowList.menuBarItemWindows()
        var hidden = StatusItemScanner.hiddenItems(
            windows: windows, notch: notch, screenFrame: screen.frame, ownPID: pid_t(ownPID))

        // Union in AX-only items: apps whose status item window wasn't enumerable.
        let knownPIDs = Set(windows.map(\.ownerPID))
        let axHidden = StatusItemScanner.hiddenItems(
            windows: axSource.items().filter { !knownPIDs.contains($0.ownerPID) },
            notch: notch, screenFrame: screen.frame, ownPID: pid_t(ownPID))
        hidden.append(contentsOf: axHidden)
        return hidden.sorted { $0.frame.minX < $1.frame.minX }
    }

    private func hidePanel() {
        graceTimer?.invalidate()
        refreshTimer?.invalidate()
        graceTimer = nil
        refreshTimer = nil
        refreshTask?.cancel()
        panelController.hide()
    }
}
