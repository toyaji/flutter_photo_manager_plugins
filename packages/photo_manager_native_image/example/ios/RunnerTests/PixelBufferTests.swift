import UIKit
import XCTest
@testable import photo_manager_native_image

final class PixelBufferTests: XCTestCase {
    private func image(width: Int, height: Int) -> CGImage {
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        return UIGraphicsImageRenderer(size: CGSize(width: width, height: height), format: format).image { ctx in
            UIColor(red: 0.8, green: 0.4, blue: 0.2, alpha: 1).setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        }.cgImage!
    }

    func testScaledSizeMatchesShorterSideWithoutUpscaling() {
        XCTAssertEqual(PixelBufferFactory.scaledSize(for: CGSize(width: 640, height: 480), target: CGSize(width: 320, height: 320)),
                       CGSize(width: 427, height: 320))
        XCTAssertEqual(PixelBufferFactory.scaledSize(for: CGSize(width: 480, height: 640), target: CGSize(width: 320, height: 320)),
                       CGSize(width: 320, height: 427))
        XCTAssertNil(PixelBufferFactory.scaledSize(for: CGSize(width: 300, height: 200), target: CGSize(width: 320, height: 320)))
        XCTAssertNil(PixelBufferFactory.scaledSize(for: CGSize(width: 320, height: 320), target: CGSize(width: 320, height: 320)))
    }

    func testLargerImageIsScaledDownToRGBA() throws {
        let buffer = try PixelBufferFactory.make(from: image(width: 64, height: 32), target: CGSize(width: 16, height: 16))
        defer { buffer.free() }
        XCTAssertEqual(buffer.width, 32)
        XCTAssertEqual(buffer.height, 16)
        XCTAssertEqual(buffer.rowBytes, 32 * 4)
        let px = buffer.data.assumingMemoryBound(to: UInt8.self)
        XCTAssertEqual(px[3], 255)
        XCTAssertGreaterThan(px[0], px[1])
        XCTAssertGreaterThan(px[1], px[2])
        XCTAssertEqual(buffer.reply["width"], 32)
        XCTAssertEqual(buffer.reply["rowBytes"], 128)
        XCTAssertEqual(buffer.reply["pointer"], Int64(Int(bitPattern: buffer.data)))
    }

    func testSmallerImageIsConvertedWithoutScaling() throws {
        let buffer = try PixelBufferFactory.make(from: image(width: 10, height: 12), target: CGSize(width: 64, height: 64))
        defer { buffer.free() }
        XCTAssertEqual(buffer.width, 10)
        XCTAssertEqual(buffer.height, 12)
        XCTAssertGreaterThanOrEqual(buffer.rowBytes, 40)
        let px = buffer.data.assumingMemoryBound(to: UInt8.self)
        XCTAssertEqual(px[3], 255)
        XCTAssertGreaterThan(px[0], px[2])
    }
}
