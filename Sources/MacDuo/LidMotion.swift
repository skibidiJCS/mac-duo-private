import Foundation

/// Pure gesture state, independent of capture and rendering.
struct LidMotion {
    enum Phase { case idle, tracking, settling }
    static let movementThreshold = 1.5
    // Visual approximation of the supplied reference, not an Apple constant.
    static let holdDelay = 0.85
    static let settleDuration = 0.32
    private(set) var phase: Phase = .idle
    private(set) var anchor: Double = 90
    private(set) var angle: Double = 90
    private var motionReference: Double = 90
    private var lastMotion: TimeInterval = 0
    private var settleStart: TimeInterval = 0

    mutating func reset(angle: Double, at now: TimeInterval) {
        self.angle = angle
        anchor = angle
        motionReference = angle
        lastMotion = now
        phase = .idle
    }

    func reference(at now: TimeInterval) -> Double {
        guard phase == .settling else { return anchor }
        let t = min(max((now - settleStart) / Self.settleDuration, 0), 1)
        let ease = t * t * (3 - 2 * t)
        return anchor + (angle - anchor) * ease
    }

    /// True only for a fresh gesture that needs a new desktop frame.
    @discardableResult
    mutating func sample(_ value: Double, at now: TimeInterval) -> Bool {
        guard value.isFinite, (0...180).contains(value) else { return false }
        let previousReference = reference(at: now)
        angle = value
        let moved = abs(value - motionReference) >= Self.movementThreshold
        if moved {
            motionReference = value
            lastMotion = now
            if phase == .idle {
                phase = .tracking
                return true
            }
            if phase == .settling {
                // Continue from the currently visible plane without a jump.
                anchor = previousReference
                phase = .tracking
            }
        }
        if phase == .tracking, now - lastMotion >= Self.holdDelay {
            phase = .settling
            settleStart = now
        } else if phase == .settling, now - settleStart >= Self.settleDuration {
            reset(angle: value, at: now)
        }
        return false
    }
}
