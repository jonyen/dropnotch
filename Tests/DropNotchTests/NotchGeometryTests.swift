import XCTest
@testable import DropNotchCore

final class NotchGeometryTests: XCTestCase {
    // 3456x2234 screen, menu bar/aux height 38, notch from x=1528 to x=1928
    let screen = CGRect(x: 0, y: 0, width: 3456, height: 2234)
    let auxLeft = CGRect(x: 0, y: 2196, width: 1528, height: 38)
    let auxRight = CGRect(x: 1928, y: 2196, width: 1528, height: 38)

    func testNotchRectBetweenAuxAreas() {
        let notch = NotchGeometry.notchRect(screenFrame: screen, auxLeft: auxLeft, auxRight: auxRight)
        XCTAssertEqual(notch, CGRect(x: 1528, y: 2196, width: 400, height: 38))
    }

    func testNotchRectNilWithoutAuxAreas() {
        XCTAssertNil(NotchGeometry.notchRect(screenFrame: screen, auxLeft: nil, auxRight: nil))
        XCTAssertNil(NotchGeometry.notchRect(screenFrame: screen, auxLeft: auxLeft, auxRight: nil))
    }

    func testNotchRectNilWhenAreasTouch() {
        // no gap => no notch
        let right = CGRect(x: 1528, y: 2196, width: 1928, height: 38)
        XCTAssertNil(NotchGeometry.notchRect(screenFrame: screen, auxLeft: auxLeft, auxRight: right))
    }

    func testCocoaRectConversion() {
        // CG rect at top of a 2234-high main display
        let cg = CGRect(x: 100, y: 0, width: 40, height: 38)
        let cocoa = NotchGeometry.cocoaRect(fromCGRect: cg, mainDisplayHeight: 2234)
        XCTAssertEqual(cocoa, CGRect(x: 100, y: 2196, width: 40, height: 38))
    }

    func testCGPointConversion() {
        let p = NotchGeometry.cgPoint(fromCocoaPoint: CGPoint(x: 100, y: 2196), mainDisplayHeight: 2234)
        XCTAssertEqual(p, CGPoint(x: 100, y: 38))
    }
}
