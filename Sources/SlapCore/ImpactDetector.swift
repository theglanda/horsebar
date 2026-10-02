import Foundation

/// Turns a stream of accelerations into individual slaps.
/// Gravity is removed with a slow moving average (high-pass), then the peak is found within a short window.
public struct ImpactDetector {
    /// Anything quieter is noise and is never reported (g).
    public var floor: Double
    /// Window in which the peak of one slap is collected (s).
    public var window: TimeInterval
    /// How fast the baseline follows the signal.
    public var alpha: Double

    private var baseline: (Double, Double, Double)?
    private var peak = 0.0
    private var peakUntil: TimeInterval = 0

    public init(floor: Double = 0.03, window: TimeInterval = 0.03, alpha: Double = 0.005) {
        self.floor = floor
        self.window = window
        self.alpha = alpha
    }

    /// Returns the slap strength (g) once the slap is over, otherwise nil.
    public mutating func feed(x: Double, y: Double, z: Double, at now: TimeInterval) -> Double? {
        guard let b = baseline else {
            baseline = (x, y, z)
            return nil
        }
        let dx = x - b.0, dy = y - b.1, dz = z - b.2
        baseline = (b.0 + alpha * dx, b.1 + alpha * dy, b.2 + alpha * dz)
        let mag = (dx * dx + dy * dy + dz * dz).squareRoot()

        if mag > floor {
            if now > peakUntil { peak = 0 }
            peak = max(peak, mag)
            peakUntil = now + window
            return nil
        }
        if peak > 0 && now > peakUntil {
            defer { peak = 0 }
            return peak
        }
        return nil
    }
}
