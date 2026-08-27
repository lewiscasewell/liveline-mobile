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
    private let legend = LivelineKit.SeriesLegendView()
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
        legend.isHidden = true
        legend.onToggle = { [weak self] id in self?.chart.toggleSeries(id) }
        return LivelineContainerView(legend: legend, bar: bar, chart: chart)
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
    var series: [LivelineSeries]? {
        didSet {
            let list = series ?? []
            chart.setSeries(
                list.map { s in
                    LivelineView.SeriesInput(
                        id: s.id, color: UIColor(cssString: s.color), label: s.label,
                        data: s.data.map { LivelineKit.LivelinePoint(time: $0.time, value: $0.value) })
                })
            legend.items = list.map {
                .init(id: $0.id, color: UIColor(cssString: $0.color), label: $0.label ?? $0.id)
            }
            container.setNeedsLayout()
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
            legend.isDark = theme != .light
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
    var tooltipY: Double? {
        didSet { chart.tooltipY = tooltipY ?? 14 }
    }
    var tooltipOutline: Bool? {
        didSet { chart.tooltipOutline = tooltipOutline ?? true }
    }
    var padding: LivelinePadding? {
        didSet {
            chart.padTopOverride = padding?.top; chart.padRightOverride = padding?.right
            chart.padBottomOverride = padding?.bottom; chart.padLeftOverride = padding?.left
        }
    }
    // Legend isn't part of the container yet; stored until it is wired.
    var seriesToggleCompact: Bool?
    var onSeriesToggle: ((_ id: String, _ visible: Bool) -> Void)?
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

    var orderbook: LivelineOrderbook? {
        didSet { chart.setOrderbook(orderbook.map(Self.toOrderbook)) }
    }

    private static func toOrderbook(_ o: LivelineOrderbook) -> LivelineKit.OrderbookData {
        LivelineKit.OrderbookData(
            bids: o.bids.map { LivelineKit.OrderbookLevel(price: $0.price, size: $0.size) },
            asks: o.asks.map { LivelineKit.OrderbookLevel(price: $0.price, size: $0.size) })
    }

    // MARK: Declarative value formatting

    var valuePrefix: String? { didSet { rebuildFormatter() } }
    var valueSuffix: String? { didSet { rebuildFormatter() } }
    var valueDecimals: Double? { didSet { rebuildFormatter() } }
    var currency: String? { didSet { rebuildFormatter() } }
    var locale: String? {
        didSet {
            chart.formattingLocale = locale.flatMap { $0.isEmpty ? nil : Locale(identifier: $0) } ?? .current
            rebuildFormatter()
        }
    }
    var useGrouping: Bool? { didSet { rebuildFormatter() } }
    var fontFamily: String? {
        didSet {
            let f = (fontFamily?.isEmpty ?? true) ? nil : fontFamily
            chart.fontFamily = f
            bar.fontFamily = f
        }
    }

    private func rebuildFormatter() {
        let nf = NumberFormatter()
        nf.locale = locale.flatMap { $0.isEmpty ? nil : Locale(identifier: $0) } ?? .current
        nf.usesGroupingSeparator = useGrouping ?? true
        if let currency, !currency.isEmpty {
            // Currency style provides the symbol, its placement and the currency's
            // own default fraction digits (0 for JPY, 2 for USD, …); `valuePrefix`/
            // `valueSuffix`/`valueDecimals` don't apply here.
            nf.numberStyle = .currency
            nf.currencyCode = currency
            chart.formatValue = { nf.string(from: NSNumber(value: $0)) ?? "\($0)" }
        } else {
            nf.numberStyle = .decimal
            let decimals = Int(valueDecimals ?? 2)
            nf.minimumFractionDigits = decimals
            nf.maximumFractionDigits = decimals
            let prefix = valuePrefix ?? ""
            let suffix = valueSuffix ?? ""
            chart.formatValue = { prefix + (nf.string(from: NSNumber(value: $0)) ?? "\($0)") + suffix }
        }
    }

    // MARK: Methods

    func push(point: LivelinePoint, seriesId: String?) throws {
        // `push` is called from JS, which may not be the main thread. The chart
        // is UIKit/@MainActor and its render loop reads the buffer on main — so
        // hop to main to avoid a data race (intermittent SIGABRT deep in UIKit).
        let p = LivelineKit.LivelinePoint(time: point.time, value: point.value)
        if Thread.isMainThread {
            chart.push(p, seriesId: seriesId)
        } else {
            DispatchQueue.main.async { self.chart.push(p, seriesId: seriesId) }
        }
    }

    func pushOrderbook(orderbook: LivelineOrderbook) throws {
        // Like `push`, may be called off the main thread; hop to main.
        let book = Self.toOrderbook(orderbook)
        if Thread.isMainThread {
            chart.setOrderbook(book)
        } else {
            DispatchQueue.main.async { self.chart.setOrderbook(book) }
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
    private let legend: LivelineKit.SeriesLegendView
    private let bar: LivelineKit.WindowBarView
    private let chart: LivelineKit.LivelineView

    init(
        legend: LivelineKit.SeriesLegendView, bar: LivelineKit.WindowBarView,
        chart: LivelineKit.LivelineView
    ) {
        self.legend = legend
        self.bar = bar
        self.chart = chart
        super.init(frame: .zero)
        addSubview(chart)
        addSubview(legend)  // multi-series legend at the top
        addSubview(bar)  // interval bar at the bottom
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) not supported") }

    override func layoutSubviews() {
        super.layoutSubviews()
        // Legend on top, interval bar at the bottom, chart fills between.
        let legendH = legend.isHidden ? 0 : legend.intrinsicContentSize.height
        let barH = bar.isHidden ? 0 : bar.intrinsicContentSize.height
        legend.frame = CGRect(x: 0, y: 0, width: bounds.width, height: legendH)
        chart.frame = CGRect(x: 0, y: legendH, width: bounds.width, height: bounds.height - legendH - barH)
        bar.frame = CGRect(x: 0, y: bounds.height - barH, width: bounds.width, height: barH)
    }
}
