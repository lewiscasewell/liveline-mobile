import Foundation
import LivelineKit
import NitroModules
import UIKit

/// The Nitro HybridView implementation: instantiates the native `LivelineView`
/// from LivelineKit and forwards props/methods to it. No drawing or chart maths
/// live here — that all belongs to LivelineKit.
///
/// Types from LivelineKit are qualified because the Nitrogen-generated types
/// (`LivelinePoint`, `CandlePoint`, `LivelineMode`, `LivelineTheme`, …) share
/// their names.
///
/// Marked `@MainActor` — Nitro applies view props and calls methods on the main
/// thread, keeping it on the same actor as the `@MainActor` `LivelineView`.
/// (The binding pod builds in Swift 5 language mode; see the podspec/Podfile.)
@MainActor
final class HybridLivelineView: HybridLivelineSpec {
    private let chart = LivelineKit.LivelineView()
    private let bar = LivelineKit.WindowBarView()
    private var lastValue: Double?

    /// Notifies JS when a window button is tapped (set by Nitro).
    var onWindowChange: ((_ secs: Double) -> Void)?
    /// Notifies JS when the mode toggle is tapped; its presence shows the toggle.
    var onModeChange: ((_ mode: LivelineMode) -> Void)? {
        didSet { bar.showModeToggle = onModeChange != nil }
    }

    private lazy var container: LivelineContainerView = {
        bar.isHidden = true
        bar.onSelect = { [weak self] secs in
            guard let self else { return }
            // Optimistic native update (no JS round-trip lag), then notify JS.
            self.chart.windowSeconds = secs
            self.bar.activeSecs = secs
            self.onWindowChange?(secs)
        }
        bar.onModeSelect = { [weak self] candle in
            guard let self else { return }
            self.chart.mode = candle ? .candle : .line
            self.bar.isCandle = candle
            self.onModeChange?(candle ? .candle : .line)
        }
        return LivelineContainerView(bar: bar, chart: chart)
    }()

    /// The UIView Nitro mounts into the RN view tree — the bar stacked above the chart.
    var view: UIView { container }

    // MARK: Window bar

    var windows: [WindowOption]? {
        didSet {
            let ws = windows ?? []
            bar.windows = ws.map { (label: $0.label, secs: $0.secs) }
            bar.isHidden = ws.isEmpty
            container.setNeedsLayout()
        }
    }

    var windowStyle: LivelineWindowStyle? {
        didSet {
            switch windowStyle {
            case .rounded: bar.style = .rounded
            case .text: bar.style = .text
            default: bar.style = .default
            }
        }
    }

    // MARK: Data

    var data: [LivelinePoint]? {
        didSet {
            guard let data else { return }
            chart.setData(data.map { LivelineKit.LivelinePoint(time: $0.time, value: $0.value) })
        }
    }

    var value: Double? {
        didSet {
            guard let value, value != lastValue else { return }
            lastValue = value
            chart.push(LivelineKit.LivelinePoint(time: Date().timeIntervalSince1970, value: value))
        }
    }

    // MARK: Candle mode

    var mode: LivelineMode? {
        didSet {
            chart.mode = (mode == .candle) ? .candle : .line
            bar.isCandle = mode == .candle
        }
    }

    var candles: [CandlePoint]? {
        didSet {
            chart.candles = (candles ?? []).map {
                LivelineKit.LivelineCandle(
                    time: $0.time, open: $0.open, high: $0.high, low: $0.low, close: $0.close)
            }
        }
    }

    var candleWidth: Double? {
        didSet { if let candleWidth { chart.candleWidth = candleWidth } }
    }

    var liveCandle: CandlePoint? {
        didSet {
            chart.liveCandle = liveCandle.map {
                LivelineKit.LivelineCandle(
                    time: $0.time, open: $0.open, high: $0.high, low: $0.low, close: $0.close)
            }
        }
    }

    // MARK: Appearance

    var color: String? {
        didSet { if let color { chart.color = UIColor(cssString: color) } }
    }

    var theme: LivelineTheme? {
        didSet {
            chart.theme = (theme == .light) ? .light : .dark
            bar.isDark = theme != .light
        }
    }

    var surfaceColor: String? {
        // Empty string (the JS default) means "no override" → theme default.
        didSet {
            if let surfaceColor, !surfaceColor.isEmpty {
                chart.surfaceColor = UIColor(cssString: surfaceColor)
            } else {
                chart.surfaceColor = nil
            }
        }
    }

    var lineWidth: Double? {
        didSet { if let lineWidth { chart.lineWidth = CGFloat(lineWidth) } }
    }

    // MARK: Time

    var window: Double? {
        didSet {
            if let window {
                chart.windowSeconds = window
                bar.activeSecs = window
            }
        }
    }

    // MARK: Feature flags

    var grid: Bool? {
        didSet { chart.grid = grid ?? true }
    }
    var badge: Bool? {
        didSet { chart.badge = badge ?? true }
    }
    var badgeTail: Bool? {
        didSet { chart.badgeTail = badgeTail ?? true }
    }
    var badgeVariant: LivelineBadgeVariant? {
        didSet {
            switch badgeVariant {
            case .minimal: chart.badgeVariant = .minimal
            case .accent: chart.badgeVariant = .accent
            default: chart.badgeVariant = .default
            }
        }
    }
    var momentum: LivelineMomentum? {
        didSet {
            switch momentum {
            case .off: chart.momentum = .off
            case .auto, .none: chart.momentum = .auto
            case .up: chart.momentum = .up
            case .down: chart.momentum = .down
            case .flat: chart.momentum = .flat
            }
        }
    }
    var fill: Bool? {
        didSet { chart.fill = fill ?? true }
    }
    var scrub: Bool? {
        didSet { chart.scrub = scrub ?? true }
    }
    var pulse: Bool? {
        didSet { chart.pulse = pulse ?? true }
    }
    var exaggerate: Bool? {
        didSet { chart.exaggerate = exaggerate ?? false }
    }
    var paused: Bool? {
        didSet { chart.paused = paused ?? false }
    }
    var loading: Bool? {
        didSet { chart.loading = loading ?? false }
    }
    var emptyText: String? {
        didSet { if let emptyText { chart.emptyText = emptyText } }
    }
    var showValue: Bool? {
        didSet { chart.showValue = showValue ?? false }
    }
    var valueMomentumColor: Bool? {
        didSet { chart.valueMomentumColor = valueMomentumColor ?? false }
    }
    var haptics: Bool? {
        didSet { chart.haptics = haptics ?? false }
    }
    var degen: Bool? {
        didSet { chart.degen = degen ?? false }
    }
    var lerpSpeed: Double? {
        didSet { if let lerpSpeed { chart.lerpSpeed = lerpSpeed } }
    }
    var referenceLine: LivelineReference? {
        // A non-finite value (the JS wrapper's sentinel) means "no line".
        didSet {
            if let r = referenceLine, r.value.isFinite {
                chart.referenceLine = LivelineKit.ReferenceLine(value: r.value, label: r.label)
            } else {
                chart.referenceLine = nil
            }
        }
    }

    // MARK: Declarative value formatting

    var valuePrefix: String? { didSet { rebuildFormatter() } }
    var valueSuffix: String? { didSet { rebuildFormatter() } }
    var valueDecimals: Double? { didSet { rebuildFormatter() } }

    private func rebuildFormatter() {
        let prefix = valuePrefix ?? ""
        let suffix = valueSuffix ?? ""
        let decimals = Int(valueDecimals ?? 2)
        chart.formatValue = { v in prefix + String(format: "%.\(decimals)f", v) + suffix }
    }

    // MARK: Methods

    func push(point: LivelinePoint) throws {
        // `push` is called from JS, which may not be the main thread. The chart
        // is UIKit/@MainActor and its render loop reads the buffer on main — so
        // hop to main to avoid a data race (intermittent SIGABRT deep in UIKit).
        let p = LivelineKit.LivelinePoint(time: point.time, value: point.value)
        if Thread.isMainThread {
            chart.push(p)
        } else {
            DispatchQueue.main.async { self.chart.push(p) }
        }
    }
}

extension UIColor {
    /// Minimal CSS-colour parse for the binding: `#rgb` or `#rrggbb`. Falls back
    /// to the liveline default blue for anything else.
    fileprivate convenience init(cssString: String) {
        let s = cssString.trimmingCharacters(in: .whitespaces)
        if s.hasPrefix("#") {
            var hex = String(s.dropFirst())
            if hex.count == 3 { hex = hex.map { "\($0)\($0)" }.joined() }
            if hex.count == 6, let v = UInt64(hex, radix: 16) {
                self.init(
                    red: CGFloat((v & 0xFF0000) >> 16) / 255,
                    green: CGFloat((v & 0x00FF00) >> 8) / 255,
                    blue: CGFloat(v & 0x0000FF) / 255,
                    alpha: 1)
                return
            }
        }
        self.init(red: 59 / 255, green: 130 / 255, blue: 246 / 255, alpha: 1)
    }
}

/// Stacks the interval bar above the chart. When there are no windows the bar is
/// hidden and the chart fills the whole view.
final class LivelineContainerView: UIView {
    private let bar: LivelineKit.WindowBarView
    private let chart: LivelineKit.LivelineView

    init(bar: LivelineKit.WindowBarView, chart: LivelineKit.LivelineView) {
        self.bar = bar
        self.chart = chart
        super.init(frame: .zero)
        addSubview(bar)
        addSubview(chart)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) not supported") }

    override func layoutSubviews() {
        super.layoutSubviews()
        // Bar at the BOTTOM (mobile placement); the chart fills the space above.
        let barH = bar.isHidden ? 0 : bar.intrinsicContentSize.height
        chart.frame = CGRect(x: 0, y: 0, width: bounds.width, height: bounds.height - barH)
        bar.frame = CGRect(x: 0, y: bounds.height - barH, width: bounds.width, height: barH)
    }
}
