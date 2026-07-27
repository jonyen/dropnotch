import XCTest
@testable import IconArt

final class IconArtTests: XCTestCase {
    let canvas = CGRect(x: 0, y: 0, width: 1024, height: 1024)

    // MARK: - Geometry

    func testNotchIsHorizontallyCentred() {
        let notch = IconGeometry.notchRect(in: canvas)
        XCTAssertEqual(notch.midX, canvas.midX, accuracy: 0.001)
    }

    func testNotchHangsFromTopOfSquircle() {
        let squircle = IconGeometry.squircleRect(in: canvas)
        let notch = IconGeometry.notchRect(in: canvas)
        XCTAssertEqual(notch.maxY, squircle.maxY, accuracy: 0.001)
    }

    func testGeometryScalesProportionally() {
        let half = CGRect(x: 0, y: 0, width: 512, height: 512)
        let big = IconGeometry.notchRect(in: canvas)
        let small = IconGeometry.notchRect(in: half)
        XCTAssertEqual(small.width, big.width / 2, accuracy: 0.001)
        XCTAssertEqual(small.height, big.height / 2, accuracy: 0.001)
    }

    func testDotCentresAreSymmetricAboutMidline() {
        let centres = IconGeometry.dotCentres(in: canvas, count: 3)
        XCTAssertEqual(centres.count, 3)
        let offsets = centres.map { $0.x - canvas.midX }
        XCTAssertEqual(offsets.first!, -offsets.last!, accuracy: 0.001)
        XCTAssertEqual(offsets[1], 0, accuracy: 0.001)
    }

    func testSingleDotSitsOnMidline() {
        let centres = IconGeometry.dotCentres(in: canvas, count: 1)
        XCTAssertEqual(centres.count, 1)
        XCTAssertEqual(centres[0].x, canvas.midX, accuracy: 0.001)
    }

    func testDotsSitBelowTheNotch() {
        let notch = IconGeometry.notchRect(in: canvas)
        let radius = IconGeometry.dotRadius(in: canvas)
        for centre in IconGeometry.dotCentres(in: canvas, count: 3) {
            XCTAssertLessThan(centre.y + radius, notch.minY)
        }
    }

    // MARK: - Small-size legibility

    func testSmallSizesCollapseToOneDot() {
        XCTAssertEqual(IconGeometry.dotCount(forPixelSize: 16), 1)
        XCTAssertEqual(IconGeometry.dotCount(forPixelSize: 32), 1)
    }

    func testLargeSizesUseThreeDots() {
        XCTAssertEqual(IconGeometry.dotCount(forPixelSize: 64), 3)
        XCTAssertEqual(IconGeometry.dotCount(forPixelSize: 1024), 3)
    }

    // MARK: - Rendering

    func testRenderProducesRequestedPixelSize() throws {
        let image = try XCTUnwrap(IconRenderer.render(pixelSize: 128))
        XCTAssertEqual(image.width, 128)
        XCTAssertEqual(image.height, 128)
    }

    func testRenderedIconIsNotBlank() throws {
        let image = try XCTUnwrap(IconRenderer.render(pixelSize: 128))
        XCTAssertTrue(hasVisibleContent(image), "icon rendered fully transparent")
    }

    func testRenderedIconHasBrightDotsAgainstDarkBody() throws {
        // The dots are the only near-white pixels; if the drawing order or
        // colours regress they vanish into the graphite body.
        let image = try XCTUnwrap(IconRenderer.render(pixelSize: 256))
        XCTAssertTrue(brightPixelCount(image) > 20, "no bright dots found")
    }

    // MARK: - Helpers

    private func pixels(_ image: CGImage) -> [UInt8] {
        var buf = [UInt8](repeating: 0, count: image.width * image.height * 4)
        let ctx = CGContext(data: &buf, width: image.width, height: image.height,
                            bitsPerComponent: 8, bytesPerRow: image.width * 4,
                            space: CGColorSpaceCreateDeviceRGB(),
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        ctx?.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return buf
    }

    private func hasVisibleContent(_ image: CGImage) -> Bool {
        pixels(image).enumerated().contains { $0.offset % 4 == 3 && $0.element > 0 }
    }

    private func brightPixelCount(_ image: CGImage) -> Int {
        let buf = pixels(image)
        var count = 0
        for i in stride(from: 0, to: buf.count, by: 4)
        where buf[i] > 200 && buf[i + 1] > 200 && buf[i + 2] > 200 && buf[i + 3] > 200 {
            count += 1
        }
        return count
    }
}
