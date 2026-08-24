import Foundation

/// The resolved direction of the line, used to colour the badge and pick the
/// endpoint arrows. Mirrors web liveline's `Momentum` type (`'up' | 'down' |
/// 'flat'`) — distinct from the ``Momentum`` *prop*, which also carries the
/// `off`/`auto` selection.
public enum Trend: String, Equatable, Hashable, Sendable {
    case up
    case down
    case flat
}
