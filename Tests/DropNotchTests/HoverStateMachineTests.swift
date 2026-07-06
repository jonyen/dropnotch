import XCTest
@testable import DropNotchCore

final class HoverStateMachineTests: XCTestCase {
    let notch = CGRect(x: 1528, y: 2196, width: 400, height: 38)
    let panel = CGRect(x: 1500, y: 2100, width: 456, height: 96)
    let t0 = Date(timeIntervalSince1970: 1_000_000)

    func makeSM() -> HoverStateMachine { HoverStateMachine(graceInterval: 0.3) }

    func testEnterNotchShows() {
        let sm = makeSM()
        let action = sm.mouseMoved(to: CGPoint(x: 1600, y: 2210), notch: notch, panel: nil, now: t0)
        XCTAssertEqual(action, .show)
        XCTAssertFalse(sm.isIdle)
    }

    func testOutsideWhileIdleDoesNothing() {
        let sm = makeSM()
        XCTAssertEqual(sm.mouseMoved(to: CGPoint(x: 10, y: 10), notch: notch, panel: nil, now: t0), .none)
        XCTAssertTrue(sm.isIdle)
    }

    func testMovingIntoPanelKeepsShowing() {
        let sm = makeSM()
        _ = sm.mouseMoved(to: CGPoint(x: 1600, y: 2210), notch: notch, panel: nil, now: t0)
        let action = sm.mouseMoved(to: CGPoint(x: 1600, y: 2150), notch: notch, panel: panel, now: t0)
        XCTAssertEqual(action, .none)
        XCTAssertFalse(sm.isIdle)
    }

    func testLeaveThenGraceExpiryHides() {
        let sm = makeSM()
        _ = sm.mouseMoved(to: CGPoint(x: 1600, y: 2210), notch: notch, panel: panel, now: t0)
        // leave both rects
        XCTAssertEqual(sm.mouseMoved(to: CGPoint(x: 10, y: 10), notch: notch, panel: panel, now: t0), .none)
        // tick before grace expiry: nothing
        XCTAssertEqual(sm.tick(now: t0.addingTimeInterval(0.1)), .none)
        // tick after expiry: hide
        XCTAssertEqual(sm.tick(now: t0.addingTimeInterval(0.35)), .hide)
        XCTAssertTrue(sm.isIdle)
    }

    func testReenterDuringGraceCancelsHide() {
        let sm = makeSM()
        _ = sm.mouseMoved(to: CGPoint(x: 1600, y: 2210), notch: notch, panel: panel, now: t0)
        _ = sm.mouseMoved(to: CGPoint(x: 10, y: 10), notch: notch, panel: panel, now: t0)
        // back inside panel during grace
        XCTAssertEqual(sm.mouseMoved(to: CGPoint(x: 1600, y: 2150), notch: notch, panel: panel, now: t0.addingTimeInterval(0.2)), .none)
        // grace should be cancelled: much later tick does nothing
        XCTAssertEqual(sm.tick(now: t0.addingTimeInterval(5)), .none)
        XCTAssertFalse(sm.isIdle)
    }

    func testMouseMoveAfterGraceExpiryHides() {
        // hide can also be delivered by a mouse move, not only tick
        let sm = makeSM()
        _ = sm.mouseMoved(to: CGPoint(x: 1600, y: 2210), notch: notch, panel: panel, now: t0)
        _ = sm.mouseMoved(to: CGPoint(x: 10, y: 10), notch: notch, panel: panel, now: t0)
        let action = sm.mouseMoved(to: CGPoint(x: 12, y: 10), notch: notch, panel: panel, now: t0.addingTimeInterval(0.4))
        XCTAssertEqual(action, .hide)
        XCTAssertTrue(sm.isIdle)
    }

    func testResetReturnsToIdleAndAllowsReshow() {
        let sm = makeSM()
        _ = sm.mouseMoved(to: CGPoint(x: 1600, y: 2210), notch: notch, panel: nil, now: t0)
        XCTAssertFalse(sm.isIdle)

        sm.reset()
        XCTAssertTrue(sm.isIdle)

        let action = sm.mouseMoved(to: CGPoint(x: 1600, y: 2210), notch: notch, panel: nil, now: t0)
        XCTAssertEqual(action, .show)
    }
}
