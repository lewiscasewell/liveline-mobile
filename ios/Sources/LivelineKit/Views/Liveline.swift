#if canImport(UIKit)
import SwiftUI

/// A SwiftUI live line chart, wrapping ``LivelineView``.
///
/// Configuration is opt-in through chained modifiers whose names match web
/// liveline exactly, so the same prop vocabulary carries across platforms:
///
/// ```swift
/// Liveline(data: data, value: value)
///     .color(.blue)
///     .theme(.dark)
///     .momentum(.auto)
///     .showValue(true)
///     .windows([.init(label: "1m", secs: 60)])
///     .frame(height: 300)
/// ```
///
/// `data` is **backfill only**. For a live feed, drive `value` — each new value
/// is appended as a sample — which mirrors the mobile `push()` path and avoids
/// re-marshalling a growing array every tick.
@MainActor
public struct Liveline: View {
    private var data: [LivelinePoint]
    private var value: Double?
    private var series: [LivelineView.SeriesInput] = []
    private var seriesValues: [String: Double] = [:]
    private var orderbook: OrderbookData?

    // Configuration (defaults mirror web liveline).
    private var color: Color = Color(red: 59 / 255, green: 130 / 255, blue: 246 / 255)
    private var theme: LivelineTheme = .dark
    private var surfaceColor: Color?
    private var paletteOverrides: ((inout Palette) -> Void)?
    private var window: Double = 30
    private var grid = true
    private var badge = true
    private var badgeTail = true
    private var badgeVariant: BadgeVariant = .default
    private var momentum: Momentum = .auto
    private var fill = true
    private var scrub = true
    private var pulse = true
    private var exaggerate = false
    private var paused = false
    private var loading = false
    private var emptyText = "No data to display"
    private var showValue = false
    private var valueMomentumColor = false
    private var haptics = false
    private var degen = false
    private var referenceLine: ReferenceLine?
    private var windows: [Window] = []
    private var windowStyle: WindowStyle = .default
    private var lineWidth: CGFloat = 2
    private var lerpSpeed: Double = 0.08
    private var formatValue: ((Double) -> String)?
    private var formatTime: ((Double) -> String)?
    private var formattingLocale: Locale = .current
    private var fontFamily: String?

    // Candle mode.
    private var mode: LivelineMode = .line
    private var candles: [LivelineCandle] = []
    private var candleWidth: Double = 1
    private var liveCandle: LivelineCandle?
    private var modeToggle = false
    private var onModeChange: ((LivelineMode) -> Void)?

    /// Creates a chart.
    /// - Parameters:
    ///   - data: Initial backfill series. Not re-sent on every value change.
    ///   - value: The latest live value; each distinct value is appended as a
    ///     new sample timestamped with the current time.
    public init(data: [LivelinePoint] = [], value: Double? = nil) {
        self.data = data
        self.value = value
    }

    /// The chart, its multi-series legend and the interval bar, all composed in
    /// one UIView container. The bar is the library's own ``WindowBarView`` — the
    /// same native control the React Native binding uses — so window selection is
    /// driven natively rather than by a SwiftUI reimplementation.
    public var body: some View {
        Representable(config: self)
    }

    // MARK: Modifiers (return Self)

    /// Sets the accent colour.
    public func color(_ v: Color) -> Self { with { $0.color = v } }
    /// Sets the base theme (the tone of grid/labels/text).
    public func theme(_ v: LivelineTheme) -> Self { with { $0.theme = v } }
    /// Overrides the chart surface colour independently of the theme. Use a
    /// clear colour to let the container show through.
    public func surfaceColor(_ v: Color?) -> Self { with { $0.surfaceColor = v } }
    /// Overrides any derived palette colours. Receives the theme-derived
    /// ``Palette`` to mutate.
    public func paletteOverrides(_ v: @escaping (inout Palette) -> Void) -> Self {
        with { $0.paletteOverrides = v }
    }
    /// Sets the visible span in seconds.
    public func window(_ v: Double) -> Self { with { $0.window = v } }
    /// Toggles the value grid.
    public func grid(_ v: Bool = true) -> Self { with { $0.grid = v } }
    /// Toggles the endpoint badge.
    public func badge(_ v: Bool = true) -> Self { with { $0.badge = v } }
    /// Toggles the badge tail.
    public func badgeTail(_ v: Bool = true) -> Self { with { $0.badgeTail = v } }
    /// Sets the badge style.
    public func badgeVariant(_ v: BadgeVariant) -> Self { with { $0.badgeVariant = v } }
    /// Sets the momentum behaviour.
    public func momentum(_ v: Momentum) -> Self { with { $0.momentum = v } }
    /// Toggles the area fill.
    public func fill(_ v: Bool = true) -> Self { with { $0.fill = v } }
    /// Toggles crosshair scrubbing.
    public func scrub(_ v: Bool = true) -> Self { with { $0.scrub = v } }
    /// Toggles the live-dot pulse.
    public func pulse(_ v: Bool = true) -> Self { with { $0.pulse = v } }
    /// Tightens the Y range so small moves fill the height.
    public func exaggerate(_ v: Bool = true) -> Self { with { $0.exaggerate = v } }
    /// Freezes scrolling while data keeps arriving.
    public func paused(_ v: Bool = true) -> Self { with { $0.paused = v } }
    /// Shows the breathing loading animation.
    public func loading(_ v: Bool = true) -> Self { with { $0.loading = v } }
    /// Sets the empty-state message.
    public func emptyText(_ v: String) -> Self { with { $0.emptyText = v } }
    /// Shows the live value overlay.
    public func showValue(_ v: Bool = true) -> Self { with { $0.showValue = v } }
    /// Tints the value overlay by momentum.
    public func valueMomentumColor(_ v: Bool = true) -> Self { with { $0.valueMomentumColor = v } }
    /// Light haptic taps while scrubbing + a hit on each degen burst.
    public func haptics(_ v: Bool = true) -> Self { with { $0.haptics = v } }
    /// Degen mode: chart shake + sparks on strong upward moves.
    public func degen(_ v: Bool = true) -> Self { with { $0.degen = v } }
    /// Adds a horizontal reference line.
    public func referenceLine(_ v: ReferenceLine?) -> Self { with { $0.referenceLine = v } }
    /// Sets the named time windows (renders a button bar; the first is initially selected).
    public func windows(_ v: [Window]) -> Self { with { $0.windows = v } }
    /// Sets the time-window button style.
    public func windowStyle(_ v: WindowStyle) -> Self { with { $0.windowStyle = v } }
    /// Sets the line stroke width.
    public func lineWidth(_ v: CGFloat) -> Self { with { $0.lineWidth = v } }
    /// Sets the base easing speed.
    public func lerpSpeed(_ v: Double) -> Self { with { $0.lerpSpeed = v } }
    /// Sets a custom value formatter.
    public func formatValue(_ v: @escaping (Double) -> String) -> Self { with { $0.formatValue = v } }
    /// Sets a custom time formatter.
    public func formatTime(_ v: @escaping (Double) -> String) -> Self { with { $0.formatTime = v } }
    /// Locale for the built-in time axis/crosshair formatting. Default `.current`.
    public func locale(_ v: Locale) -> Self { with { $0.formattingLocale = v } }
    /// Font family for all chart text (registered by the app). Default: system mono.
    public func fontFamily(_ v: String?) -> Self { with { $0.fontFamily = v } }
    /// Multi-series mode: a set of equal-peer lines (each with its own colour,
    /// endpoint dot, dashed baseline and label). A non-empty array replaces
    /// `data`/`value` and renders a legend of toggle chips above the chart. Feed
    /// live updates with ``seriesValues(_:)``.
    public func series(_ v: [LivelineView.SeriesInput]) -> Self { with { $0.series = v } }
    /// The latest value for each series id (multi-series live feed). Each changed
    /// value is appended to its series, mirroring the single-series `value` path.
    public func seriesValues(_ v: [String: Double]) -> Self { with { $0.seriesValues = v } }
    /// Order-book depth (`{ bids, asks }`). Resting sizes float upward behind the
    /// price line — bids in the up-colour, asks in the down-colour — with a drift
    /// speed that reacts to price momentum. Pair with `value` for the price line.
    public func orderbook(_ v: OrderbookData?) -> Self { with { $0.orderbook = v } }
    /// Sets the chart type (`.line` or `.candle`).
    public func mode(_ v: LivelineMode) -> Self { with { $0.mode = v } }
    /// Shows a native line/candle toggle at the end of the interval bar (opt-in).
    /// The bar appears for the toggle even without `windows`. Pair with
    /// ``onModeChange(_:)`` and drive ``mode(_:)`` from it.
    public func modeToggle(_ v: Bool = true) -> Self { with { $0.modeToggle = v } }
    /// Called with the chosen mode when the toggle is tapped. Drive ``mode(_:)`` from it.
    public func onModeChange(_ f: @escaping (LivelineMode) -> Void) -> Self { with { $0.onModeChange = f } }
    /// Sets the OHLC candles (used when `mode == .candle`).
    public func candles(_ v: [LivelineCandle]) -> Self { with { $0.candles = v } }
    /// Sets the seconds per candle.
    public func candleWidth(_ v: Double) -> Self { with { $0.candleWidth = v } }
    /// Sets the current live candle.
    public func liveCandle(_ v: LivelineCandle?) -> Self { with { $0.liveCandle = v } }

    private func with(_ transform: (inout Self) -> Void) -> Self {
        var copy = self
        transform(&copy)
        return copy
    }

    // MARK: UIViewRepresentable bridge

    private struct Representable: UIViewRepresentable {
        var config: Liveline

        func makeCoordinator() -> Coordinator { Coordinator() }

        func makeUIView(context: Context) -> LegendChartContainer {
            let container = LegendChartContainer()
            apply(to: container, context: context, initial: true)
            return container
        }

        func updateUIView(_ container: LegendChartContainer, context: Context) {
            apply(to: container, context: context, initial: false)
        }

        private func apply(to container: LegendChartContainer, context: Context, initial: Bool) {
            let c = config
            let view = container.chart

            // Multi-series legend (chips) sits above the chart.
            if !c.series.isEmpty {
                let signature = c.series.map { "\($0.id)|\($0.label ?? "")" }.joined(separator: ",")
                if signature != context.coordinator.legendSignature {
                    context.coordinator.legendSignature = signature
                    container.legend.items = c.series.map {
                        .init(id: $0.id, color: $0.color, label: $0.label ?? $0.id)
                    }
                    container.legend.onToggle = { [weak view] id in view?.toggleSeries(id) }
                }
                let isDark = c.theme != .light
                if isDark != context.coordinator.legendIsDark {
                    context.coordinator.legendIsDark = isDark
                    container.legend.isDark = isDark
                }
                if container.legend.isHidden {
                    container.legend.isHidden = false
                    container.setNeedsLayout()
                }
            } else if !container.legend.isHidden {
                container.legend.isHidden = true
                container.setNeedsLayout()
            }
            view.color = UIColor(c.color)
            view.theme = c.theme
            view.surfaceColor = c.surfaceColor.map { UIColor($0) }
            view.paletteOverrides = c.paletteOverrides
            // Interval bar — the library's native WindowBarView, wired inside the
            // container to drive the chart's window (like the RN binding). The
            // window is set from config only when the window set first appears or
            // changes; after that the bar owns the selection, so SwiftUI re-applies
            // don't clobber the user's choice.
            context.coordinator.onModeChange = c.onModeChange
            if initial {
                container.windowBar.onModeSelect = { [weak view] candle in
                    view?.mode = candle ? .candle : .line
                    context.coordinator.onModeChange?(candle ? .candle : .line)
                }
            }
            container.windowBar.showModeToggle = c.modeToggle
            container.windowBar.isCandle = c.mode == .candle
            let barDark = c.theme != .light
            if container.windowBar.isDark != barDark { container.windowBar.isDark = barDark }
            container.windowBar.fontFamily = c.fontFamily
            if !c.windows.isEmpty {
                let signature = c.windows.map { "\($0.label)|\($0.secs)" }.joined(separator: ",")
                if signature != context.coordinator.windowSignature {
                    context.coordinator.windowSignature = signature
                    container.windowBar.windows = c.windows.map { ($0.label, $0.secs) }
                    let initial = c.windows.first?.secs ?? c.window
                    container.windowBar.activeSecs = initial
                    view.windowSeconds = initial
                }
                container.windowBar.style = WindowBarView.Style(c.windowStyle)
            } else {
                context.coordinator.windowSignature = nil
                view.windowSeconds = c.window
            }
            // The bar is shown when there are windows OR the mode toggle is on.
            let showBar = !c.windows.isEmpty || c.modeToggle
            if container.windowBar.isHidden == showBar {
                container.windowBar.isHidden = !showBar
                container.setNeedsLayout()
            }
            view.grid = c.grid
            view.badge = c.badge
            view.badgeTail = c.badgeTail
            view.badgeVariant = c.badgeVariant
            view.momentum = c.momentum
            view.fill = c.fill
            view.scrub = c.scrub
            view.pulse = c.pulse
            view.exaggerate = c.exaggerate
            view.paused = c.paused
            view.loading = c.loading
            view.emptyText = c.emptyText
            view.showValue = c.showValue
            view.valueMomentumColor = c.valueMomentumColor
            view.haptics = c.haptics
            view.degen = c.degen
            view.referenceLine = c.referenceLine
            view.lineWidth = c.lineWidth
            view.lerpSpeed = c.lerpSpeed
            if let f = c.formatValue { view.formatValue = f }
            if let f = c.formatTime { view.formatTime = f }
            view.formattingLocale = c.formattingLocale
            view.fontFamily = c.fontFamily

            view.setOrderbook(c.orderbook)

            view.mode = c.mode
            view.candleWidth = c.candleWidth
            if c.mode == .candle {
                view.candles = c.candles
                view.liveCandle = c.liveCandle
            }

            if initial {
                if !c.data.isEmpty { view.setData(c.data) }
                if !c.series.isEmpty { view.setSeries(c.series) }
            }
            if let value = c.value, value != context.coordinator.lastValue {
                context.coordinator.lastValue = value
                view.push(LivelinePoint(time: Date().timeIntervalSince1970, value: value))
            }
            // Multi-series live feed: push each changed per-series value.
            if !c.seriesValues.isEmpty {
                let now = Date().timeIntervalSince1970
                for (id, v) in c.seriesValues where context.coordinator.lastSeriesValues[id] != v {
                    context.coordinator.lastSeriesValues[id] = v
                    view.push(LivelinePoint(time: now, value: v), seriesId: id)
                }
            }
        }

        final class Coordinator {
            var lastValue: Double?
            var lastSeriesValues: [String: Double] = [:]
            var legendSignature: String?
            var legendIsDark: Bool?
            var windowSignature: String?
            var onModeChange: ((LivelineMode) -> Void)?
        }
    }

    /// Stacks the multi-series legend chips above the chart and the native
    /// interval bar below it — mirroring the React Native container. The legend
    /// and bar are hidden until series / windows are set, so a plain chart fills
    /// the whole view.
    final class LegendChartContainer: UIView {
        let legend = SeriesLegendView()
        let chart = LivelineView()
        let windowBar = WindowBarView()

        override init(frame: CGRect) {
            super.init(frame: frame)
            addSubview(chart)
            addSubview(legend)
            addSubview(windowBar)
            legend.isHidden = true
            windowBar.isHidden = true
            windowBar.onSelect = { [weak chart] secs in chart?.windowSeconds = secs }
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) { fatalError("init(coder:) not supported") }

        override func layoutSubviews() {
            super.layoutSubviews()
            let legendH = legend.isHidden ? 0 : legend.intrinsicContentSize.height
            let barH = windowBar.isHidden ? 0 : windowBar.intrinsicContentSize.height
            legend.frame = CGRect(x: 0, y: 0, width: bounds.width, height: legendH)
            windowBar.frame = CGRect(x: 0, y: bounds.height - barH, width: bounds.width, height: barH)
            chart.frame = CGRect(
                x: 0, y: legendH, width: bounds.width, height: bounds.height - legendH - barH)
        }
    }
}

// MARK: - Window style bridge

extension WindowBarView.Style {
    init(_ s: WindowStyle) {
        switch s {
        case .default: self = .default
        case .rounded: self = .rounded
        case .text: self = .text
        }
    }
}
#endif
