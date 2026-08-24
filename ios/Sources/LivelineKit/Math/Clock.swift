import Foundation

/// Frame-rate-independent exponential smoothing, matching web liveline's `lerp`.
///
/// `speed` is the fraction of the remaining distance covered per 16.67 ms (one
/// 60 fps frame). The per-frame factor is `1 - (1 - speed)^(dt / 16.67)`, so the
/// result is invariant to the actual frame rate — a 60 fps and a 120 fps device
/// converge identically.
public enum Clock {
    /// One 60 fps frame, in milliseconds.
    public static let frameMs: Double = 16.67

    /// Smooths `current` toward `target`.
    /// - Parameters:
    ///   - current: The current value.
    ///   - target: The value to approach.
    ///   - speed: Fraction approached per 16.67 ms frame (`0...1`).
    ///   - dt: Elapsed time since the last update, in milliseconds.
    public static func lerp(current: Double, target: Double, speed: Double, dt: Double = frameMs) -> Double {
        let factor = 1 - pow(1 - speed, dt / frameMs)
        return current + (target - current) * factor
    }
}
