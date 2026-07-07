import CoreGraphics

/// Pure filter: which menu bar items can the user not see?
public enum StatusItemScanner {
    /// Owners that are menu bar chrome, not clickable status items.
    public static let excludedOwners: Set<String> = ["Window Server"]

    public static func hiddenItems(
        windows: [MenuBarItemInfo],
        notch: CGRect?,
        screenFrame: CGRect,
        ownPID: pid_t,
        otherScreens: [CGRect] = [],
        menuBarBand: CGRect? = nil
    ) -> [MenuBarItemInfo] {
        windows
            .filter { $0.ownerPID != ownPID }
            .filter { !excludedOwners.contains($0.ownerName) }
            .filter { item in !otherScreens.contains { $0.intersects(item.frame) } }
            .filter { item in
                // Popovers and panels share the status window level; only
                // windows overlapping the menu bar's y-band are status items.
                guard let band = menuBarBand else { return true }
                return item.frame.intersects(band)
            }
            .filter { isHidden($0.frame, notch: notch, screenFrame: screenFrame) }
            .sorted { $0.frame.minX < $1.frame.minX }
    }

    private static func isHidden(_ frame: CGRect, notch: CGRect?, screenFrame: CGRect) -> Bool {
        // On notched screens, visible status items live strictly right of
        // the notch; macOS parks overflow items under it or further left in
        // app-menu territory, where they never render.
        if let notch, frame.minX < notch.maxX { return true }
        if frame.minX < screenFrame.minX { return true }
        if frame.maxX > screenFrame.maxX { return true }
        return false
    }
}
