import Foundation

/// User-chosen icon order for the panel (cmd+drag to rearrange), persisted
/// by owner app name.
public enum PanelOrder {
    static let key = "panelIconOrder"

    public static func save(_ names: [String], defaults: UserDefaults = .standard) {
        defaults.set(names, forKey: key)
    }

    public static func saved(defaults: UserDefaults = .standard) -> [String] {
        defaults.stringArray(forKey: key) ?? []
    }

    /// Stable-sorts items by their saved rank; items not in the saved order
    /// follow, keeping their existing relative order.
    public static func apply(saved: [String], to items: [MenuBarItemInfo]) -> [MenuBarItemInfo] {
        guard !saved.isEmpty else { return items }
        var rank: [String: Int] = [:]
        for (index, name) in saved.enumerated() where rank[name] == nil {
            rank[name] = index
        }
        return items.enumerated()
            .sorted { a, b in
                let ra = rank[a.element.ownerName] ?? Int.max
                let rb = rank[b.element.ownerName] ?? Int.max
                return ra == rb ? a.offset < b.offset : ra < rb
            }
            .map(\.element)
    }
}
