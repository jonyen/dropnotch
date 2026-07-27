import XCTest
@testable import DropNotchCore

final class LoginItemTests: XCTestCase {
    func testRawBuildBinaryIsNotRegistrable() {
        let url = URL(fileURLWithPath: "/Users/x/proj/.build/arm64-apple-macosx/release/DropNotch")
        XCTAssertFalse(LoginItem.isAppBundle(url))
    }

    func testAppBundleIsRegistrable() {
        let url = URL(fileURLWithPath: "/Users/x/proj/build/DropNotch.app")
        XCTAssertTrue(LoginItem.isAppBundle(url))
    }

    func testTrailingSlashAppBundleIsRegistrable() {
        let url = URL(fileURLWithPath: "/Applications/DropNotch.app", isDirectory: true)
        XCTAssertTrue(LoginItem.isAppBundle(url))
    }

    func testBinaryNamedLikeAppIsNotRegistrable() {
        let url = URL(fileURLWithPath: "/usr/local/bin/DropNotch")
        XCTAssertFalse(LoginItem.isAppBundle(url))
    }
}
