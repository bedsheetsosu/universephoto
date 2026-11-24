import Foundation

/// "Ink nib": the faster the Pencil moves, the lighter the pressure.
public enum SpeedPressure {
    /// Speed (points per second) at which the full effect is reached.
    public static let fullSpeed: Double = 2500

    /// `amount` 0…1: at full speed the pressure drops to `1 - 0.75 * amount` of itself.
    public static func apply(_ pressure: Double, speed: Double, amount: Double) -> Double {
        guard amount > 0 else { return pressure }
        let t = min(max(speed / fullSpeed, 0), 1)
        let eased = t * t * (3 - 2 * t)
        return pressure * (1 - 0.75 * min(amount, 1) * eased)
    }
}
