import Foundation

/// A named time window, e.g. `Window(label: "1m", secs: 60)`.
///
/// Mirrors the `windows` prop of web liveline. Windows describe how much history
/// is visible; the render loop scrolls to keep `secs` seconds of data on screen.
public struct Window: Equatable, Hashable, Sendable, Identifiable {
    /// Stable identity derived from the label.
    public var id: String { label }
    /// Human-readable label shown on the window control, e.g. `"1m"`.
    public var label: String
    /// Duration of the window in seconds.
    public var secs: Double

    /// Creates a window.
    /// - Parameters:
    ///   - label: Human-readable label, e.g. `"1m"`.
    ///   - secs: Duration in seconds.
    public init(label: String, secs: Double) {
        self.label = label
        self.secs = secs
    }
}
