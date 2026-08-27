#if canImport(UIKit)
    import UIKit

    /// A numeric label whose digits slide-and-fade when they change — the same
    /// "numeric text" content transition SwiftUI ships, hand-rolled for UIKit so
    /// it works as an overlay on the chart's Core Graphics canvas.
    ///
    /// The font is monospaced, so every glyph shares one advance width and the
    /// columns stay aligned; only the characters that actually change animate,
    /// each rolling in the direction the value moved (up when it rises).
    @MainActor
    final class TickerLabel: UIView {
        var font: UIFont = .monospacedSystemFont(ofSize: 20, weight: .medium) {
            didSet {
                measure()
                rebuild(chars)
            }
        }
        var textColor: UIColor = .label {
            didSet { for l in labels { l?.textColor = textColor } }
        }

        private var chars: [Character] = []
        private var labels: [UILabel?] = []
        private var charW: CGFloat = 0
        private var charH: CGFloat = 0

        /// The text currently displayed — lets the caller skip redundant updates.
        var currentText: String { String(chars) }

        override init(frame: CGRect) {
            super.init(frame: frame)
            clipsToBounds = true
            measure()
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) { fatalError("init(coder:) not supported") }

        override var intrinsicContentSize: CGSize {
            CGSize(width: charW * CGFloat(chars.count), height: charH)
        }

        private func measure() {
            let s = ("0" as NSString).size(withAttributes: [.font: font])
            charW = ceil(s.width)
            charH = ceil(s.height)
        }

        private func makeLabel(_ c: Character) -> UILabel {
            let l = UILabel()
            l.font = font
            l.textColor = textColor
            l.textAlignment = .center
            l.text = String(c)
            return l
        }

        private func frameFor(_ i: Int) -> CGRect {
            CGRect(x: CGFloat(i) * charW, y: 0, width: charW, height: charH)
        }

        /// Rebuild the whole row without animation (used when the length changes).
        private func rebuild(_ new: [Character]) {
            labels.forEach { $0?.removeFromSuperview() }
            labels = new.enumerated().map { i, c in
                let l = makeLabel(c)
                l.frame = frameFor(i)
                addSubview(l)
                return l
            }
            chars = new
            invalidateIntrinsicContentSize()
        }

        /// Set the displayed text. `up` rolls new digits in from below (a rising
        /// value); `false` rolls them from above.
        func setText(_ newText: String, up: Bool) {
            let new = Array(newText)
            if chars.isEmpty {
                rebuild(new)  // first show: nothing to animate from
                return
            }
            if new.count != chars.count {
                transition(to: new, up: up)
                return
            }
            for i in 0..<new.count where new[i] != chars[i] {
                animateChange(at: i, to: new[i], up: up)
            }
            chars = new
        }

        /// The digit count changed (e.g. the value crossed 100): roll the whole
        /// row over — old characters slide out, new ones slide in — rather than
        /// snapping.
        private func transition(to new: [Character], up: Bool) {
            for l in labels {
                guard let l else { continue }
                UIView.animate(
                    withDuration: 0.26, delay: 0, options: [.curveEaseIn, .beginFromCurrentState]
                ) {
                    l.frame = l.frame.offsetBy(dx: 0, dy: up ? -self.charH : self.charH)
                    l.alpha = 0
                } completion: { _ in l.removeFromSuperview() }
            }
            labels = new.enumerated().map { i, c in
                let l = makeLabel(c)
                let rest = frameFor(i)
                l.frame = rest.offsetBy(dx: 0, dy: up ? self.charH : -self.charH)
                l.alpha = 0
                addSubview(l)
                UIView.animate(
                    withDuration: 0.26, delay: 0.03, options: [.curveEaseOut, .beginFromCurrentState]
                ) {
                    l.frame = rest
                    l.alpha = 1
                }
                return l
            }
            chars = new
            invalidateIntrinsicContentSize()
        }

        private func animateChange(at i: Int, to c: Character, up: Bool) {
            let rest = frameFor(i)
            let old = labels[i]
            let incoming = makeLabel(c)
            incoming.frame = rest.offsetBy(dx: 0, dy: up ? charH : -charH)
            incoming.alpha = 0
            addSubview(incoming)
            labels[i] = incoming
            UIView.animate(
                withDuration: 0.28, delay: 0,
                options: [.curveEaseOut, .beginFromCurrentState]
            ) {
                incoming.frame = rest
                incoming.alpha = 1
                old?.frame = rest.offsetBy(dx: 0, dy: up ? -self.charH : self.charH)
                old?.alpha = 0
            } completion: { _ in
                old?.removeFromSuperview()
            }
        }
    }
#endif
