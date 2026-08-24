import Foundation

/// A horizontal reference line drawn at a fixed value, with an optional label.
/// The value is always kept in view by the autoscale.
public struct ReferenceLine: Equatable, Hashable, Sendable {
    /// The value at which the line is drawn.
    public var value: Double
    /// Optional centred label; when set, the line breaks around the text.
    public var label: String?

    /// Creates a reference line.
    public init(value: Double, label: String? = nil) {
        self.value = value
        self.label = label
    }
}
