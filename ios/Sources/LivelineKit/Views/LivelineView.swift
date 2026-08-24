#if canImport(UIKit)
import CoreGraphics
import QuartzCore
import UIKit

/// The real, imperative chart view — a faithful port of web liveline's line
/// mode. Owns the ring buffer, the `CADisplayLink` frame loop, all easing
/// state, the Core Graphics rendering, and a pan recogniser for scrubbing.
///
/// This is the object the React Native binding holds directly:
///
/// ```swift
/// let chart = LivelineView()
/// chart.color = .systemBlue
/// chart.push(LivelinePoint(time: t, value: v))
/// ```
///
/// The render pipeline matches the reference library's draw order:
/// reference line → grid → line + fill + dashed baseline → time axis →
/// live dot (+ pulse) → momentum arrows → left-edge fade → crosshair → badge.
///
/// - Note: Phase 1 is **line mode only**. Candles, multi-series, orderbook and
///   degen mode come later.
@MainActor
public final class LivelineView: UIView {
    // MARK: Public configuration (names mirror web liveline props)

    /// Accent colour. Derives the full palette. Default `#3b82f6`.
    public var color: UIColor = LivelineView.defaultAccent { didSet { rebuildPalette() } }
    /// Base theme. Default `.dark`. Sets the *tone* of grid, labels, text and
    /// crosshair (light-on-dark vs dark-on-light). The surface colour is
    /// separate — see ``surfaceColor``.
    public var theme: LivelineTheme = .dark { didSet { rebuildPalette() } }

    /// Overrides the chart surface (background) colour, independent of `theme`.
    /// `nil` uses the theme default; a clear colour lets the container show
    /// through (as the web library does). Pick a `theme` that matches the
    /// surface brightness so grid/text stay legible.
    public var surfaceColor: UIColor? { didSet { rebuildPalette() } }

    /// Escape hatch to override any derived palette colours (grid, labels,
    /// dash, momentum tints, …). Receives the theme-derived ``Palette`` to
    /// mutate. Applied after ``surfaceColor``. `nil` = no change.
    public var paletteOverrides: ((inout Palette) -> Void)? { didSet { rebuildPalette() } }
    /// Visible span in seconds. Default 30. (Named `windowSeconds` because
    /// `UIView` already defines `window`; the SwiftUI wrapper exposes it as
    /// `.window(_:)` to match the web prop name.)
    public var windowSeconds: Double = 30 { didSet { windowSeconds = max(0.001, windowSeconds) } }
    /// Draw the value grid + labels. Default `true`.
    public var grid: Bool = true
    /// Draw the endpoint value badge. Default `true`.
    public var badge: Bool = true
    /// Draw the badge's pointed tail. Default `true`.
    public var badgeTail: Bool = true
    /// Badge visual style. Default `.default`.
    public var badgeVariant: BadgeVariant = .default
    /// Momentum behaviour. Default `.auto`.
    public var momentum: Momentum = .auto
    /// Fill the area under the line. Default `true`.
    public var fill: Bool = true
    /// Enable crosshair scrubbing. Default `true`.
    public var scrub: Bool = true
    /// Pulsing ring on the live dot. Default `true`.
    public var pulse: Bool = true
    /// Tighten the Y range so small moves fill the height. Default `false`.
    public var exaggerate: Bool = false
    /// Freeze scrolling while data keeps arriving; catches up on resume.
    public var paused: Bool = false
    /// Show the breathing loading animation. Default `false`.
    public var loading: Bool = false
    /// Message shown in the empty state.
    public var emptyText: String = "No data to display"
    /// Optional horizontal reference line.
    public var referenceLine: ReferenceLine? { didSet { setNeedsDisplay() } }
    /// Stroke width in points. Default 2.
    public var lineWidth: CGFloat = 2
    /// Value formatter for the badge, grid labels and crosshair.
    public var formatValue: (Double) -> String = LivelineView.defaultFormatValue
    /// Time formatter for the time axis and crosshair. When `nil` (the default),
    /// labels auto-format by scale — years, months, days or times — so the same
    /// chart reads sensibly from a 30-second window out to a 4-year one. Set a
    /// closure to take full control.
    public var formatTime: ((Double) -> String)?
    /// Base easing speed per 60 fps frame. Default 0.08.
    public var lerpSpeed: Double = 0.08
    /// Show the live value as a large text overlay above the chart, updated
    /// every frame. Default `false`.
    public var showValue: Bool = false { didSet { valueLabel.isHidden = !showValue } }
    /// Tint the ``showValue`` overlay by momentum (green up / red down).
    public var valueMomentumColor: Bool = false

    /// Named time windows. The first entry sets the visible span.
    public var windows: [Window] = [] {
        didSet {
            if let first = windows.first { windowSeconds = first.secs }
        }
    }

    // MARK: Candle mode

    /// Chart type. Default `.line`. Switching crossfades between line and
    /// candle rendering while the shared Y-range eases between the two extents.
    public var mode: LivelineMode = .line {
        didSet {
            if oldValue != mode {
                let transition = CATransition()
                transition.type = .fade
                transition.duration = 0.4
                transition.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                layer.add(transition, forKey: "modeChange")
            }
            setNeedsDisplay()
        }
    }
    /// OHLC candles (required when `mode == .candle`).
    public var candles: [LivelineCandle] = []
    /// Seconds per candle (required when `mode == .candle`).
    public var candleWidth: Double = 1
    /// The current live candle with real-time OHLC, if any.
    public var liveCandle: LivelineCandle?

    // MARK: Data

    private var buffer: RingBuffer<LivelinePoint>
    private static let defaultCapacity = 8192

    // MARK: Easing state (persist across frames)

    private var displayValue: Double = 0
    private var displayValueInited = false
    var domain = Domain()

    var badgeY: CGFloat = 0
    var badgeYInited = false
    var badgeGreen: Double = 1  // 0 = red (down), 1 = green (up)
    var badgeDisplayW: CGFloat = 0

    // Candle live-OHLC easing state.
    var displayCandle: LivelineCandle?
    var liveBull: Double = 0.5  // 0 = bear (red), 1 = bull (green)

    var arrowUp: Double = 0
    var arrowDown: Double = 0

    var gridInterval: Double = 0
    var gridAlphas: [Int: Double] = [:]  // key = round(val*1000)
    var timeAlphas: [Int: (alpha: Double, text: String)] = [:]  // key = round(t*100)

    var scrubAmount: Double = 0
    private var lastHover: (x: CGFloat, value: Double, time: Double)?

    // Smooth window (interval) transition.
    var displayWindow: Double = 30
    private var windowTransFrom: Double = 30
    private var windowTransTo: Double = 30
    private var windowTransStartMs: Double = 0
    private var windowInited = false

    private var pauseProgress: Double = 0
    private var timeDebt: Double = 0
    private var loadingAlpha: Double = 0
    var chartReveal: Double = 0

    // MARK: Frame clock

    private var displayLink: CADisplayLink?
    private var lastFrameMs: Double = 0
    private var scrubRecognizer: UILongPressGestureRecognizer?

    // MARK: Scrub input

    var isHovering = false
    var hoverX: CGFloat?

    // MARK: showValue overlay

    private lazy var valueLabel: UILabel = {
        let label = UILabel()
        label.font = .monospacedSystemFont(ofSize: 20, weight: .medium)
        label.isHidden = true
        return label
    }()

    // MARK: Derived

    var palette: Palette

    // MARK: Constants (from the reference engine)

    enum K {
        static let maxDeltaMs = 50.0
        static let scrubLerp = 0.12
        static let badgeWidthLerp = 0.15
        static let badgeYLerp = 0.35
        static let momentumColorLerp = 0.12
        static let windowBuffer = 0.05
        static let windowBufferNoBadge = 0.015
        static let chartRevealSpeed = 0.14
        static let chartRevealSpeedFwd = 0.09
        static let pauseProgressSpeed = 0.12
        static let pauseCatchup = 0.08
        static let pauseCatchupFast = 0.22
        static let loadingAlphaSpeed = 0.14
        static let fadeEdgeWidth: CGFloat = 40
        static let crosshairFadeMinPx: CGFloat = 5
        static let gridMinGap = 36.0
        static let gridFadeIn = 0.18
        static let gridFadeOut = 0.12
        static let timeFade = 0.08
        // Badge geometry
        static let badgePadX: CGFloat = 10
        static let badgePadY: CGFloat = 3
        static let badgeTailLen: CGFloat = 5
        static let badgeTailSpread: CGFloat = 2.5
        static let badgeLineH: CGFloat = 16
        // Dot
        static let pulseInterval = 1500.0
        static let pulseDuration = 900.0
        // Loading squiggle
        static let loadingAmplitudeRatio = 0.07
        static let loadingScrollSpeed = 0.001
    }

    private static let defaultAccent = UIColor(red: 59 / 255, green: 130 / 255, blue: 246 / 255, alpha: 1)
    static let momentumGreenComponents = (34.0, 197.0, 94.0)
    static let momentumRedComponents = (239.0, 68.0, 68.0)

    /// Default value formatter — two decimal places, matching web liveline.
    public static func defaultFormatValue(_ v: Double) -> String { String(format: "%.2f", v) }

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f
    }()

    /// Default time formatter — `HH:mm:ss` in the local time zone.
    public static func defaultFormatTime(_ t: Double) -> String {
        timeFormatter.string(from: Date(timeIntervalSince1970: t))
    }

    /// Reusable `DateFormatter`s keyed by format string, so auto-formatting the
    /// axis every frame never allocates. Main-thread only (the render loop).
    private var timeFormatterCache: [String: DateFormatter] = [:]

    private func timeFormatter(_ format: String) -> DateFormatter {
        if let f = timeFormatterCache[format] { return f }
        let f = DateFormatter()
        f.dateFormat = format
        timeFormatterCache[format] = f
        return f
    }

    /// Axis label for a tick at time `t` (seconds). Uses `formatTime` when set,
    /// otherwise picks a format from the tick `interval`: year ticks show the
    /// year, month ticks the month, day ticks the date, finer ticks the time.
    func axisTimeLabel(_ t: Double, interval: Double) -> String {
        if let formatTime { return formatTime(t) }
        let format: String
        if interval >= 31_536_000 { format = "yyyy" }        // ≥ 1 year
        else if interval >= 2_592_000 { format = "MMM yyyy" }  // ≥ 1 month
        else if interval >= 86_400 { format = "d MMM" }        // ≥ 1 day
        else if interval >= 60 { format = "HH:mm" }            // ≥ 1 minute
        else { format = "HH:mm:ss" }
        return timeFormatter(format).string(from: Date(timeIntervalSince1970: t))
    }

    /// Crosshair label for a precise time `t`, scaled to the visible window so a
    /// year-wide view shows a full date while a live view shows seconds.
    func crosshairTimeLabel(_ t: Double) -> String {
        if let formatTime { return formatTime(t) }
        let w = windowSeconds
        let format: String
        if w >= 63_072_000 { format = "d MMM yyyy" }   // ≥ 2 years
        else if w >= 2_592_000 { format = "d MMM" }    // ≥ 1 month
        else if w >= 86_400 { format = "d MMM, HH:mm" } // ≥ 1 day
        else if w >= 3_600 { format = "HH:mm" }        // ≥ 1 hour
        else { format = "HH:mm:ss" }
        return timeFormatter(format).string(from: Date(timeIntervalSince1970: t))
    }

    // MARK: Init

    /// Creates a chart view with the given frame.
    public override init(frame: CGRect) {
        self.buffer = RingBuffer<LivelinePoint>(capacity: LivelineView.defaultCapacity)
        self.palette = Theme.palette(accent: LivelineView.defaultAccent.rgba, theme: .dark)
        super.init(frame: frame)
        commonInit()
    }

    /// Creates a chart view from a coder.
    public required init?(coder: NSCoder) {
        self.buffer = RingBuffer<LivelinePoint>(capacity: LivelineView.defaultCapacity)
        self.palette = Theme.palette(accent: LivelineView.defaultAccent.rgba, theme: .dark)
        super.init(coder: coder)
        commonInit()
    }

    private func commonInit() {
        contentMode = .redraw
        isOpaque = false
        backgroundColor = .clear
        rebuildPalette()
        addSubview(valueLabel)
        // A zero-duration long press fires on touch-down (so press-and-hold
        // shows the crosshair immediately and keeps it while the finger is
        // held still) and tracks movement for scrubbing — unlike a pan, which
        // only begins once the finger drags.
        let press = UILongPressGestureRecognizer(target: self, action: #selector(handleScrub(_:)))
        press.minimumPressDuration = 0
        press.cancelsTouchesInView = false
        press.delegate = self
        addGestureRecognizer(press)
        scrubRecognizer = press
    }

    deinit { displayLink?.invalidate() }

    // MARK: Lifecycle

    public override func didMoveToWindow() {
        super.didMoveToWindow()
        if window == nil { stopLink() } else { startLink() }
    }

    private func startLink() {
        guard displayLink == nil else { return }
        let link = CADisplayLink(target: self, selector: #selector(tick))
        link.add(to: .main, forMode: .common)
        displayLink = link
    }

    private func stopLink() {
        displayLink?.invalidate()
        displayLink = nil
        lastFrameMs = 0
    }

    @objc private func tick() { setNeedsDisplay() }

    // MARK: Data input

    /// Backfills the buffer with a series, replacing current data.
    /// Live updates must use ``push(_:)``.
    ///
    /// When the chart already had data (e.g. switching time window / resolution),
    /// the value domain is NOT reset — it eases to the new range each frame, so
    /// the line morphs into the new data instead of snapping. Only the first
    /// load (from empty) snaps the domain to initialise it.
    public func setData(_ points: [LivelinePoint]) {
        let wasEmpty = buffer.count == 0
        buffer.removeAll()
        for p in points { buffer.push(p) }
        if wasEmpty, let last = points.last {
            displayValue = last.value
            displayValueInited = true
            domain.reset()
        }
        setNeedsDisplay()
    }

    /// Appends a single live sample. Call once per tick, never per frame.
    public func push(_ point: LivelinePoint) {
        buffer.push(point)
        if !displayValueInited {
            displayValue = point.value
            displayValueInited = true
        }
        setNeedsDisplay()
    }

    /// Moves the live "head" — replaces the most recent sample in place instead
    /// of appending. Use this to update the current bucket at a wide interval's
    /// resolution: the head keeps moving live every frame while the committed
    /// points behind it stay put (like a candle's forming bar). Falls back to
    /// ``push(_:)`` when the buffer is empty.
    public func updateHead(_ point: LivelinePoint) {
        guard buffer.count > 0 else { push(point); return }
        buffer.replaceLast(point)
        if !displayValueInited {
            displayValue = point.value
            displayValueInited = true
        }
        setNeedsDisplay()
    }

    /// The most recently pushed value, or 0.
    public var currentValue: Double { buffer.last?.value ?? 0 }

    // MARK: Palette

    private func rebuildPalette() {
        var p = Theme.palette(accent: color.rgba, theme: theme)
        p.lineWidth = Double(lineWidth)
        // Overrides win over the theme-derived defaults. `theme` still sets the
        // tone of grid/labels/text; these only change specific surfaces.
        if let surfaceColor { p.background = surfaceColor.rgba }
        if let overrides = paletteOverrides { overrides(&p) }
        palette = p
        setNeedsDisplay()
    }

    // MARK: Layout

    struct Layout {
        var w: CGFloat
        var h: CGFloat
        var padTop: CGFloat
        var padRight: CGFloat
        var padBottom: CGFloat
        var padLeft: CGFloat
        var chartW: CGFloat
        var chartH: CGFloat
        var leftEdge: Double
        var rightEdge: Double
        var minVal: Double
        var maxVal: Double
        var valRange: Double

        func toX(_ t: Double) -> CGFloat {
            padLeft + CGFloat((t - leftEdge) / (rightEdge - leftEdge)) * chartW
        }
        func toY(_ v: Double) -> CGFloat {
            padTop + CGFloat((maxVal - v) / valRange) * chartH
        }
    }

    private func padding() -> (top: CGFloat, right: CGFloat, bottom: CGFloat, left: CGFloat) {
        let right: CGFloat = badge ? 80 : (grid ? 54 : 12)
        return (12, right, 28, 12)
    }

    /// Eases the displayed window (span) toward the target `windowSeconds` with a
    /// 750 ms log-interpolated, cosine-eased transition — so switching time
    /// windows zooms smoothly instead of snapping.
    private func advanceWindow(nowMs: Double) {
        if !windowInited {
            displayWindow = windowSeconds
            windowTransTo = windowSeconds
            windowInited = true
            return
        }
        if windowTransTo != windowSeconds {
            windowTransFrom = displayWindow
            windowTransTo = windowSeconds
            windowTransStartMs = nowMs
        }
        if windowTransStartMs == 0 {
            displayWindow = windowSeconds
        } else {
            let t = min((nowMs - windowTransStartMs) / 750, 1)
            let eased = (1 - cos(t * .pi)) / 2
            displayWindow = exp(log(windowTransFrom) + (log(windowTransTo) - log(windowTransFrom)) * eased)
            if t >= 1 {
                displayWindow = windowSeconds
                windowTransStartMs = 0
            }
        }
    }

    // MARK: Frame update + draw

    public override func draw(_ rect: CGRect) {
        guard let ctx = UIGraphicsGetCurrentContext() else { return }
        let w = bounds.width
        let h = bounds.height
        guard w > 0, h > 0 else { return }

        // Background
        ctx.setFillColor(UIColor(rgba: palette.background).cgColor)
        ctx.fill(bounds)

        // Delta time (ms), frame-rate independent.
        let nowMs = CACurrentMediaTime() * 1000
        let dt = lastFrameMs == 0 ? Clock.frameMs : min(nowMs - lastFrameMs, K.maxDeltaMs)
        lastFrameMs = nowMs

        let pad = padding()
        let chartH = h - pad.top - pad.bottom

        advanceWindow(nowMs: nowMs)

        // Pause progress + time debt.
        let pauseTarget = paused ? 1.0 : 0.0
        pauseProgress = Clock.lerp(
            current: pauseProgress, target: pauseTarget, speed: K.pauseProgressSpeed, dt: dt)
        if pauseProgress < 0.005 { pauseProgress = 0 }
        if pauseProgress > 0.995 { pauseProgress = 1 }
        let pausedDt = dt * (1 - pauseProgress)
        timeDebt += (dt / 1000) * pauseProgress
        if !paused, timeDebt > 0.001 {
            let speed = timeDebt > 10 ? K.pauseCatchupFast : K.pauseCatchup
            timeDebt = Clock.lerp(current: timeDebt, target: 0, speed: speed, dt: dt)
            if timeDebt < 0.01 { timeDebt = 0 }
        }

        let isCandle = mode == .candle
        let hasData = isCandle ? (!candles.isEmpty || liveCandle != nil) : buffer.count >= 2

        // Loading + reveal crossfades.
        let loadingTarget = loading ? 1.0 : 0.0
        loadingAlpha = Clock.lerp(
            current: loadingAlpha, target: loadingTarget, speed: K.loadingAlphaSpeed, dt: dt)
        loadingAlpha = min(max(loadingAlpha, 0), 1)

        let revealTarget = (!loading && hasData) ? 1.0 : 0.0
        chartReveal = Clock.lerp(
            current: chartReveal, target: revealTarget,
            speed: revealTarget == 1 ? K.chartRevealSpeedFwd : K.chartRevealSpeed, dt: dt
        )
        if abs(chartReveal - revealTarget) < 0.005 { chartReveal = revealTarget }
        if chartReveal < 0.01 { domain.reset() }

        // now in data-time, anchored to real time, minus pause debt.
        let now = Date().timeIntervalSince1970 - timeDebt

        if !hasData {
            if loadingAlpha > 0.01 {
                drawLoading(ctx, w: w, h: h, pad: pad, nowMs: nowMs, alpha: loadingAlpha)
            }
            if (1 - loadingAlpha) > 0.01 { drawEmpty(ctx, w: w, h: h, pad: pad, alpha: 1 - loadingAlpha) }
            drawLeftEdgeFade(ctx, w: w, h: h, padLeft: pad.left)
            updateValueLabel(value: displayValue, trend: .flat, pad: pad)
            return
        }

        if isCandle {
            valueLabel.isHidden = true
            drawCandleFrame(ctx, w: w, h: h, pad: pad, now: now, dt: dt, pausedDt: pausedDt, nowMs: nowMs)
            return
        }

        // Smoothed value (adaptive speed).
        let value = currentValue
        let adaptiveSpeed = Domain.adaptiveSpeed(
            value: value, displayValue: displayValue,
            displayMin: domain.minVal, displayMax: domain.maxVal, base: lerpSpeed
        )
        displayValue = Clock.lerp(current: displayValue, target: value, speed: adaptiveSpeed, dt: pausedDt)
        if abs(displayValue - value) < domain.valRange * 0.001 { displayValue = value }
        let smoothValue = displayValue

        // Window edges.
        let winBuffer = badge ? K.windowBuffer : K.windowBufferNoBadge
        let rightEdge = now + displayWindow * winBuffer
        let leftEdge = rightEdge - displayWindow

        // Visible points (one before the left edge for a clean entry).
        var visible = [LivelinePoint]()
        visible.reserveCapacity(buffer.count)
        var startIdx = 0
        for i in 0..<buffer.count where buffer[i].time >= leftEdge {
            startIdx = max(0, i - 1)
            break
        }
        // Cap at `now` (not `rightEdge`, which sits ahead for the badge gap) so
        // that when paused — `now` frozen while points keep arriving — the newer
        // points stay out of view and the line truly freezes.
        for i in startIdx..<buffer.count where buffer[i].time <= now {
            visible.append(buffer[i])
        }
        guard visible.count >= 2 else {
            updateValueLabel(value: smoothValue, trend: .flat, pad: pad)
            return
        }

        // Range easing.
        var values = [Double]()
        values.reserveCapacity(visible.count)
        for p in visible { values.append(p.value) }
        let target = AutoRange.compute(
            values: values, currentValue: smoothValue,
            referenceValue: referenceLine?.value, exaggerate: exaggerate
        )
        domain.update(target: target, speed: adaptiveSpeed, dt: dt, chartH: Double(chartH))

        let layout = Layout(
            w: w, h: h, padTop: pad.top, padRight: pad.right, padBottom: pad.bottom, padLeft: pad.left,
            chartW: w - pad.left - pad.right, chartH: chartH,
            leftEdge: leftEdge, rightEdge: rightEdge,
            minVal: domain.minVal, maxVal: domain.maxVal, valRange: domain.valRange
        )

        // Momentum.
        let trend = resolveTrend()
        let showMomentum = momentum != .off

        let reveal = chartReveal
        func revealRamp(_ start: Double, _ end: Double) -> Double {
            let t = min(max((reveal - start) / (end - start), 0), 1)
            return t * t * (3 - 2 * t)
        }

        // 1. Reference line.
        if let ref = referenceLine, reveal > 0.01 {
            ctx.saveGState()
            ctx.setAlpha(CGFloat(min(reveal, 1)))
            drawReferenceLine(ctx, layout: layout, ref: ref)
            ctx.restoreGState()
        }

        // 2. Grid.
        if grid {
            let a = reveal < 1 ? revealRamp(0.15, 0.7) : 1
            if a > 0.01 { drawGrid(ctx, layout: layout, dt: dt, groupAlpha: a) }
        }

        // 3. Line + fill + dashed baseline.
        let scrubX: CGFloat? = scrubAmount > 0.05 ? hoverX : nil
        let dotPoint = drawLineFillDash(
            ctx, layout: layout, visible: visible, smoothValue: smoothValue,
            now: now, scrubX: scrubX, reveal: reveal, nowMs: nowMs
        )

        // 4. Time axis.
        do {
            let a = reveal < 1 ? revealRamp(0.15, 0.7) : 1
            if a > 0.01 { drawTimeAxis(ctx, layout: layout, dt: dt, groupAlpha: a) }
        }

        // 5. Live dot + pulse.
        let dotAlpha = reveal < 0.3 ? 0 : (reveal - 0.3) / 0.7
        var dotScrub = scrubAmount
        if let hx = hoverX, scrubAmount > 0 {
            let dist = dotPoint.x - hx
            let fadeStart = min(80, layout.chartW * 0.3)
            dotScrub =
                dist < K.crosshairFadeMinPx
                ? 0
                : dist >= fadeStart
                    ? scrubAmount
                    : Double((dist - K.crosshairFadeMinPx) / (fadeStart - K.crosshairFadeMinPx)) * scrubAmount
        }
        if dotAlpha > 0.01 {
            ctx.saveGState()
            ctx.setAlpha(CGFloat(dotAlpha))
            let showPulse = pulse && reveal > 0.6 && pauseProgress < 0.5
            drawDot(ctx, at: dotPoint, showPulse: showPulse, scrubDim: dotScrub, nowMs: nowMs)
            ctx.restoreGState()
        }

        // 5b. Momentum arrows.
        if showMomentum, let trend {
            let arrowReveal = reveal < 1 ? revealRamp(0.6, 1) : 1
            let arrowAlpha = arrowReveal * (1 - pauseProgress)
            if arrowAlpha > 0.01 {
                ctx.saveGState()
                ctx.setAlpha(CGFloat(arrowAlpha))
                drawArrows(ctx, at: dotPoint, trend: trend, dt: dt, nowMs: nowMs)
                ctx.restoreGState()
            }
        }

        // 6. Left-edge fade.
        drawLeftEdgeFade(ctx, w: w, h: h, padLeft: pad.left)

        // 7. Crosshair.
        if let hx = hoverX, let hover = lastHover, scrubAmount > 0.01 {
            let dist = dotPoint.x - hx
            let fadeStart = min(80, layout.chartW * 0.3)
            let opacity =
                dist < K.crosshairFadeMinPx
                ? 0
                : dist >= fadeStart
                    ? scrubAmount
                    : Double((dist - K.crosshairFadeMinPx) / (fadeStart - K.crosshairFadeMinPx)) * scrubAmount
            if opacity > 0.01 {
                drawCrosshair(ctx, layout: layout, hover: hover, opacity: opacity, liveDotX: dotPoint.x)
            }
        }

        // 8. Badge.
        if badge, reveal >= 0.25 {
            updateBadge(
                smoothValue: smoothValue, layout: layout, trend: trend, showMomentum: showMomentum, dt: dt)
            drawBadge(ctx, smoothValue: smoothValue, layout: layout, reveal: reveal)
        }

        // Scrub amount easing (after using it, for next frame).
        let scrubTarget = isHovering ? 1.0 : 0.0
        scrubAmount += (scrubTarget - scrubAmount) * K.scrubLerp
        if scrubAmount < 0.01 { scrubAmount = 0 }
        if scrubAmount > 0.99 { scrubAmount = 1 }

        updateValueLabel(value: smoothValue, trend: trend ?? .flat, pad: pad)
    }

    // MARK: showValue overlay

    private func updateValueLabel(
        value: Double, trend: Trend, pad: (top: CGFloat, right: CGFloat, bottom: CGFloat, left: CGFloat)
    ) {
        guard showValue else {
            if !valueLabel.isHidden { valueLabel.isHidden = true }
            return
        }
        valueLabel.isHidden = false
        valueLabel.text = formatValue(value)
        let color: RGBA
        if valueMomentumColor, trend != .flat {
            color = trend == .up ? Theme.up : Theme.down
        } else {
            color = palette.tooltipText
        }
        valueLabel.textColor = UIColor(rgba: color)
        valueLabel.sizeToFit()
        // Sit just past the left-edge fade zone so the digits stay readable.
        valueLabel.frame.origin = CGPoint(x: pad.left + K.fadeEdgeWidth, y: pad.top)
    }

    // MARK: Momentum resolution

    private func resolveTrend() -> Trend? {
        switch momentum {
        case .off: return nil
        case .up: return .up
        case .down: return .down
        case .flat: return .flat
        case .auto: return detectTrend()
        }
    }

    private func detectTrend() -> Trend {
        let n = buffer.count
        guard n >= 5 else { return .flat }
        let lookback = min(n, 20)
        var slice = [LivelinePoint]()
        slice.reserveCapacity(lookback)
        for i in (n - lookback)..<n { slice.append(buffer[i]) }
        return MomentumDetect.detect(slice, lookback: lookback)
    }

    // MARK: Scrub gesture

    @objc private func handleScrub(_ gesture: UILongPressGestureRecognizer) {
        guard scrub else { return }
        switch gesture.state {
        case .began, .changed:
            isHovering = true
            hoverX = min(max(gesture.location(in: self).x, 0), bounds.width)
            updateHover()
            setNeedsDisplay()
        case .ended, .cancelled, .failed:
            isHovering = false
        default:
            break
        }
    }

    private func updateHover() {
        guard let hx = hoverX else { return }
        let pad = padding()
        let w = bounds.width
        guard hx >= pad.left, hx <= w - pad.right else { return }
        let now = Date().timeIntervalSince1970 - timeDebt
        let winBuffer = badge ? K.windowBuffer : K.windowBufferNoBadge
        let rightEdge = now + displayWindow * winBuffer
        let leftEdge = rightEdge - displayWindow
        let maxX = pad.left + CGFloat((now - leftEdge) / (rightEdge - leftEdge)) * (w - pad.left - pad.right)
        let clampedX = min(hx, maxX)
        let t = leftEdge + Double((clampedX - pad.left) / (w - pad.left - pad.right)) * (rightEdge - leftEdge)
        if let v = Interpolate.atTime(buffer.elements, time: t) {
            lastHover = (clampedX, v, t)
        }
    }
}

extension LivelineView: UIGestureRecognizerDelegate {
    /// Allow the scrub press to recognise alongside an enclosing scroll view's
    /// pan, so touching the chart shows the crosshair without disabling scroll.
    public func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer
    ) -> Bool {
        true
    }
}
#endif
