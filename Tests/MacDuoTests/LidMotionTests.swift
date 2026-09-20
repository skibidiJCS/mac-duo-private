import XCTest
import simd
@testable import MacDuo

final class LidMotionTests: XCTestCase {
    func testEveryAnglePreservesAspectRatioWithoutMagnificationOrCropping() {
        let geometry = DepthGeometry()
        for start in stride(from: 0.0, through: 180, by: 3) {
            for current in stride(from: 0.0, through: 180, by: 3) {
                let p = geometry.corners(startAngle: start, currentAngle: current,
                                         screenSize: CGSize(width: 1440, height: 900))
                let sx = (p[1].x - p[0].x) / 1440
                let sy = (p[3].y - p[0].y) / 900
                XCTAssertEqual(sx, sy, accuracy: 1e-12)
                XCTAssertGreaterThanOrEqual(sx, 0.94 - 1e-12)
                XCTAssertLessThanOrEqual(sx, 1)
                XCTAssertEqual(p[0].y, p[1].y)
                XCTAssertEqual(p[2].y, p[3].y)
                XCTAssertEqual(p[0].x, p[3].x)
                XCTAssertEqual(p[1].x, p[2].x)
                XCTAssertTrue(p.allSatisfy { $0.x >= -1e-9 && $0.x <= 1440 + 1e-9 && $0.y >= -1e-9 && $0.y <= 900 + 1e-9 })
            }
        }
    }

    func testKeepsActualStartingAngleWhileMoving() {
        for initial in [55.0, 80, 105, 125] {
            var motion = LidMotion()
            motion.reset(angle: initial, at: 0)
            XCTAssertTrue(motion.sample(initial - 3, at: 0.1))
            for index in 1...10 {
                motion.sample(initial - Double(index * 3), at: Double(index) * 0.1)
                XCTAssertEqual(motion.reference(at: Double(index) * 0.1), initial)
                XCTAssertEqual(motion.phase, .tracking)
            }
        }
    }
    func testPauseThenAdaptsToNewAngleAndRetriggersBelowNinety() {
        var motion = LidMotion()
        motion.reset(angle: 80, at: 0)
        XCTAssertTrue(motion.sample(60, at: 0.1))
        motion.sample(60, at: 0.9)
        XCTAssertEqual(motion.phase, .tracking)
        motion.sample(60, at: 1)
        XCTAssertEqual(motion.phase, .settling)
        motion.sample(60, at: 1.4)
        XCTAssertEqual(motion.phase, .idle)
        XCTAssertEqual(motion.anchor, 60)
        XCTAssertTrue(motion.sample(45, at: 1.5))
        XCTAssertEqual(motion.anchor, 60)
    }
    func testRapidReversalsKeepTheSamePlane() {
        var motion = LidMotion()
        motion.reset(angle: 110, at: 0)
        XCTAssertTrue(motion.sample(100, at: 0.05))
        for index in 1...1000 {
            let value = index.isMultiple(of: 2) ? 70.0 : 120.0
            XCTAssertFalse(motion.sample(value, at: Double(index) * 0.05 + 0.05))
            XCTAssertEqual(motion.phase, .tracking)
            XCTAssertEqual(motion.anchor, 110)
        }
    }
    func testRepeatedGesturesAlwaysRearm() {
        var motion = LidMotion()
        motion.reset(angle: 85, at: 0)
        for index in 0..<1000 {
            let time = Double(index) * 2
            let destination = index.isMultiple(of: 2) ? 55.0 : 85.0
            XCTAssertTrue(motion.sample(destination, at: time + 0.1))
            motion.sample(destination, at: time + 1)
            motion.sample(destination, at: time + 1.4)
            XCTAssertEqual(motion.phase, .idle)
            XCTAssertEqual(motion.anchor, destination)
        }
    }
    func testMovementDuringSettleContinuesWithoutSnap() {
        var motion = LidMotion()
        motion.reset(angle: 110, at: 0)
        motion.sample(70, at: 0.1)
        motion.sample(70, at: 1)
        let visible = motion.reference(at: 1.15)
        XCTAssertFalse(motion.sample(65, at: 1.15))
        XCTAssertEqual(motion.anchor, visible, accuracy: 0.00001)
        XCTAssertEqual(motion.phase, .tracking)
    }
    func testNoiseDoesNotTriggerOrPreventSettling() {
        var motion = LidMotion()
        motion.reset(angle: 100, at: 0)
        for index in 1...20 {
            XCTAssertFalse(motion.sample(index.isMultiple(of: 2) ? 100 : 101, at: Double(index) * 0.05))
        }
        XCTAssertEqual(motion.phase, .idle)
        motion.sample(75, at: 1.1)
        for index in 1...30 {
            motion.sample(index.isMultiple(of: 2) ? 75 : 76, at: 1.1 + Double(index) * 0.05)
        }
        XCTAssertEqual(motion.phase, .idle)
    }
    func testSlowCumulativeMovementAndOpening() {
        var motion = LidMotion()
        motion.reset(angle: 70, at: 0)
        XCTAssertFalse(motion.sample(70.5, at: 0.125))
        XCTAssertFalse(motion.sample(71, at: 0.25))
        XCTAssertTrue(motion.sample(71.5, at: 0.375))
        XCTAssertEqual(motion.anchor, 70)
    }
    func testResetClearsGestureForSleepDisableAndDisplayChanges() {
        var motion = LidMotion()
        motion.reset(angle: 110, at: 0)
        motion.sample(50, at: 0.1)
        motion.reset(angle: 20, at: 2)
        XCTAssertEqual(motion.phase, .idle)
        XCTAssertTrue(motion.sample(25, at: 2.1))
        XCTAssertEqual(motion.anchor, 20)
    }
    func testGeometryUsesBothDirectionsAndIsIdentityAtAnyRestAngle() {
        let geometry = DepthGeometry()
        for start in stride(from: 10.0, through: 130, by: 10) {
            let flat = geometry.corners(startAngle: start, currentAngle: start, screenSize: CGSize(width: 1440, height: 900))
            XCTAssertEqual(flat[2].x, 1440, accuracy: 0.000001)
            XCTAssertEqual(flat[2].y, 900, accuracy: 0.000001)
            for current in stride(from: 5.0, through: 135, by: 5) {
                let corners = geometry.corners(startAngle: start, currentAngle: current, screenSize: CGSize(width: 1440, height: 900))
                XCTAssertTrue(corners.allSatisfy { $0.x.isFinite && $0.y.isFinite })
            }
        }
        let opening = geometry.corners(startAngle: 90, currentAngle: 110, screenSize: CGSize(width: 1440, height: 900))
        XCTAssertNotEqual(opening[2], CGPoint(x: 1440, y: 900))
    }
}
