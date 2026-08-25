#if canImport(UIKit)
    import UIKit

    /// The multi-series legend: a row of tappable chips (colour dot + label)
    /// inside a subtle track. Tapping a chip hides/shows that series — the chip
    /// dims when hidden. Rendered natively so the bindings share one implementation.
    public final class SeriesLegendView: UIView {
        public struct Item {
            public let id: String
            public let color: UIColor
            public let label: String
            public init(id: String, color: UIColor, label: String) {
                self.id = id
                self.color = color
                self.label = label
            }
        }

        /// Called with the tapped series' id (visibility is tracked internally).
        public var onToggle: ((String) -> Void)?
        public var isDark = false { didSet { applyColors() } }
        public var items: [Item] = [] { didSet { rebuild() } }

        private let track = UIView()
        private var chips: [(id: String, view: UIView, dot: UIView, label: UILabel)] = []
        private var hiddenIds: Set<String> = []
        private let topInset: CGFloat = 6
        private let sideInset: CGFloat = 12
        private let chipH: CGFloat = 24

        public override init(frame: CGRect) {
            super.init(frame: frame)
            track.layer.cornerCurve = .continuous
            track.layer.masksToBounds = true
            addSubview(track)
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) { fatalError("init(coder:) not supported") }

        public override var intrinsicContentSize: CGSize {
            items.isEmpty
                ? CGSize(width: UIView.noIntrinsicMetric, height: 0)
                : CGSize(width: UIView.noIntrinsicMetric, height: chipH + 8 + topInset * 2)
        }

        private func font() -> UIFont { .systemFont(ofSize: 12, weight: .medium) }

        private func rebuild() {
            chips.forEach { $0.view.removeFromSuperview() }
            chips.removeAll()
            hiddenIds = hiddenIds.filter { id in items.contains { $0.id == id } }
            isHidden = items.isEmpty
            for item in items {
                let chip = UIView()
                chip.isUserInteractionEnabled = true
                chip.addGestureRecognizer(
                    UITapGestureRecognizer(target: self, action: #selector(chipTapped(_:))))
                let dot = UIView()
                dot.layer.cornerRadius = 3.5
                dot.backgroundColor = item.color
                let label = UILabel()
                label.text = item.label
                label.font = font()
                chip.addSubview(dot)
                chip.addSubview(label)
                track.addSubview(chip)
                chips.append((item.id, chip, dot, label))
            }
            applyColors()
            invalidateIntrinsicContentSize()
            setNeedsLayout()
        }

        private func applyColors() {
            track.backgroundColor = UIColor(white: isDark ? 1 : 0, alpha: isDark ? 0.03 : 0.02)
            let text = UIColor(white: isDark ? 1 : 0, alpha: isDark ? 0.7 : 0.6)
            for chip in chips {
                let on = !hiddenIds.contains(chip.id)
                chip.view.alpha = on ? 1 : 0.35
                chip.label.textColor = text
            }
        }

        @objc private func chipTapped(_ g: UITapGestureRecognizer) {
            guard let view = g.view, let chip = chips.first(where: { $0.view === view }) else { return }
            if hiddenIds.contains(chip.id) { hiddenIds.remove(chip.id) } else { hiddenIds.insert(chip.id) }
            applyColors()
            onToggle?(chip.id)
        }

        public override func layoutSubviews() {
            super.layoutSubviews()
            let dotSize: CGFloat = 7
            let innerGap: CGFloat = 5
            let chipGap: CGFloat = 4
            let padX: CGFloat = 10
            var x = padX
            for chip in chips {
                let labelW = ceil(
                    ((chip.label.text ?? "") as NSString).size(withAttributes: [.font: font()]).width)
                let w = padX + dotSize + innerGap + labelW + padX
                chip.dot.frame = CGRect(x: padX, y: (chipH - dotSize) / 2, width: dotSize, height: dotSize)
                chip.label.frame = CGRect(x: padX + dotSize + innerGap, y: 0, width: labelW, height: chipH)
                chip.view.frame = CGRect(x: x, y: 0, width: w, height: chipH)
                x += w + chipGap
            }
            let contentW = chips.isEmpty ? 0 : x - chipGap
            let trackH = chipH + 8
            track.frame = CGRect(x: sideInset, y: topInset, width: contentW, height: trackH)
            track.layer.cornerRadius = trackH / 2
            for chip in chips { chip.view.frame.origin.y = (trackH - chipH) / 2 }
        }
    }
#endif
