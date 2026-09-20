import XCTest
import simd
@testable import MacDuo

final class LidMotionTests: XCTestCase {
    func testProjectionMatchesIndependentWorldSpaceRayIntersection() {
        let width = 1440.0, height = 900.0
        for start in [70.0, 90, 110, 125] {
            for current in [60.0, 90, 120] {
                let a = start * .pi / 180, b = current * .pi / 180
                let eye = SIMD3(0.0, height * 2.7 * sin(a) + height / 2 * cos(a), -height * 2.7 * cos(a) + height / 2 * sin(a))
                let normal = SIMD3(0.0, sin(b), -cos(b))
                let alongGlass = SIMD3(0.0, cos(b), sin(b))
                let actual = DepthGeometry().corners(startAngle: start, currentAngle: current,
                    viewingDistanceRatio: 2.7, recession: 1, screenSize: CGSize(width: width, height: height))
                for (i, point) in [(0, SIMD2(0.0, 0.0)), (1, SIMD2(width, 0.0)), (2, SIMD2(width, height)), (3, SIMD2(0.0, height))] {
                    let world = SIMD3(point.x - width / 2, point.y * cos(a), point.y * sin(a))
                    let ray = world - eye
                    let hit = eye + ray * (-simd_dot(eye, normal) / simd_dot(ray, normal))
                    XCTAssertEqual(actual[i].x, hit.x + width / 2, accuracy: 1e-8)
                    XCTAssertEqual(actual[i].y, simd_dot(hit, alongGlass), accuracy: 1e-8)
                }
            }
        }
    }

    func testInteriorPointsStayOnFixedWorldPlaneDuringOpeningClosingAndRecovery() {
        let size = CGSize(width: 1440, height: 900)
        let view = 110.0 * .pi / 180
        let eye = SIMD3(0.0, 900 * (4 * sin(view) + 0.5 * cos(view)),
                        900 * (-4 * cos(view) + 0.5 * sin(view)))
        for reference in [75.0, 95, 110, 125] {
            for current in [65.0, 90, 110, 135] {
                let a = reference * .pi / 180, b = current * .pi / 180
                let normal = SIMD3(0.0, sin(b), -cos(b))
                let along = SIMD3(0.0, cos(b), sin(b))
                let corners = DepthGeometry().corners(startAngle: reference, currentAngle: current,
                    viewingDistanceRatio: 4, recession: 1, screenSize: size, viewingAngle: 110)
                let transform = Homography.matrix(width: 1440, height: 900,
                    to: corners.map { SIMD2(Double($0.x), Double($0.y)) })
                for x in stride(from: 0.0, through: 1440, by: 180) {
                    for y in stride(from: 0.0, through: 900, by: 150) {
                        let world = SIMD3(x - 720, y * cos(a), y * sin(a))
                        let ray = world - eye
                        let hit = eye + ray * (-simd_dot(eye, normal) / simd_dot(ray, normal))
                        let mapped = transform * SIMD3(x, y, 1)
                        XCTAssertEqual(mapped.x / mapped.z, hit.x + 720, accuracy: 1e-7)
                        XCTAssertEqual(mapped.y / mapped.z, simd_dot(hit, along), accuracy: 1e-7)
                    }
                }
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
            let flat = geometry.corners(startAngle: start, currentAngle: start, viewingDistanceRatio: 2.7, recession: 1, screenSize: CGSize(width: 1440, height: 900))
            XCTAssertEqual(flat[2].x, 1440, accuracy: 0.000001)
            XCTAssertEqual(flat[2].y, 900, accuracy: 0.000001)
            for current in stride(from: 5.0, through: 135, by: 5) {
                let corners = geometry.corners(startAngle: start, currentAngle: current, viewingDistanceRatio: 2.7, recession: 1, screenSize: CGSize(width: 1440, height: 900))
                XCTAssertEqual(corners[0], .zero)
                XCTAssertTrue(corners.allSatisfy { $0.x.isFinite && $0.y.isFinite })
            }
        }
        let opening = geometry.corners(startAngle: 90, currentAngle: 110, viewingDistanceRatio: 2.7, recession: 1, screenSize: CGSize(width: 1440, height: 900))
        XCTAssertNotEqual(opening[2], CGPoint(x: 1440, y: 900))
    }
}
