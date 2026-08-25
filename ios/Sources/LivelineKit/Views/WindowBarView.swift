#if canImport(UIKit)
    import UIKit

    /// The built-in interval bar — a segmented control matching web liveline's
    /// `windows` / `windowStyle`, with an optional line/candle mode toggle at the
    /// end. Rendered natively (not in JS) so the chart's bindings share one
    /// implementation. Reports taps via ``onSelect`` / ``onModeSelect``.
    public final class WindowBarView: UIView {
        public enum Style { case `default`, rounded, text }

        /// Called with the chosen span (seconds) when an interval button is tapped.
        public var onSelect: ((Double) -> Void)?
        /// Called with `true` for candle, `false` for line when the mode toggle is tapped.
        public var onModeSelect: ((Bool) -> Void)?

        public var windows: [(label: String, secs: Double)] = [] { didSet { rebuild() } }
        public var style: Style = .default { didSet { rebuild() } }
        public var activeSecs: Double = 0 { didSet { updateColors() } }
        public var isDark: Bool = false { didSet { updateColors() } }
        public var showModeToggle: Bool = false { didSet { rebuild() } }
        public var isCandle: Bool = false { didSet { updateColors() } }

        private let scroll = UIScrollView()
        private let intervalBar = UIView()
        private let modeBar = UIView()
        private var buttons: [(secs: Double, button: UIButton)] = []
        private var modeButtons: [(candle: Bool, button: UIButton)] = []

        private let barHeight: CGFloat = 28
        private let sideInset: CGFloat = 12
        private let topInset: CGFloat = 6
        private let groupGap: CGFloat = 8

        public override init(frame: CGRect) {
            super.init(frame: frame)
            scroll.showsHorizontalScrollIndicator = false
            scroll.showsVerticalScrollIndicator = false
            addSubview(scroll)
            intervalBar.layer.masksToBounds = true
            modeBar.layer.masksToBounds = true
            scroll.addSubview(intervalBar)
            scroll.addSubview(modeBar)
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) { fatalError("init(coder:) not supported") }

        public override var intrinsicContentSize: CGSize {
            CGSize(width: UIView.noIntrinsicMetric, height: barHeight + topInset * 2)
        }

        private var isText: Bool { style == .text }
        private var pad: CGFloat { isText ? 0 : (style == .rounded ? 3 : 2) }
        private func gray(_ alpha: Double) -> UIColor { UIColor(white: isDark ? 1 : 0, alpha: CGFloat(alpha)) }

        private func rebuild() {
            buttons.forEach { $0.button.removeFromSuperview() }
            buttons.removeAll()
            for w in windows {
                let b = makeButton()
                b.setTitle(w.label, for: .normal)
                let secs = w.secs
                b.addAction(UIAction { [weak self] _ in self?.onSelect?(secs) }, for: .touchUpInside)
                intervalBar.addSubview(b)
                buttons.append((secs, b))
            }

            modeButtons.forEach { $0.button.removeFromSuperview() }
            modeButtons.removeAll()
            modeBar.isHidden = !showModeToggle
            if showModeToggle {
                let cfg = UIImage.SymbolConfiguration(pointSize: 12, weight: .regular)
                for (candle, icon) in [(false, "chart.xyaxis.line"), (true, "chart.bar.xaxis")] {
                    let b = makeButton()
                    b.setImage(UIImage(systemName: icon, withConfiguration: cfg), for: .normal)
                    b.addAction(UIAction { [weak self] _ in self?.onModeSelect?(candle) }, for: .touchUpInside)
                    modeBar.addSubview(b)
                    modeButtons.append((candle, b))
                }
            }

            updateColors()
            invalidateIntrinsicContentSize()
            setNeedsLayout()
        }

        private func makeButton() -> UIButton {
            let b = UIButton(type: .custom)
            let padX: CGFloat = isText ? 6 : 10
            let padY: CGFloat = isText ? 2 : 3
            b.contentEdgeInsets = UIEdgeInsets(top: padY, left: padX, bottom: padY, right: padX)
            b.layer.masksToBounds = true
            return b
        }

        private func updateColors() {
            let containerBg = isText ? UIColor.clear : gray(WindowBarTokens.trackAlpha(isDark: isDark))
            intervalBar.backgroundColor = containerBg
            modeBar.backgroundColor = containerBg
            let indicator = gray(WindowBarTokens.indicatorAlpha(isDark: isDark))
            let active = gray(WindowBarTokens.activeAlpha(isDark: isDark))
            let inactive = gray(WindowBarTokens.inactiveAlpha(isDark: isDark))

            for (secs, b) in buttons {
                let on = secs == activeSecs
                b.setTitleColor(on ? active : inactive, for: .normal)
                b.titleLabel?.font = .systemFont(ofSize: CGFloat(WindowBarTokens.fontSize), weight: on ? .semibold : .regular)
                b.backgroundColor = (on && !isText) ? indicator : .clear
            }
            for (candle, b) in modeButtons {
                let on = candle == isCandle
                b.tintColor = on ? active : inactive
                b.backgroundColor = (on && !isText) ? indicator : .clear
            }
            setNeedsLayout()
        }

        /// Lays a container's buttons left→right and returns its content width.
        private func layout(_ container: UIView, _ items: [UIButton], sizedByTitle: Bool) -> CGFloat {
            let spacing: CGFloat = isText ? 4 : 2
            let padX: CGFloat = isText ? 6 : 10
            let btnH = barHeight - pad * 2
            let sizingFont = UIFont.systemFont(ofSize: CGFloat(WindowBarTokens.fontSize), weight: .semibold)
            var x = pad
            for b in items {
                // Icons get a fixed width; titles are sized to their semibold width so
                // the frame never changes (and never clips to "…") when active.
                let w: CGFloat
                if sizedByTitle {
                    let label = b.title(for: .normal) ?? ""
                    w = ceil((label as NSString).size(withAttributes: [.font: sizingFont]).width) + padX * 2
                } else {
                    w = 18 + padX * 2
                }
                b.frame = CGRect(x: x, y: pad, width: w, height: btnH)
                b.layer.cornerRadius = style == .rounded ? btnH / 2 : (isText ? 0 : 4)
                x += w + spacing
            }
            return (items.isEmpty ? 0 : x - spacing) + pad
        }

        public override func layoutSubviews() {
            super.layoutSubviews()
            scroll.frame = bounds

            let intervalW = layout(intervalBar, buttons.map { $0.button }, sizedByTitle: true)
            let modeW = showModeToggle ? layout(modeBar, modeButtons.map { $0.button }, sizedByTitle: false) : 0
            let groupW = intervalW + (showModeToggle ? groupGap + modeW : 0)

            let fits = groupW + sideInset * 2 <= bounds.width
            let originX = fits ? (bounds.width - groupW) / 2 : sideInset
            let radius: CGFloat = style == .rounded ? barHeight / 2 : (isText ? 0 : 6)

            intervalBar.frame = CGRect(x: originX, y: topInset, width: intervalW, height: barHeight)
            intervalBar.layer.cornerRadius = radius
            modeBar.frame = CGRect(
                x: intervalBar.frame.maxX + groupGap, y: topInset, width: modeW, height: barHeight)
            modeBar.layer.cornerRadius = radius

            let maxX = showModeToggle ? modeBar.frame.maxX : intervalBar.frame.maxX
            scroll.contentSize = CGSize(width: max(bounds.width, maxX + sideInset), height: bounds.height)
        }
    }
#endif
