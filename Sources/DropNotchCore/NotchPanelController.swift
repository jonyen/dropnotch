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
    var onClick: ((PanelItem) -> Void)?
    var onReorder: (([PanelItem]) -> Void)?
    /// Cmd+drag released up in the menu bar band: move the real item there.
    var onDragToMenuBar: ((MenuBarItemInfo, CGPoint) -> Void)?
    /// Bottom of the menu bar in global Cocoa coords (set on show).
    var menuBarMinY: CGFloat = .greatestFiniteMagnitude
}

struct NotchPanelView: View {
    @ObservedObject var model: PanelModel
    @State private var dragIndex: Int?
    @State private var dragOffset: CGFloat = 0

    /// Approximate horizontal footprint of one icon (28pt min + padding + spacing).
    private let slotWidth: CGFloat = 44

    var body: some View {
        HStack(spacing: 8) {
            ForEach(Array(model.items.enumerated()), id: \.element.id) { index, item in
                let shift = displacement(for: index)
                IconButton(item: item) { model.onClick?(item) }
                    .offset(x: shift)
                    .zIndex(dragIndex == index ? 1 : 0)
                    .animation(dragIndex == index ? nil : .easeOut(duration: 0.15), value: shift)
                    .gesture(dragGesture(for: index))
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 6)
        .padding(.bottom, 10)
    }

    /// While dragging, the slot the dragged icon would land in.
    private func proposedTarget(from index: Int) -> Int {
        let delta = Int((dragOffset / slotWidth).rounded())
        return max(0, min(model.items.count - 1, index + delta))
    }

    /// Live reflow: neighbors step aside as the dragged icon passes them,
    /// just like the real menu bar.
    private func displacement(for index: Int) -> CGFloat {
        guard let from = dragIndex else { return 0 }
        if index == from { return dragOffset }
        let target = proposedTarget(from: from)
        if from < target, index > from, index <= target { return -slotWidth }
        if from > target, index < from, index >= target { return slotWidth }
        return 0
    }

    /// Cmd+drag rearranges icons, mirroring the real menu bar's gesture.
    private func dragGesture(for index: Int) -> some Gesture {
        DragGesture(minimumDistance: 4)
            .onChanged { value in
                guard NSEvent.modifierFlags.contains(.command) else { return }
                if dragIndex == nil { dragIndex = index }
                if dragIndex == index { dragOffset = value.translation.width }
            }
            .onEnded { value in
                guard dragIndex == index else {
                    dragIndex = nil
                    dragOffset = 0
                    return
                }
                let target = proposedTarget(from: index)
                dragIndex = nil
                dragOffset = 0
                // Released up in the menu bar: move the real item there
                // instead of reordering the panel.
                let release = NSEvent.mouseLocation
                if release.y >= model.menuBarMinY {
                    model.onDragToMenuBar?(model.items[index].info, release)
                    return
                }
                guard target != index else { return }
                var items = model.items
                items.insert(items.remove(at: index), at: target)
                model.items = items
                model.onReorder?(items)
            }
    }
}

private struct IconButton: View {
    let item: PanelItem
    let action: () -> Void

    var body: some View {
        // No hover highlight: the real menu bar doesn't highlight on
        // mouse-over, and this panel should feel like an extension of it.
        Image(nsImage: item.image)
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(height: 24)
            .frame(minWidth: 28)
            .padding(4)
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
    /// Bottom corner radius, shared by the container and the material so the
    /// two never disagree mid-resize.
    static let cornerRadius: CGFloat = 14
    static let roundedBottomCorners: CACornerMask = [.layerMinXMinYCorner, .layerMaxXMinYCorner]

    /// Clip a layer to the panel's shape: square top, rounded bottom, straight
    /// sides. A layer corner radius tracks bounds changes exactly, unlike a
    /// resizable mask image, whose corners distort when stretched.
    static func applyPanelShape(to layer: CALayer?) {
        layer?.cornerRadius = cornerRadius
        layer?.cornerCurve = .continuous
        layer?.maskedCorners = roundedBottomCorners
        layer?.masksToBounds = true
    }

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
    /// Carries the sampled menu bar color between material and icons.
    private var tintView: NSView?

    public var onItemClick: ((PanelItem) -> Void)? {
        get { model.onClick }
        set { model.onClick = newValue }
    }

    public var onReorder: (([PanelItem]) -> Void)? {
        get { model.onReorder }
        set { model.onReorder = newValue }
    }

    public var onDragToMenuBar: ((MenuBarItemInfo, CGPoint) -> Void)? {
        get { model.onDragToMenuBar }
        set { model.onDragToMenuBar = newValue }
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
        // No shadow: its hard rim reads as a black outline against the
        // menu bar, and the real menu bar draws none.
        panel.hasShadow = false
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        // Below the menu bar window so the slide-down animation emerges from
        // under it, above normal windows. (Set after isFloatingPanel, which
        // would otherwise reset the level.)
        panel.level = .floating
        // Menu bar icons are white glyphs; force dark appearance so the
        // panel reads as an extension of the menu bar.
        panel.appearance = NSAppearance(named: .darkAqua)

        // SwiftUI materials only blur content within the window (nothing, in
        // a clear panel), so real translucency needs an NSVisualEffectView
        // blending behind the window. The effect view and the icon row are
        // siblings so the material's alpha never fades the icons.
        let container = NSView()
        container.wantsLayer = true
        Self.applyPanelShape(to: container.layer)

        let effect = NSVisualEffectView()
        effect.material = PanelStyle.material
        effect.state = .active
        effect.blendingMode = .behindWindow
        effect.alphaValue = PanelStyle.materialAlpha
        effect.translatesAutoresizingMaskIntoConstraints = false
        // The container's masksToBounds clips app-drawn content, but a
        // behind-window backdrop is composited by the window server against
        // the window shape — so a resize exposes an unclipped strip on the
        // growing edge, which reads as a square corner until the mask catches
        // up. Clipping the material's own layer shapes the backdrop directly.
        effect.wantsLayer = true
        Self.applyPanelShape(to: effect.layer)

        // Tint layer between the material and the icons: carries the sampled
        // menu bar color so the panel matches the real menu bar's hue.
        let tint = NSView()
        tint.wantsLayer = true
        tint.translatesAutoresizingMaskIntoConstraints = false
        tintView = tint

        let hosting = FirstMouseHostingView(rootView: NotchPanelView(model: model))
        hosting.translatesAutoresizingMaskIntoConstraints = false

        container.addSubview(effect)
        container.addSubview(tint)
        container.addSubview(hosting)
        NSLayoutConstraint.activate([
            effect.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            effect.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            effect.topAnchor.constraint(equalTo: container.topAnchor),
            effect.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            tint.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            tint.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            tint.topAnchor.constraint(equalTo: container.topAnchor),
            tint.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            hosting.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            hosting.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            hosting.topAnchor.constraint(equalTo: container.topAnchor),
            hosting.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])
        panel.contentView = container
    }

    public func show(items: [PanelItem], notch: CGRect) {
        showGeneration += 1
        model.menuBarMinY = notch.minY
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

    /// Apply the sampled menu bar color; nil clears back to material-only.
    public func setTint(_ color: NSColor?) {
        tintView?.layer?.backgroundColor = color?.withAlphaComponent(0.85).cgColor
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
