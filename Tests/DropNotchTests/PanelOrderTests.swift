import XCTest
@testable import DropNotchCore

final class PanelOrderTests: XCTestCase {
    func item(_ name: String, x: CGFloat) -> MenuBarItemInfo {
        MenuBarItemInfo(windowID: nil, ownerPID: 1, ownerName: name,
                        frame: CGRect(x: x, y: 0, width: 40, height: 38), title: nil)
    }

    func testSavedOrderApplied() {
        let items = [item("A", x: 0), item("B", x: 50), item("C", x: 100)]
        let ordered = PanelOrder.apply(saved: ["C", "A", "B"], to: items)
        XCTAssertEqual(ordered.map(\.ownerName), ["C", "A", "B"])
    }

    func testUnknownItemsKeepPositionAfterKnown() {
        let items = [item("New", x: 0), item("A", x: 50), item("B", x: 100)]
        let ordered = PanelOrder.apply(saved: ["B", "A"], to: items)
        XCTAssertEqual(ordered.map(\.ownerName), ["B", "A", "New"])
    }

    func testEmptySavedKeepsGeometricOrder() {
        let items = [item("A", x: 0), item("B", x: 50)]
        let ordered = PanelOrder.apply(saved: [], to: items)
        XCTAssertEqual(ordered.map(\.ownerName), ["A", "B"])
    }

    func testSaveRoundTrip() {
        let defaults = UserDefaults(suiteName: "PanelOrderTests")!
        defaults.removePersistentDomain(forName: "PanelOrderTests")
        PanelOrder.save(["X", "Y"], defaults: defaults)
        XCTAssertEqual(PanelOrder.saved(defaults: defaults), ["X", "Y"])
    }
}
