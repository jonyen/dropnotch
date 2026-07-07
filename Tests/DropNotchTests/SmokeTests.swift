import XCTest
@testable import DropNotchCore

final class SmokeTests: XCTestCase {
    func testVersionNotEmpty() {
        XCTAssertFalse(DropNotchInfo.version.isEmpty)
    }
}
