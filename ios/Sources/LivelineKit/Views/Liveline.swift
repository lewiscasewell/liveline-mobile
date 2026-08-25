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

    // Candle mode.
    private var mode: LivelineMode = .line
    private var candles: [LivelineCandle] = []
    private var candleWidth: Double = 1
    private var liveCandle: LivelineCandle?

    /// The window selected via the button bar (nil = the first window / `window`).
    @State private var activeWindow: Double?

    /// Creates a chart.
    /// - Parameters:
    ///   - data: Initial backfill series. Not re-sent on every value change.
    ///   - value: The latest live value; each distinct value is appended as a
    ///     new sample timestamped with the current time.
    public init(data: [LivelinePoint] = [], value: Double? = nil) {
        self.data = data
        self.value = value
    }

    /// The effective visible span: the selected window button, else the first
    /// window, else the `window` value.
    private var effectiveWindow: Double {
        activeWindow ?? windows.first?.secs ?? window
    }

    /// The chart, with an optional time-window button bar above it.
    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !windows.isEmpty {
                WindowBar(
                    windows: windows, style: windowStyle, active: effectiveWindow
                ) { activeWindow = $0 }
            }
            Representable(config: self, window: effectiveWindow)
        }
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
    /// Sets the chart type (`.line` or `.candle`).
    public func mode(_ v: LivelineMode) -> Self { with { $0.mode = v } }
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
        var window: Double

        func makeCoordinator() -> Coordinator { Coordinator() }

        func makeUIView(context: Context) -> LivelineView {
            let view = LivelineView()
            apply(to: view, context: context, initial: true)
            return view
        }

        func updateUIView(_ view: LivelineView, context: Context) {
            apply(to: view, context: context, initial: false)
        }

        private func apply(to view: LivelineView, context: Context, initial: Bool) {
            let c = config
            view.color = UIColor(c.color)
            view.theme = c.theme
            view.surfaceColor = c.surfaceColor.map { UIColor($0) }
            view.paletteOverrides = c.paletteOverrides
            view.windowSeconds = window
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

            view.mode = c.mode
            view.candleWidth = c.candleWidth
            if c.mode == .candle {
                view.candles = c.candles
                view.liveCandle = c.liveCandle
            }

            if initial, !c.data.isEmpty {
                view.setData(c.data)
            }
            if let value = c.value, value != context.coordinator.lastValue {
                context.coordinator.lastValue = value
                view.push(LivelinePoint(time: Date().timeIntervalSince1970, value: value))
            }
        }

        final class Coordinator {
            var lastValue: Double?
        }
    }
}

// MARK: - Window button bar

@MainActor
private struct WindowBar: View {
    let windows: [Window]
    let style: WindowStyle
    let active: Double
    let onSelect: (Double) -> Void

    // The bar is chrome outside the chart, so it follows the app's appearance
    // rather than the chart's own theme.
    @Environment(\.colorScheme) private var colorScheme
    private var dark: Bool { colorScheme == .dark }

    private func gray(_ alpha: Double) -> Color { (dark ? Color.white : Color.black).opacity(alpha) }
    private var activeColor: Color { gray(WindowBarTokens.activeAlpha(isDark: dark)) }
    private var inactiveColor: Color { gray(WindowBarTokens.inactiveAlpha(isDark: dark)) }
    private var trackColor: Color {
        style == .text ? .clear : gray(WindowBarTokens.trackAlpha(isDark: dark))
    }
    private var indicatorColor: Color { gray(WindowBarTokens.indicatorAlpha(isDark: dark)) }
    private var corner: CGFloat { style == .rounded ? 999 : 6 }
    private var innerCorner: CGFloat { style == .rounded ? 999 : 4 }

    var body: some View {
        HStack(spacing: style == .text ? 4 : 2) {
            ForEach(windows) { w in
                let isActive = w.secs == active
                Button {
                    onSelect(w.secs)
                } label: {
                    Text(w.label)
                        .font(.system(size: WindowBarTokens.fontSize, weight: isActive ? .semibold : .regular))
                        .foregroundColor(isActive ? activeColor : inactiveColor)
                        .padding(.horizontal, style == .text ? 6 : 10)
                        .padding(.vertical, style == .text ? 2 : 3)
                        .background(
                            RoundedRectangle(cornerRadius: innerCorner)
                                .fill(isActive && style != .text ? indicatorColor : .clear)
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(style == .text ? 0 : (style == .rounded ? 3 : 2))
        .background(RoundedRectangle(cornerRadius: corner).fill(trackColor))
    }
}
#endif
