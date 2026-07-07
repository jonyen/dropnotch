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

/// First click must register without activating the app, or taps in the
/// panel are swallowed as focus clicks.
private final class FirstMouseHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

/// Panel appearance knobs, overridable via environment for quick visual
/// iteration: DROPNOTCH_MATERIAL=menu|popover|hud|sidebar|tooltip|selection
/// and DROPNOTCH_ALPHA=0.0-1.0.
enum PanelStyle {
    static var material: NSVisualEffectView.Material {
        switch ProcessInfo.processInfo.environment["DROPNOTCH_MATERIAL"] {
        case "menu": return .menu
        case "hud": return .hudWindow
        case "sidebar": return .sidebar
        case "tooltip": return .toolTip
        case "selection": return .selection
        case "underwindow": return .underWindowBackground
        default: return .popover
        }
    }

    static var materialAlpha: CGFloat {
        ProcessInfo.processInfo.environment["DROPNOTCH_ALPHA"]
            .flatMap { Double($0) }.map { CGFloat($0) } ?? 0.7
    }
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

        // SwiftUI materials only blur content within the window (nothing, in
        // a clear panel), so real translucency needs an NSVisualEffectView
        // blending behind the window. The effect view and the icon row are
        // siblings so the material's alpha never fades the icons.
        let container = NSView()
        container.wantsLayer = true
        container.layer?.cornerRadius = 14
        container.layer?.cornerCurve = .continuous
        container.layer?.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner]
        container.layer?.masksToBounds = true

        let effect = NSVisualEffectView()
        effect.material = PanelStyle.material
        effect.state = .active
        effect.blendingMode = .behindWindow
        effect.alphaValue = PanelStyle.materialAlpha
        effect.translatesAutoresizingMaskIntoConstraints = false

        let hosting = FirstMouseHostingView(rootView: NotchPanelView(model: model))
        hosting.translatesAutoresizingMaskIntoConstraints = false

        container.addSubview(effect)
        container.addSubview(hosting)
        NSLayoutConstraint.activate([
            effect.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            effect.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            effect.topAnchor.constraint(equalTo: container.topAnchor),
            effect.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            hosting.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            hosting.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            hosting.topAnchor.constraint(equalTo: container.topAnchor),
            hosting.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])
        panel.contentView = container
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

    public func hide(animated: Bool = true) {
        guard panel.isVisible, !isHiding else { return }
        targetFrame = .zero
        guard animated else {
            panel.orderOut(nil)
            return
        }
        isHiding = true
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
