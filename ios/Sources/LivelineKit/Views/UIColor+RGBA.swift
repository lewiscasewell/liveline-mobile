#if canImport(UIKit)
import UIKit

extension UIColor {
    /// Creates a `UIColor` from a platform-neutral ``RGBA``.
    convenience init(rgba: RGBA) {
        self.init(
            red: CGFloat(rgba.r),
            green: CGFloat(rgba.g),
            blue: CGFloat(rgba.b),
            alpha: CGFloat(rgba.a)
        )
    }

    /// The colour as a platform-neutral ``RGBA`` in the extended sRGB space.
    var rgba: RGBA {
        var r: CGFloat = 0
        var g: CGFloat = 0
        var b: CGFloat = 0
        var a: CGFloat = 0
        getRed(&r, green: &g, blue: &b, alpha: &a)
        return RGBA(r: Double(r), g: Double(g), b: Double(b), a: Double(a))
    }
}
#endif
