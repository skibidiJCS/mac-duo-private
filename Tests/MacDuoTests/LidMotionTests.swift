import XCTest
import simd
@testable import MacDuo

final class LidMotionTests: XCTestCase {
    func testInverseProjectionMatchesIndependentWorldSpaceRays() {
        let size = CGSize(width: 1440, height: 900)
        let view = 110.0 * .pi / 180
        let eye = SIMD3(0.0, 900 * (3.5 * sin(view) + 0.5 * cos(view)),
                        900 * (-3.5 * cos(view) + 0.5 * sin(view)))
        for reference in [60.0, 90, 110, 140] {
            for current in stride(from: 5.0, through: 175, by: 5) {
                let a = reference * .pi / 180, b = current * .pi / 180
                let normal = SIMD3(0.0, sin(a), -cos(a))
                let up = SIMD3(0.0, cos(a), sin(a))
                let matrix = DepthGeometry().screenToPicture(startAngle: reference,
                    currentAngle: current, screenSize: size, viewingAngle: 110)
                for x in [0.0, 360, 720, 1440] {
                    for y in [0.0, 225, 450, 900] {
                        let glass = SIMD3(x - 720, y * cos(b), y * sin(b))
                        let ray = glass - eye
                        let hit = eye + ray * (-simd_dot(eye, normal) / simd_dot(ray, normal))
                        let mapped = matrix * SIMD3(x, y, 1)
                        XCTAssertEqual(mapped.x / mapped.z, hit.x + 720, accuracy: 1e-7)
                        XCTAssertEqual(mapped.y / mapped.z, simd_dot(hit, up), accuracy: 1e-7)
                    }
                }
            }
        }
    }

    func testOpeningAndClosingHaveDistinctPerspectiveAndAnchoredHinge() {
        let size = CGSize(width: 1440, height: 900)
        let close = DepthGeometry().screenToPicture(startAngle: 90, currentAngle: 60, screenSize: size)
        let open = DepthGeometry().screenToPicture(startAngle: 90, currentAngle: 120, screenSize: size)
        XCTAssertLessThan(close[1].z, 0)
        XCTAssertGreaterThan(open[1].z, 0)
        for matrix in [close, open] {
            XCTAssertEqual(matrix * SIMD3(0, 0, 1), SIMD3(0, 0, 1))
            XCTAssertEqual(matrix * SIMD3(1440, 0, 1), SIMD3(1440, 0, 1))
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
    func testProjectionIsIdentityAtRestAndFiniteAtExtremeAngles() {
        for start in stride(from: 0.0, through: 180, by: 5) {
            let flat = DepthGeometry().screenToPicture(startAngle: start, currentAngle: start,
                screenSize: CGSize(width: 1440, height: 900))
            XCTAssertEqual(flat, matrix_identity_double3x3)
            for current in stride(from: 0.0, through: 180, by: 5) {
                let matrix = DepthGeometry().screenToPicture(startAngle: start, currentAngle: current,
                    screenSize: CGSize(width: 1440, height: 900))
                for i in 0..<3 { for j in 0..<3 { XCTAssertTrue(matrix[i][j].isFinite) } }
            }
        }
    }
}
