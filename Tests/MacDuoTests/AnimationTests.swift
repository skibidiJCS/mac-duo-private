import XCTest
import AppKit
@testable import LidAngleKit
@testable import MacDuo

final class AnimationTests: XCTestCase {
    func testClosedSensorWraparound() {
        XCTAssertEqual(LidAngleSensor.normalizedAngle(359.33), 0.67, accuracy: 0.001)
        XCTAssertEqual(LidAngleSensor.normalizedAngle(110), 110)
        XCTAssertEqual(LidAngleSensor.normalizedAngle(0), 0)
    }
    @MainActor func testMetalPipelineAndFrameRelease() throws {
        let renderer = try XCTUnwrap(DepthRenderer())
        let context = try XCTUnwrap(CGContext(data: nil, width: 128, height: 80, bitsPerComponent: 8, bytesPerRow: 512, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(red: 0.2, green: 0.4, blue: 0.8, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 128, height: 80))
        let image = try XCTUnwrap(context.makeImage())
        let picture = try XCTUnwrap(renderer.makePicture(image: image, screenSize: CGSize(width: 128, height: 80), pixelScale: 1))
        renderer.adopt(picture)
        XCTAssertTrue(renderer.isReady)
        renderer.release()
        XCTAssertFalse(renderer.isReady)
    }
    func testSpringIsFrameRateIndependent() {
        func simulate(hz: Double) -> Double {
            var spring = CriticallyDampedSpring(value: 90)
            for _ in 0..<Int(hz) { spring.advance(to: 20, dt: 1 / hz) }
            return spring.value
        }
        XCTAssertEqual(simulate(hz: 60), simulate(hz: 120), accuracy: 0.000001)
    }
    func testSmoothingReachesNinetyPercentWithinSeventyMilliseconds() {
        var spring = CriticallyDampedSpring(value: 0)
        spring.advance(to: 1, dt: 0.07)
        XCTAssertGreaterThan(spring.value, 0.9)
        XCTAssertLessThanOrEqual(spring.value, 1)
    }
    func testDroppedFrameAndReversalSettleWithoutInstability() {
        var spring = CriticallyDampedSpring(value: 90)
        spring.advance(to: 10, dt: 0.5)
        XCTAssertTrue((10...90).contains(spring.value))
        for _ in 0..<120 { spring.advance(to: 100, dt: 1 / 120) }
        XCTAssertEqual(spring.value, 100, accuracy: 0.001)
        XCTAssertTrue(spring.velocity.isFinite)
    }
    func testCenteredImageAndFlatFrameMatchDisplay() {
        let geometry = DepthGeometry()
        let flat = geometry.corners(startAngle: 90, currentAngle: 90, screenSize: CGSize(width: 1440, height: 900))
        XCTAssertEqual(flat, [CGPoint(x: 0, y: 0), CGPoint(x: 1440, y: 0), CGPoint(x: 1440, y: 900), CGPoint(x: 0, y: 900)])
        for angle in stride(from: 5.0, through: 90.0, by: 5) {
            let corners = geometry.corners(startAngle: 90, currentAngle: angle, screenSize: CGSize(width: 1440, height: 900))
            XCTAssertEqual(corners[0].x + corners[1].x, 1440, accuracy: 1e-9)
            XCTAssertTrue(corners.allSatisfy { $0.x.isFinite && $0.y.isFinite })
        }
    }
}
