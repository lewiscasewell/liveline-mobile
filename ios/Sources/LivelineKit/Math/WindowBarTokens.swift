import Foundation

/// Shared design tokens for the interval-bar chrome, so the UIKit
/// (`WindowBarView`) and SwiftUI (`WindowBar`) implementations stay in lock-step
/// — change a value here and both bars follow. The bar is grayscale: white on a
/// dark appearance, black on light, at the alphas below. Values mirror web
/// liveline's window-bar styling.
public enum WindowBarTokens {
    /// Point size for interval labels.
    public static let fontSize: Double = 11

    /// Container/track background alpha.
    public static func trackAlpha(isDark: Bool) -> Double { isDark ? 0.03 : 0.02 }
    /// Active-button indicator fill alpha.
    public static func indicatorAlpha(isDark: Bool) -> Double { isDark ? 0.06 : 0.035 }
    /// Active label/icon alpha.
    public static func activeAlpha(isDark: Bool) -> Double { isDark ? 0.7 : 0.55 }
    /// Inactive label/icon alpha.
    public static func inactiveAlpha(isDark: Bool) -> Double { isDark ? 0.25 : 0.22 }
}
