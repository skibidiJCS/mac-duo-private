import Foundation

/// Exact critically damped response to a constant target; stable at any frame interval.
struct CriticallyDampedSpring {
    var value: Double
    var velocity: Double = 0
    var frequency: Double = 22

    init(value: Double = 0) { self.value = value }

    mutating func advance(to target: Double, dt: Double) {
        guard dt.isFinite, dt > 0, target.isFinite else { return }
        let offset = value - target
        let coefficient = velocity + frequency * offset
        let decay = exp(-frequency * dt)
        value = target + (offset + coefficient * dt) * decay
        velocity = (velocity - frequency * coefficient * dt) * decay
    }

    mutating func reset(to newValue: Double) {
        value = newValue
        velocity = 0
    }
}
