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
        .background(
            UnevenRoundedRectangle(
                cornerRadii: .init(bottomLeading: 14, bottomTrailing: 14),
                style: .continuous)
            .fill(Color.black)
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
                    .fill(hovering ? Color.white.opacity(0.2) : Color.clear)
            )
            .onHover { hovering = $0 }
            .onTapGesture(perform: action)
            .help(item.info.title ?? item.info.ownerName)
    }
}

@MainActor
public final class NotchPanelController {
    private let panel: NSPanel
    private let model = PanelModel()

    public var onItemClick: ((MenuBarItemInfo) -> Void)? {
        get { model.onClick }
        set { model.onClick = newValue }
    }

    public var panelFrame: CGRect? {
        panel.isVisible ? panel.frame : nil
    }

    public init() {
        panel = NSPanel(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false)
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 1)
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.contentView = NSHostingView(rootView: NotchPanelView(model: model))
    }

    public func show(items: [PanelItem], notch: CGRect) {
        model.items = items
        panel.contentView?.layoutSubtreeIfNeeded()
        let size = panel.contentView?.fittingSize ?? .zero
        let width = max(size.width, notch.width)
        let origin = CGPoint(x: notch.midX - width / 2, y: notch.minY - size.height)
        panel.setFrame(CGRect(origin: origin, size: CGSize(width: width, height: size.height)),
                       display: true)
        panel.orderFrontRegardless()
    }

    public func hide() {
        panel.orderOut(nil)
    }
}
