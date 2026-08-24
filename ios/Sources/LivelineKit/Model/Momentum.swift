import Foundation

/// Momentum tint behaviour for the line and value readout.
///
/// A single flat enum, unlike web liveline's `true | 'up' | 'down' | 'flat'`
/// union. This divergence is intentional and recorded in `spec/API.md`.
///
/// - `off`: no momentum tint; the line uses the accent colour.
/// - `auto`: the tint tracks the sign of recent change (up/down derived live).
/// - `up`: force the "up" tint.
/// - `down`: force the "down" tint.
/// - `flat`: force the neutral tint.
public enum Momentum: String, Equatable, Hashable, Sendable, CaseIterable {
    case off
    case auto
    case up
    case down
    case flat
}
