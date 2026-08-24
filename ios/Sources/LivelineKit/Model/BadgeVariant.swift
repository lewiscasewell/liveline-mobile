import Foundation

/// Visual style of the endpoint value badge.
///
/// - `default`: an accent-filled (or momentum-tinted) pill with white text.
/// - `minimal`: a quieter neutral pill with primary text.
public enum BadgeVariant: String, Equatable, Hashable, Sendable, CaseIterable {
    case `default`
    case minimal
}
