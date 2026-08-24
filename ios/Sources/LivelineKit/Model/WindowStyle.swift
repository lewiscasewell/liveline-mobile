import Foundation

/// Visual style of the time-window button bar.
///
/// - `default`: a segmented pill group with a sliding indicator.
/// - `rounded`: fully-rounded (capsule) pills.
/// - `text`: plain text buttons with no background.
public enum WindowStyle: String, Equatable, Hashable, Sendable, CaseIterable {
    case `default`
    case rounded
    case text
}
