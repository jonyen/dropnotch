import AppKit
import SwiftUI

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

    public var onItemClick: ((MenuBarItemInfo) -> Void)? {
        get { model.onClick }
        set { model.onClick = newValue }
    }

    public var panelFrame: CGRect? {
        panel.isVisible ? panel.frame : nil
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

        // Menu-style translucent material, rounded bottom corners — reads as
        // an extension of the menu bar / an open menu.
        let effect = NSVisualEffectView()
        effect.material = .menu
        effect.state = .active
        effect.blendingMode = .behindWindow
        effect.wantsLayer = true
        effect.layer?.cornerRadius = 14
        effect.layer?.cornerCurve = .continuous
        effect.layer?.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner]
        effect.layer?.masksToBounds = true

        let hosting = NSHostingView(rootView: NotchPanelView(model: model))
        hosting.translatesAutoresizingMaskIntoConstraints = false
        effect.addSubview(hosting)
        NSLayoutConstraint.activate([
            hosting.leadingAnchor.constraint(equalTo: effect.leadingAnchor),
            hosting.trailingAnchor.constraint(equalTo: effect.trailingAnchor),
            hosting.topAnchor.constraint(equalTo: effect.topAnchor),
            hosting.bottomAnchor.constraint(equalTo: effect.bottomAnchor),
        ])
        panel.contentView = effect
    }

    public func show(items: [PanelItem], notch: CGRect) {
        showGeneration += 1
        let wasVisible = panel.isVisible
        model.items = items
        panel.contentView?.layoutSubtreeIfNeeded()
        let size = panel.contentView?.fittingSize ?? .zero
        let width = max(size.width, notch.width)
        let finalFrame = CGRect(x: notch.midX - width / 2, y: notch.minY - size.height,
                                width: width, height: size.height)

        if wasVisible {
            // 1s refresh while open: update in place, no animation.
            panel.setFrame(finalFrame, display: true)
            return
        }

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
        guard panel.isVisible else { return }
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
            }
        })
    }
}
