#if canImport(UIKit)
    import UIKit

    /// The built-in interval bar — built from native `UISegmentedControl`s so it
    /// adopts the system's Liquid Glass on iOS 26 automatically (exactly like a
    /// SwiftUI `.segmented` picker), instead of a hand-drawn look-alike. An
    /// optional line/candle toggle sits at the end. Reports taps via ``onSelect``
    /// / ``onModeSelect``.
    public final class WindowBarView: UIView {
        /// Retained for API compatibility; the native control supplies its own
        /// (Liquid Glass) style, so this no longer changes the appearance.
        public enum Style { case `default`, rounded, text }

        /// Called with the chosen span (seconds) when an interval segment is tapped.
        public var onSelect: ((Double) -> Void)?
        /// Called with `true` for candle, `false` for line when the toggle is tapped.
        public var onModeSelect: ((Bool) -> Void)?

        public var windows: [(label: String, secs: Double)] = [] { didSet { rebuildIntervals() } }
        public var style: Style = .default
        public var activeSecs: Double = 0 { didSet { syncInterval() } }
        public var isDark: Bool = false { didSet { applyAppearance() } }
        public var showModeToggle: Bool = false { didSet { rebuildMode() } }
        public var isCandle: Bool = false { didSet { syncMode() } }

        private let scroll = UIScrollView()
        private let intervalControl = UISegmentedControl()
        private let modeControl = UISegmentedControl()

        private let sideInset: CGFloat = 12
        private let topInset: CGFloat = 6
        private let groupGap: CGFloat = 8

        public override init(frame: CGRect) {
            super.init(frame: frame)
            scroll.showsHorizontalScrollIndicator = false
            scroll.showsVerticalScrollIndicator = false
            addSubview(scroll)
            // Size each segment to its own label rather than stretching equally.
            intervalControl.apportionsSegmentWidthsByContent = true
            modeControl.apportionsSegmentWidthsByContent = true
            intervalControl.addTarget(self, action: #selector(intervalChanged), for: .valueChanged)
            modeControl.addTarget(self, action: #selector(modeChanged), for: .valueChanged)
            scroll.addSubview(intervalControl)
            scroll.addSubview(modeControl)
            rebuildMode()
            applyAppearance()
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) { fatalError("init(coder:) not supported") }

        public override var intrinsicContentSize: CGSize {
            let h = max(intervalControl.intrinsicContentSize.height, 28)
            return CGSize(width: UIView.noIntrinsicMetric, height: h + topInset * 2)
        }

        private func rebuildIntervals() {
            intervalControl.removeAllSegments()
            for (i, w) in windows.enumerated() {
                intervalControl.insertSegment(withTitle: w.label, at: i, animated: false)
            }
            syncInterval()
            invalidateIntrinsicContentSize()
            setNeedsLayout()
        }

        private func rebuildMode() {
            modeControl.removeAllSegments()
            modeControl.isHidden = !showModeToggle
            guard showModeToggle else {
                setNeedsLayout()
                return
            }
            let cfg = UIImage.SymbolConfiguration(pointSize: 12, weight: .regular)
            for (i, icon) in ["chart.xyaxis.line", "chart.bar.xaxis"].enumerated() {
                modeControl.insertSegment(
                    with: UIImage(systemName: icon, withConfiguration: cfg), at: i, animated: false)
            }
            syncMode()
            setNeedsLayout()
        }

        private func syncInterval() {
            guard let idx = windows.firstIndex(where: { $0.secs == activeSecs }) else { return }
            if intervalControl.selectedSegmentIndex != idx { intervalControl.selectedSegmentIndex = idx }
        }

        private func syncMode() {
            let idx = isCandle ? 1 : 0
            if modeControl.numberOfSegments > idx, modeControl.selectedSegmentIndex != idx {
                modeControl.selectedSegmentIndex = idx
            }
        }

        private func applyAppearance() {
            let ui: UIUserInterfaceStyle = isDark ? .dark : .light
            intervalControl.overrideUserInterfaceStyle = ui
            modeControl.overrideUserInterfaceStyle = ui
            // Smaller and lighter than the native default — closer to the old bar.
            intervalControl.setTitleTextAttributes(
                [.font: UIFont.systemFont(ofSize: 12, weight: .regular), .foregroundColor: UIColor.secondaryLabel],
                for: .normal)
            intervalControl.setTitleTextAttributes(
                [.font: UIFont.systemFont(ofSize: 12, weight: .medium), .foregroundColor: UIColor.label],
                for: .selected)
        }

        @objc private func intervalChanged() {
            let i = intervalControl.selectedSegmentIndex
            guard i >= 0, i < windows.count else { return }
            onSelect?(windows[i].secs)
        }

        @objc private func modeChanged() {
            onModeSelect?(modeControl.selectedSegmentIndex == 1)
        }

        public override func layoutSubviews() {
            super.layoutSubviews()
            scroll.frame = bounds
            let h = intervalControl.intrinsicContentSize.height
            let intervalW = intervalControl.intrinsicContentSize.width
            let modeW = showModeToggle ? modeControl.intrinsicContentSize.width : 0
            let groupW = intervalW + (showModeToggle ? groupGap + modeW : 0)

            // Centre the group when it fits; otherwise left-align and scroll.
            let fits = groupW + sideInset * 2 <= bounds.width
            let originX = fits ? (bounds.width - groupW) / 2 : sideInset

            intervalControl.frame = CGRect(x: originX, y: topInset, width: intervalW, height: h)
            modeControl.frame = CGRect(
                x: intervalControl.frame.maxX + groupGap, y: topInset, width: modeW, height: h)

            let maxX = showModeToggle ? modeControl.frame.maxX : intervalControl.frame.maxX
            scroll.contentSize = CGSize(width: max(bounds.width, maxX + sideInset), height: bounds.height)
        }
    }
#endif
