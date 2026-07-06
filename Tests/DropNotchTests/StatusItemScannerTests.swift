import XCTest
@testable import DropNotchCore

final class StatusItemScannerTests: XCTestCase {
    let screen = CGRect(x: 0, y: 0, width: 3456, height: 2234)
    let notch = CGRect(x: 1528, y: 2196, width: 400, height: 38)
    let ownPID: pid_t = 999

    func item(_ name: String, x: CGFloat, width: CGFloat = 40, pid: pid_t = 100) -> MenuBarItemInfo {
        MenuBarItemInfo(windowID: 1, ownerPID: pid, ownerName: name,
                        frame: CGRect(x: x, y: 2196, width: width, height: 38), title: nil)
    }

    func testVisibleItemNotHidden() {
        let items = StatusItemScanner.hiddenItems(
            windows: [item("Dropbox", x: 2000)], notch: notch, screenFrame: screen, ownPID: ownPID)
        XCTAssertTrue(items.isEmpty)
    }

    func testItemUnderNotchIsHidden() {
        let hidden = item("Docker", x: 1600)
        let items = StatusItemScanner.hiddenItems(
            windows: [hidden], notch: notch, screenFrame: screen, ownPID: ownPID)
        XCTAssertEqual(items, [hidden])
    }

    func testItemPartiallyUnderNotchIsHidden() {
        let hidden = item("Docker", x: 1500) // 1500-1540 overlaps notch start 1528
        let items = StatusItemScanner.hiddenItems(
            windows: [hidden], notch: notch, screenFrame: screen, ownPID: ownPID)
        XCTAssertEqual(items, [hidden])
    }

    func testOffscreenLeftIsHidden() {
        let hidden = item("Overflow", x: -40)
        let items = StatusItemScanner.hiddenItems(
            windows: [hidden], notch: notch, screenFrame: screen, ownPID: ownPID)
        XCTAssertEqual(items, [hidden])
    }

    func testOffscreenRightIsHidden() {
        let hidden = item("Overflow", x: 3440) // extends past 3456
        let items = StatusItemScanner.hiddenItems(
            windows: [hidden], notch: notch, screenFrame: screen, ownPID: ownPID)
        XCTAssertEqual(items, [hidden])
    }

    func testOwnItemsExcluded() {
        let mine = item("DropNotch", x: 1600, pid: 999)
        let items = StatusItemScanner.hiddenItems(
            windows: [mine], notch: notch, screenFrame: screen, ownPID: ownPID)
        XCTAssertTrue(items.isEmpty)
    }

    func testWindowServerExcluded() {
        let ws = item("Window Server", x: 1600)
        let items = StatusItemScanner.hiddenItems(
            windows: [ws], notch: notch, screenFrame: screen, ownPID: ownPID)
        XCTAssertTrue(items.isEmpty)
    }

    func testNilNotchStillCatchesOffscreen() {
        let hidden = item("Overflow", x: -40)
        let visible = item("Dropbox", x: 2000)
        let items = StatusItemScanner.hiddenItems(
            windows: [visible, hidden], notch: nil, screenFrame: screen, ownPID: ownPID)
        XCTAssertEqual(items, [hidden])
    }

    func testSortedLeftToRight() {
        let a = item("B", x: 1700)
        let b = item("A", x: 1550)
        let items = StatusItemScanner.hiddenItems(
            windows: [a, b], notch: notch, screenFrame: screen, ownPID: ownPID)
        XCTAssertEqual(items.map(\.ownerName), ["A", "B"])
    }

    func testWindowOutsideMenuBarBandExcluded() {
        // Popover/panel windows share the status window level but live
        // mid-screen; a band filter must drop them.
        let band = CGRect(x: 0, y: 2196, width: 3456, height: 38)
        let popover = MenuBarItemInfo(
            windowID: 7, ownerPID: 100, ownerName: "WeatherMenu",
            frame: CGRect(x: 3400, y: 900, width: 332, height: 1200), title: nil)
        let realHidden = item("Docker", x: 1600)
        let items = StatusItemScanner.hiddenItems(
            windows: [popover, realHidden], notch: notch, screenFrame: screen, ownPID: ownPID,
            menuBarBand: band)
        XCTAssertEqual(items, [realHidden])
    }

    func testNilBandKeepsOldBehavior() {
        let popover = MenuBarItemInfo(
            windowID: 7, ownerPID: 100, ownerName: "WeatherMenu",
            frame: CGRect(x: 3400, y: 900, width: 332, height: 1200), title: nil)
        let items = StatusItemScanner.hiddenItems(
            windows: [popover], notch: notch, screenFrame: screen, ownPID: ownPID)
        XCTAssertEqual(items, [popover]) // maxX 3732 > 3456: old rule flags it
    }

    func testExternalDisplayItemExcludedWhenOtherScreensProvided() {
        let external = CGRect(x: 3456, y: 0, width: 2560, height: 1440)
        let externalItem = MenuBarItemInfo(
            windowID: 1, ownerPID: 100, ownerName: "ExternalApp",
            frame: CGRect(x: 3500, y: 1402, width: 40, height: 38), title: nil)
        let items = StatusItemScanner.hiddenItems(
            windows: [externalItem], notch: notch, screenFrame: screen, ownPID: ownPID,
            otherScreens: [external])
        XCTAssertTrue(items.isEmpty)
    }

    func testExternalDisplayItemIncludedWithoutOtherScreens() {
        let externalItem = MenuBarItemInfo(
            windowID: 1, ownerPID: 100, ownerName: "ExternalApp",
            frame: CGRect(x: 3500, y: 1402, width: 40, height: 38), title: nil)
        let items = StatusItemScanner.hiddenItems(
            windows: [externalItem], notch: notch, screenFrame: screen, ownPID: ownPID,
            otherScreens: [])
        XCTAssertEqual(items, [externalItem])
    }
}
