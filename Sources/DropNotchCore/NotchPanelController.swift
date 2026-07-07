import AppKit
import SwiftUI
import os.log

public struct PanelItem: Identifiable {
    public let id: Int
    public let info: MenuBarItemInfo
    public let image: NSImage

    public init(id: Int, info: MenuBarItemInfo, image: NSImage) {
        self.id = id
        self.info = info
        self.image = image
    }
}

@MainActor
final class PanelModel: ObservableObject {
    @Published var items: [PanelItem] = []
    var onClick: ((MenuBarItemInfo) -> Void)?
}

struct NotchPanelView: View {
    @ObservedObject var model: PanelModel

    var body: some View {
        HStack(spacing: 8) {
            if model.items.isEmpty {
                Text("Nothing hidden")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            } else {
                ForEach(model.items) { item in
                    IconButton(item: item) { model.onClick?(item.info) }
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 6)
        .padding(.bottom, 10)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            .ultraThinMaterial,
            in: UnevenRoundedRectangle(
                cornerRadii: .init(bottomLeading: 14, bottomTrailing: 14),
                style: .continuous)
        )
    }
}

private struct IconButton: View {
    let item: PanelItem
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Image(nsImage: item.image)
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(height: 24)
            .frame(minWidth: 28)
            .padding(4)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(hovering ? Color.primary.opacity(0.15) : Color.clear)
            )
            .onHover { hovering = $0 }
            .onTapGesture(perform: action)
            .help(item.info.tooltip ?? item.info.title ?? item.info.ownerName)
    }
}

private final class NonKeyPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

@MainActor
public final class NotchPanelController {
    private let panel: NSPanel
    private let model = PanelModel()
    /// Bumped on every show; a hide animation's completion only orders the
    /// panel out if no show happened while it was animating.
    private var showGeneration = 0
    /// Width locked in while the panel is open: refreshes may grow it but
    /// never shrink it, so the panel doesn't snap around horizontally.
    private var openWidth: CGFloat = 0
    /// Where the panel is headed (may still be animating there).
    private var targetFrame: CGRect = .zero
    /// True while the slide-up hide animation is in flight.
    private var isHiding = false

    public var onItemClick: ((MenuBarItemInfo) -> Void)? {
        get { model.onClick }
        set { model.onClick = newValue }
    }

    public var panelFrame: CGRect? {
        // Mid-hide the panel is visually gone; don't count it as hover area.
        (panel.isVisible && !isHiding) ? panel.frame : nil
    }

    public init() {
        panel = NonKeyPanel(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false)
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        // Below the menu bar window so the slide-down animation emerges from
        // under it, above normal windows. (Set after isFloatingPanel, which
        // would otherwise reset the level.)
        panel.level = .floating

        // Translucent material + rounded bottom corners come from the SwiftUI
        // view's .ultraThinMaterial background.
        panel.contentView = NSHostingView(rootView: NotchPanelView(model: model))
    }

    public func show(items: [PanelItem], notch: CGRect) {
        showGeneration += 1
        // A panel mid-hide counts as not visible: it needs the full
        // place-and-slide path, not an in-place content refresh.
        let wasVisible = panel.isVisible && !isHiding
        isHiding = false
        model.items = items
        panel.contentView?.layoutSubtreeIfNeeded()
        let size = panel.contentView?.fittingSize ?? .zero
        let width = max(size.width, notch.width, wasVisible ? openWidth : 0)
        openWidth = width
        let finalFrame = CGRect(x: notch.midX - width / 2, y: notch.minY - size.height,
                                width: width, height: size.height)
        Logger(subsystem: DropNotchInfo.logSubsystem, category: "panel")
            .debug("show items=\(items.count) fitting=\(size.width, format: .fixed(precision: 1))x\(size.height, format: .fixed(precision: 1)) frame=\(String(describing: finalFrame), privacy: .public) wasVisible=\(wasVisible, privacy: .public)")

        if wasVisible {
            // 1s refresh while open: update in place, no animation. Compare
            // against the animation target, not the live frame, so an
            // in-flight slide isn't stomped mid-animation.
            if targetFrame != finalFrame {
                panel.setFrame(finalFrame, display: true)
            }
            targetFrame = finalFrame
            return
        }
        targetFrame = finalFrame

        // Slide down from behind the menu bar: start with the panel tucked
        // fully above its final position, then animate to rest.
        let startFrame = CGRect(x: finalFrame.minX, y: notch.minY,
                                width: width, height: size.height)
        panel.setFrame(startFrame, display: false)
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.22
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().setFrame(finalFrame, display: true)
        }
    }

    public func hide() {
        guard panel.isVisible, !isHiding else { return }
        isHiding = true
        targetFrame = .zero
        let generation = showGeneration
        let frame = panel.frame
        let upFrame = CGRect(x: frame.minX, y: frame.maxY, width: frame.width, height: frame.height)
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.18
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            panel.animator().setFrame(upFrame, display: true)
        }, completionHandler: { [weak self] in
            Task { @MainActor in
                guard let self, self.showGeneration == generation else { return }
                self.panel.orderOut(nil)
                self.isHiding = false
            }
        })
    }
}
