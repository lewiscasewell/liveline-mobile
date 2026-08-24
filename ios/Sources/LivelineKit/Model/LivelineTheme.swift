import Foundation

/// Selects the base surface a chart is drawn on. The accent colour is supplied
/// separately (via `color`); the theme decides background, grid and text tones.
public enum LivelineTheme: String, Equatable, Hashable, Sendable, CaseIterable {
    case light
    case dark
}
