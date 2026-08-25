import Foundation

/// Visual style of the endpoint value badge.
///
/// - `default`: a momentum-tinted (green up / red down) pill with white text.
/// - `minimal`: a quieter neutral pill with primary text.
/// - `accent`: filled with the line/accent colour, with white text — keeps the
///   momentum arrows but drops the green/red tint.
public enum BadgeVariant: String, Equatable, Hashable, Sendable, CaseIterable {
    case `default`
    case minimal
    case accent
}
