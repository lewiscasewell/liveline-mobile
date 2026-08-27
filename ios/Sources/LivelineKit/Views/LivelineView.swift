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
    /// Base theme. Default `.dark`. Sets the *tone* of the line, grid, labels,
    /// text and crosshair (light-on-dark vs dark-on-light). It does **not** paint
    /// a background — the chart is transparent unless you set ``surfaceColor`` —
    /// so pick a `theme` that matches whatever background sits behind the chart.
    public var theme: LivelineTheme = .dark { didSet { rebuildPalette() } }

    /// Opaque background fill for the chart. When `nil` (the default) the canvas
    /// is transparent and the container behind it shows through — matching web
    /// liveline, where the surrounding element supplies the background. Set an
    /// opaque colour to make the chart a self-contained card instead; `theme`
    /// still controls the tone independently.
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
    /// Locale used by the built-in time axis/crosshair formatting (field order,
    /// month names, 12/24-hour). Default `.current`. Ignored when ``formatTime``
    /// is set. (Value formatting is controlled via ``formatValue``.)
    public var formattingLocale: Locale = .current {
        didSet {
            guard formattingLocale != oldValue else { return }
            timeFormatterCache.removeAll()
            setNeedsDisplay()
        }
    }
    /// Font family for all chart text. `nil`/empty uses the system monospaced
    /// font. The family must be registered by the host app (bundled + Info.plist,
    /// or `expo-font`); an unknown family falls back to the system font. Numeric
    /// labels always get monospaced digits so ticking values stay tabular.
    public var fontFamily: String? {
        didSet {
            guard fontFamily != oldValue else { return }
            valueLabel.font = tickerFont()
            setNeedsDisplay()
        }
    }
    /// Base easing speed per 60 fps frame. Default 0.08.
    public var lerpSpeed: Double = 0.08
    /// Vertical offset (points) of the crosshair tooltip text. Default 14.
    public var tooltipY: Double = 14
    /// Stroke an outline behind the crosshair tooltip text. Default `true`.
    public var tooltipOutline: Bool = true
    /// Per-side chart-inset overrides (points); `nil` keeps the default.
    public var padTopOverride: Double?
    public var padRightOverride: Double?
    public var padBottomOverride: Double?
    public var padLeftOverride: Double?
    /// Show the live value as a large text overlay above the chart, updated
    /// every frame. Default `false`.
    public var showValue: Bool = false { didSet { valueLabel.isHidden = !showValue } }
    /// Tint the ``showValue`` overlay by momentum (green up / red down).
    public var valueMomentumColor: Bool = false
    /// Emit haptic feedback: a light tap as the crosshair moves between samples
    /// while scrubbing, and a stronger hit on each degen burst. Default `false`.
    public var haptics: Bool = true
    /// Degen mode: on a strong upward move the chart shakes and sparks burst from
    /// the live dot (with a haptic hit when ``haptics`` is on). Default `false`.
    public var degen: Bool = false { didSet { if !degen { degenParticles.removeAll(); degenShake = 0 } } }

    /// Named time windows. The first entry sets the visible span.
    public var windows: [Window] = [] {
        didSet {
            if let first = windows.first { windowSeconds = first.secs }
        }
    }

    // MARK: Candle mode

    /// Chart type. Default `.line`. Switching crossfades between line and
    /// candle rendering while the shared Y-range eases between the two extents.
    public var mode: LivelineMode = .line { didSet { setNeedsDisplay() } }
    /// Eased line↔candle morph: 0 = line, 1 = candle. The line fades out as the
    /// candles grow into their height.
    private var modeProgress: Double = 0
    /// OHLC candles (required when `mode == .candle`).
    public var candles: [LivelineCandle] = []
    /// Seconds per candle (required when `mode == .candle`).
    public var candleWidth: Double = 1 {
        didSet {
            // A new candle scale (e.g. interval switch) invalidates the ticks
            // aggregated at the old width.
            if oldValue != candleWidth {
                liveCandles.removeAll()
                liveCandle = nil
            }
        }
    }
    /// The current live candle with real-time OHLC, if any.
    public var liveCandle: LivelineCandle?
    /// Candles aggregated from live `push()` ticks — the forming candle rolls into
    /// here once its bucket closes, so candle mode streams like the line.
    var liveCandles: [LivelineCandle] = []

    // MARK: Data

    private var buffer: RingBuffer<LivelinePoint>
    private static let defaultCapacity = 8192

    /// One line series. In multi-series mode (``series`` non-empty) all series
    /// are equal peers — each with its own colour, endpoint dot, dashed baseline
    /// and label — and there is no single-series badge/value/momentum.
    struct Series {
        let id: String
        var color: RGBA
        var label: String?
        var buffer: RingBuffer<LivelinePoint>
        var visible = true
        var lastCommitTime: Double = -.infinity
        var displayValue: Double = 0  // eased current value, for a smooth dot
        var displayInited = false
        var labelY: CGFloat = 0  // resolved (de-collided) endpoint-label y
    }
    var series: [Series] = []
    var isMultiSeries: Bool { !series.isEmpty }

    /// The current order book, if any. Its resting sizes float upward behind the
    /// price line (see ``LivelineView/advanceAndDrawOrderbook(_:layout:dt:momentumMag:groupAlpha:)``).
    var orderbook: OrderbookData?
    var orderbookLabels: [OrderbookFloatLabel] = []
    var orderbookSpawnClock: Double = 0
    /// Previous total depth + eased churn (how fast the book is changing), which
    /// — with price momentum — drives the stream speed.
    var orderbookLastTotal: Double = -1
    var orderbookChurn: Double = 0

    // MARK: Easing state (persist across frames)

    private var displayValue: Double = 0
    private var displayValueInited = false
    /// Time of the last COMMITTED live sample, used to auto-bucket ``push(_:)``
    /// to the current window's resolution. `-inf` forces the next push to commit.
    private var lastCommitTime: Double = -.infinity
    /// Roughly how many live points to commit across the visible window before
    /// sliding the head instead of appending.
    private static let liveResolution: Double = 300
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

    // Degen mode + haptics state.
    var degenParticles: [DegenParticle] = []
    var degenShake: Double = 0
    var degenArmed = true
    var degenBaseline: Double = 0
    var degenBaselineInit = false
    lazy var lightHaptic = UIImpactFeedbackGenerator(style: .light)
    lazy var heavyHaptic = UIImpactFeedbackGenerator(style: .heavy)
    var lastHoverIndex = -1

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

    private lazy var valueLabel: TickerLabel = {
        let label = TickerLabel()
        label.font = .monospacedSystemFont(ofSize: 20, weight: .medium)
        label.isHidden = true
        return label
    }()
    /// Last value shown by the overlay, so the ticker knows which way to roll.
    private var lastValueShown = 0.0
    /// When the ticker last changed (ms), to throttle updates and pick roll vs snap.
    private var lastTickerMs = 0.0

    // MARK: Derived

    var palette: Palette
    /// Whether an opaque `surfaceColor` is set. When false the canvas is
    /// transparent: no background fill, and the left-edge fade erases to reveal
    /// what's behind the view rather than painting the surface over the line.
    var surfaceIsOpaque = false

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
        // showValue ticker: don't repaint the number more often than this. Each
        // digit rolls over ~0.28s; holding repaints to roughly that duration lets
        // a roll finish before the next starts, so fast moves step cleanly instead
        // of stacking into a blur of half-rolled digits.
        static let tickerThrottleMs = 280.0
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
    /// Default value formatter — the device locale's decimal style (correct
    /// decimal/grouping separators), 2 fraction digits. Main-thread only.
    private static let defaultNumberFormatter: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.locale = .current
        f.minimumFractionDigits = 2
        f.maximumFractionDigits = 2
        return f
    }()

    public static func defaultFormatValue(_ v: Double) -> String {
        defaultNumberFormatter.string(from: NSNumber(value: v)) ?? String(format: "%.2f", v)
    }

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = .current
        f.setLocalizedDateFormatFromTemplate("jmmss")
        return f
    }()

    /// Default time formatter — a locale-appropriate time (honours the device's
    /// 12/24-hour setting) in the local time zone.
    public static func defaultFormatTime(_ t: Double) -> String {
        timeFormatter.string(from: Date(timeIntervalSince1970: t))
    }

    /// Reusable `DateFormatter`s keyed by template, so auto-formatting the axis
    /// every frame never allocates. Each is built with
    /// `setLocalizedDateFormatFromTemplate` in the current locale, so field
    /// order, separators, month names and 12/24-hour all localize.
    /// Main-thread only (the render loop).
    private var timeFormatterCache: [String: DateFormatter] = [:]

    private func timeFormatter(_ template: String) -> DateFormatter {
        if let f = timeFormatterCache[template] { return f }
        let f = DateFormatter()
        f.locale = formattingLocale
        f.setLocalizedDateFormatFromTemplate(template)
        timeFormatterCache[template] = f
        return f
    }

    /// Axis label for a tick at time `t` (seconds). Uses `formatTime` when set,
    /// otherwise picks a format from the tick `interval`: year ticks show the
    /// year, month ticks the month, day ticks the date, finer ticks the time.
    func axisTimeLabel(_ t: Double, interval: Double) -> String {
        if let formatTime { return formatTime(t) }
        let template: String
        if interval >= 31_536_000 { template = "yyyy" }        // ≥ 1 year
        else if interval >= 2_592_000 { template = "MMMyyyy" }  // ≥ 1 month
        else if interval >= 86_400 { template = "dMMM" }        // ≥ 1 day
        else if interval >= 60 { template = "jmm" }            // ≥ 1 minute
        else { template = "jmmss" }
        return timeFormatter(template).string(from: Date(timeIntervalSince1970: t))
    }

    /// Crosshair label for a precise time `t`, scaled to the visible window so a
    /// year-wide view shows a full date while a live view shows seconds.
    func crosshairTimeLabel(_ t: Double) -> String {
        if let formatTime { return formatTime(t) }
        let w = windowSeconds
        let template: String
        if w >= 63_072_000 { template = "dMMMyyyy" }   // ≥ 2 years
        else if w >= 2_592_000 { template = "dMMM" }   // ≥ 1 month
        else if w >= 86_400 { template = "dMMMjmm" }   // ≥ 1 day
        else if w >= 3_600 { template = "jmm" }        // ≥ 1 hour
        else { template = "jmmss" }
        return timeFormatter(template).string(from: Date(timeIntervalSince1970: t))
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
        // Keep any existing samples OLDER than the new series' start. Switching to
        // a narrower window (zoom in) then still has data covering the left, so
        // the zoom magnifies smoothly instead of chopping the line off; switching
        // to a wider window keeps nothing (the new series already reaches back
        // further). Buffer points are chronological, so stop at the first overlap.
        var older: [LivelinePoint] = []
        if !wasEmpty, let newStart = points.first?.time {
            older.reserveCapacity(buffer.count)
            for i in 0..<buffer.count {
                let p = buffer[i]
                if p.time < newStart { older.append(p) } else { break }
            }
        }
        buffer.removeAll()
        for p in older { buffer.push(p) }
        for p in points { buffer.push(p) }
        if wasEmpty, let last = points.last {
            displayValue = last.value
            displayValueInited = true
            domain.reset()
        }
        // The next live push starts a fresh point after this backfill.
        lastCommitTime = -.infinity
        setNeedsDisplay()
    }

    /// Adds a live sample, adapting to the current window automatically: it
    /// commits a new point about every `windowSeconds / liveResolution` and
    /// slides the head in place between commits. So a fast feed on a wide window
    /// (1W, 4Y) repaints the current point at the window's resolution instead of
    /// piling ticks onto "now", while a live/short window keeps every tick. Just
    /// call it once per data tick — no per-window bookkeeping needed.
    public func push(_ point: LivelinePoint, seriesId: String? = nil) {
        if let seriesId, let idx = series.firstIndex(where: { $0.id == seriesId }) {
            var s = series[idx]
            commit(point, to: &s.buffer, lastCommit: &s.lastCommitTime)
            if !s.displayInited {
                s.displayValue = point.value
                s.displayInited = true
            }
            series[idx] = s
            setNeedsDisplay()
            return
        }
        commit(point, to: &buffer, lastCommit: &lastCommitTime)
        if !displayValueInited {
            displayValue = point.value
            displayValueInited = true
        }
        aggregateLiveCandle(point)
        setNeedsDisplay()
    }

    /// Buckets a live sample into a buffer at the current window's resolution.
    private func commit(
        _ point: LivelinePoint, to buffer: inout RingBuffer<LivelinePoint>, lastCommit: inout Double
    ) {
        let bucket = windowSeconds / LivelineView.liveResolution
        if buffer.count == 0 || point.time - lastCommit >= bucket {
            buffer.push(point)
            lastCommit = point.time
        } else {
            buffer.replaceLast(point)
        }
    }

    /// One additional line series — a context line rendered behind the primary.
    public struct SeriesInput {
        public let id: String
        public let color: UIColor
        public let label: String?
        public let data: [LivelinePoint]
        public init(id: String, color: UIColor, label: String? = nil, data: [LivelinePoint]) {
            self.id = id
            self.color = color
            self.label = label
            self.data = data
        }
    }

    /// Sets the line series. A non-empty array switches to multi-series mode
    /// (`data`/`value` are ignored); empty restores single-series. Per-series
    /// visibility (from the legend) is preserved across updates by `id`. Live
    /// updates use ``push(_:seriesId:)``.
    public func setSeries(_ input: [SeriesInput]) {
        let wasVisible = Dictionary(series.map { ($0.id, $0.visible) }, uniquingKeysWith: { a, _ in a })
        series = input.map { s in
            var buf = RingBuffer<LivelinePoint>(capacity: LivelineView.defaultCapacity)
            for p in s.data { buf.push(p) }
            var next = Series(id: s.id, color: s.color.rgba, label: s.label, buffer: buf)
            next.visible = wasVisible[s.id] ?? true
            if let last = s.data.last {
                next.displayValue = last.value
                next.displayInited = true
            }
            return next
        }
        setNeedsDisplay()
    }

    /// Hides or shows a series (driven by the legend chips).
    @discardableResult
    public func toggleSeries(_ id: String) -> Bool {
        guard let idx = series.firstIndex(where: { $0.id == id }) else { return true }
        series[idx].visible.toggle()
        setNeedsDisplay()
        return series[idx].visible
    }

    /// Folds a tick into the forming candle (OHLC), rolling to a new bucket when
    /// `candleWidth` elapses, so candle mode streams from the same `push()` feed.
    private func aggregateLiveCandle(_ point: LivelinePoint) {
        guard candleWidth > 0 else { return }
        let start = (point.time / candleWidth).rounded(.down) * candleWidth
        if var lc = liveCandle, lc.time == start {
            lc.high = max(lc.high, point.value)
            lc.low = min(lc.low, point.value)
            lc.close = point.value
            liveCandle = lc
        } else {
            if let closed = liveCandle { liveCandles.append(closed) }
            liveCandle = LivelineCandle(
                time: start, open: point.value, high: point.value, low: point.value, close: point.value)
        }
    }

    /// The most recently pushed value, or 0.
    public var currentValue: Double { buffer.last?.value ?? 0 }

    /// Strokes the plain line from the tick buffer over `layout` at `alpha` — used
    /// to fade the line out during the line→candle morph.
    func drawLineOverlay(_ ctx: CGContext, layout: Layout, now: Double, alpha: Double) {
        guard alpha > 0.01, buffer.count >= 2 else { return }
        var pts = [CGPoint]()
        pts.reserveCapacity(buffer.count)
        for i in 0..<buffer.count {
            let p = buffer[i]
            if p.time < layout.leftEdge - 2 { continue }
            if p.time > now { break }
            pts.append(CGPoint(x: layout.toX(p.time), y: layout.toY(p.value)))
        }
        guard pts.count >= 2 else { return }
        ctx.saveGState()
        ctx.setAlpha(CGFloat(alpha))
        ctx.setStrokeColor(UIColor(rgba: palette.line).cgColor)
        ctx.setLineWidth(lineWidth)
        ctx.setLineJoin(.round)
        ctx.setLineCap(.round)
        ctx.beginPath()
        ctx.move(to: pts[0])
        for p in pts.dropFirst() { ctx.addLine(to: p) }
        ctx.strokePath()
        ctx.restoreGState()
    }

    // MARK: Palette

    private func rebuildPalette() {
        var p = Theme.palette(accent: color.rgba, theme: theme)
        p.lineWidth = Double(lineWidth)
        // Overrides win over the theme-derived defaults. `theme` still sets the
        // tone of grid/labels/text; these only change specific surfaces.
        if let surfaceColor { p.background = surfaceColor.rgba }
        if let overrides = paletteOverrides { overrides(&p) }
        palette = p
        // With no opaque `surfaceColor` the canvas is transparent (web parity):
        // the chart paints no background fill and the container behind it shows
        // through. An opaque surface makes it a self-contained card instead.
        surfaceIsOpaque = (surfaceColor?.rgba.a ?? 0) > 0.001
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
        // Reserve a row above the plot for the showValue overlay (web parity).
        let top: CGFloat = showValue ? 40 : 12
        return (
            padTopOverride.map { CGFloat($0) } ?? top,
            padRightOverride.map { CGFloat($0) } ?? right,
            padBottomOverride.map { CGFloat($0) } ?? 28,
            padLeftOverride.map { CGFloat($0) } ?? 12
        )
    }

    /// The right-edge window buffer (fraction of the span). In line mode with
    /// momentum arrows + badge, it widens to leave a gap for the arrows. This is
    /// the single source of truth so the render and the crosshair's
    /// screen-x→time mapping agree — otherwise the crosshair drifts off the line.
    private func currentWinBuffer(chartW: CGFloat) -> Double {
        if mode == .candle { return 0.015 }  // matches CK.buffer in LivelineView+Candle
        var b = badge ? K.windowBuffer : K.windowBufferNoBadge
        if badge, momentum != .off {
            b = max(b, 37.0 / max(Double(chartW), 1))
        }
        return b
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

        // Only an opaque surface paints a background; otherwise the canvas stays
        // transparent so the container behind the chart shows through (web parity).
        if surfaceIsOpaque {
            ctx.setFillColor(UIColor(rgba: palette.background).cgColor)
            ctx.fill(bounds)
        }

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

        // Ease the line↔candle morph (0 = line, 1 = candle).
        modeProgress = Clock.lerp(current: modeProgress, target: mode == .candle ? 1 : 0, speed: 0.1, dt: dt)
        if modeProgress < 0.002 { modeProgress = 0 }
        if modeProgress > 0.998 { modeProgress = 1 }

        let isCandle = modeProgress > 0
        let hasCandle = !candles.isEmpty || liveCandle != nil || !liveCandles.isEmpty
        let hasSeriesData = isMultiSeries && series.contains { $0.visible && $0.buffer.count >= 2 }
        let hasData = hasSeriesData || (isCandle ? (hasCandle || buffer.count >= 2) : buffer.count >= 2)

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

        // Multi-series mode replaces the single-series render entirely (no
        // badge/value overlay/momentum — the per-series labels stand in).
        if isMultiSeries {
            if !valueLabel.isHidden { valueLabel.isHidden = true }
            drawMultiSeries(ctx, w: w, h: h, pad: pad, now: now, dt: dt, nowMs: nowMs)
            return
        }

        if !hasData {
            if loadingAlpha > 0.01 {
                drawLoading(ctx, w: w, h: h, pad: pad, nowMs: nowMs, alpha: loadingAlpha)
            }
            if (1 - loadingAlpha) > 0.01 {
                drawEmpty(ctx, w: w, h: h, pad: pad, nowMs: nowMs, alpha: 1 - loadingAlpha)
            }
            drawLeftEdgeFade(ctx, w: w, h: h, padLeft: pad.left)
            updateValueLabel(value: displayValue, trend: .flat, pad: pad)
            return
        }

        if isCandle {
            drawCandleFrame(
                ctx, w: w, h: h, pad: pad, now: now, dt: dt, pausedDt: pausedDt, nowMs: nowMs,
                modeProgress: modeProgress)
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

        // Window edges. The buffer widens for the momentum-arrow gap; using the
        // shared helper keeps the crosshair's hit-testing in sync.
        let winBuffer = currentWinBuffer(chartW: w - pad.left - pad.right)
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

        // Degen: shake the frame + advance particles before rendering.
        degenPreDraw(ctx, dt: dt)

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

        // 2.5 Orderbook: resting sizes float upward behind the price line.
        if hasOrderbook {
            let a = reveal < 1 ? revealRamp(0.15, 0.7) : 1
            let mMag = min(1, abs(value - smoothValue) / max(domain.valRange * 0.15, 1e-9))
            advanceAndDrawOrderbook(ctx, layout: layout, dt: dt, momentumMag: mMag, groupAlpha: a)
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

        // 5c. Degen burst — sparks + shake when the value pops up.
        degenTrigger(at: dotPoint, value: smoothValue, range: domain.valRange, dt: dt)
        degenDrawParticles(ctx)

        // 6. Left-edge fade.
        drawLeftEdgeFade(ctx, w: w, h: h, padLeft: pad.left)

        // 7. Crosshair. Recompute the hovered value from the CURRENT line every
        // frame (not just on finger-move) so the dot stays glued to the line as
        // a live chart scrolls and updates underneath it.
        if hoverX != nil, scrubAmount > 0.01 { updateHover() }
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

    func updateValueLabel(
        value: Double, trend: Trend, pad: (top: CGFloat, right: CGFloat, bottom: CGFloat, left: CGFloat)
    ) {
        guard showValue else {
            if !valueLabel.isHidden { valueLabel.isHidden = true }
            return
        }
        valueLabel.isHidden = false
        // When momentum-coloured, drop the sign — the colour conveys direction (web parity).
        let shown = valueMomentumColor ? abs(value) : value
        let color: RGBA
        if valueMomentumColor, trend != .flat {
            color = trend == .up ? Theme.up : Theme.down
        } else {
            color = palette.tooltipText
        }
        valueLabel.textColor = UIColor(rgba: color)
        // The ticker rolls each changed digit over ~0.28s. Driven every frame by
        // the eased value, fast movement would restart a digit's roll before it
        // finishes — a blur of half-rolled ghosts. Throttling repaints to about
        // the roll's own duration lets each roll finish first, so fast moves step
        // over cleanly. Slow moves change less often than the throttle, so they
        // roll immediately, exactly as before.
        let text = formatValue(shown)
        let nowMs = CACurrentMediaTime() * 1000
        if text != valueLabel.currentText, nowMs - lastTickerMs >= K.tickerThrottleMs {
            valueLabel.setText(text, up: shown >= lastValueShown)
            lastTickerMs = nowMs
            lastValueShown = shown
        }
        // Top-left, above the plot (matching web's block above the chart).
        let size = valueLabel.intrinsicContentSize
        valueLabel.frame = CGRect(x: pad.left, y: 6, width: size.width, height: size.height)
    }

    // MARK: Momentum resolution

    func resolveTrend() -> Trend? {
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
        case .began:
            isHovering = true
            lastHoverIndex = -1
            if haptics { lightHaptic.prepare() }
            hoverX = min(max(gesture.location(in: self).x, 0), bounds.width)
            updateHover(emitHaptics: true)
            setNeedsDisplay()
        case .changed:
            isHovering = true
            hoverX = min(max(gesture.location(in: self).x, 0), bounds.width)
            updateHover(emitHaptics: true)
            setNeedsDisplay()
        case .ended, .cancelled, .failed:
            isHovering = false
        default:
            break
        }
    }

    /// Recomputes the hovered sample. `emitHaptics` is only true for real finger
    /// movement (the per-frame re-glue call passes false), so a light tap fires
    /// as the crosshair crosses each step — never from the chart scrolling under
    /// a still finger.
    private func updateHover(emitHaptics: Bool = false) {
        guard let hx = hoverX else { return }
        let pad = padding()
        let w = bounds.width
        guard hx >= pad.left, hx <= w - pad.right else { return }
        let now = Date().timeIntervalSince1970 - timeDebt
        let winBuffer = currentWinBuffer(chartW: w - pad.left - pad.right)
        let rightEdge = now + displayWindow * winBuffer
        let leftEdge = rightEdge - displayWindow
        let maxX = pad.left + CGFloat((now - leftEdge) / (rightEdge - leftEdge)) * (w - pad.left - pad.right)
        let clampedX = min(hx, maxX)
        let t = leftEdge + Double((clampedX - pad.left) / (w - pad.left - pad.right)) * (rightEdge - leftEdge)
        if let v = Interpolate.atTime(buffer.elements, time: t) {
            lastHover = (clampedX, v, t)
        }
        if emitHaptics, haptics, isHovering {
            let idx = Int(clampedX / 6)  // a tap roughly every 6pt of travel
            if idx != lastHoverIndex {
                lightHaptic.impactOccurred(intensity: 0.5)
                lightHaptic.prepare()
                lastHoverIndex = idx
            }
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
