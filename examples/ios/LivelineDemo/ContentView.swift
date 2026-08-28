import LivelineKit
import SwiftUI

/// A scrollable showcase of the implemented line-mode features. A global
/// Light/Dark toggle drives the whole screen's subtle gradient background *and*
/// every chart's `theme`, so each demo can be checked in both tones. The charts
/// are transparent (the default), so the gradient shows straight through them —
/// nothing paints its own background. The one exception is "Custom surface",
/// which sets an opaque `surfaceColor` independent of the theme.
struct ContentView: View {
    enum Demo: String, CaseIterable, Identifiable {
        case basic = "Basic"
        case momentum = "Momentum"
        case valueOverlay = "Value overlay"
        case referenceLine = "Reference line"
        case heartRate = "Heart rate"
        case cpu = "CPU usage"
        case sparse = "Slow ticker"
        case timeWindows = "Time windows"
        case candlestick = "Candlestick"
        case prediction = "Prediction market"
        case orderbook = "Orderbook"
        case degen = "Degen"
        case states = "Loading"
        case noData = "No data"
        case paused = "Paused"
        case stale = "Stale feed"
        case stress = "Stress tests"
        case surface = "Custom surface"
        var id: String { rawValue }
    }

    @State private var selected: Demo = .basic
    @State private var dark = true

    /// A super-subtle diagonal gradient: black→dark-grey in dark mode,
    /// light-grey→white in light mode. Because the charts are transparent, this
    /// is what you see behind every line.
    private var appBackground: LinearGradient {
        let stops: [Color] =
            dark
            ? [Color(red: 0.02, green: 0.02, blue: 0.02), Color(red: 0.12, green: 0.12, blue: 0.13)]
            : [Color(red: 0.90, green: 0.91, blue: 0.93), Color(red: 1, green: 1, blue: 1)]
        return LinearGradient(colors: stops, startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                appBackground.ignoresSafeArea()
                VStack(alignment: .leading, spacing: 16) {
                    Picker("Theme", selection: $dark) {
                        Text("Light").tag(false)
                        Text("Dark").tag(true)
                    }
                    .pickerStyle(.segmented)

                    Picker("Demo", selection: $selected) {
                        ForEach(Demo.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.menu)

                    // Only the selected demo is mounted, so a single chart (one
                    // display link + one feed) runs at a time.
                    selectedCard
                        .id(selected)
                    Spacer()
                }
                .padding()
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
            .navigationTitle("Liveline")
        }
        .preferredColorScheme(dark ? .dark : .light)
    }

    @ViewBuilder private var selectedCard: some View {
        switch selected {
        case .basic: BasicCard()
        case .momentum: MomentumCard()
        case .valueOverlay: ValueOverlayCard()
        case .referenceLine: ReferenceLineCard()
        case .heartRate: HeartRateCard()
        case .cpu: CPUCard()
        case .sparse: SparseCard()
        case .timeWindows: TimeWindowsCard()
        case .candlestick: CandlestickCard()
        case .prediction: PredictionCard()
        case .orderbook: OrderbookCard()
        case .degen: DegenCard()
        case .states: StatesCard()
        case .noData: NoDataCard()
        case .paused: PausedCard()
        case .stale: StaleFeedCard()
        case .stress: StressCard()
        case .surface: SurfaceCard()
        }
    }
}

/// Maps the SwiftUI colour scheme to a Liveline theme, so every chart's tone
/// follows the global toggle.
private func livelineTheme(_ scheme: ColorScheme) -> LivelineTheme { scheme == .dark ? .dark : .light }

// MARK: - Card chrome

private struct Card<Content: View>: View {
    let title: String
    let subtitle: String
    @ViewBuilder var content: () -> Content
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.headline)
            // No fill: the chart is transparent, so the app gradient shows
            // through. A hairline border just delineates the card.
            content()
                .frame(height: 220)
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(
                            scheme == .dark ? Color.white.opacity(0.1) : Color.black.opacity(0.08),
                            lineWidth: 1)
                )
            Text(subtitle).font(.caption).foregroundStyle(.secondary)
        }
    }
}

// MARK: - Feed models

/// Standard normal via Box–Muller — smoother tails than a uniform.
func randn() -> Double {
    let u = Double.random(in: Double.leastNormalMagnitude...1)
    let v = Double.random(in: 0...1)
    return (-2 * log(u)).squareRoot() * cos(2 * Double.pi * v)
}

/// A trending random walk. Instead of i.i.d. up/down noise (which reads as
/// jittery zig-zag), it integrates a slowly-decaying AR(1) *velocity*, so the
/// value keeps moving one direction for a stretch — mostly up during an up-move,
/// with the odd down-tick — then stalls and reverses. Mean-reversion keeps it
/// bounded. `momentum` is the velocity autocorrelation (higher = longer trends).
struct TrendWalk {
    private(set) var value: Double
    private var velocity = 0.0
    private let center, vol, momentum, reversion, drift: Double

    init(
        center: Double, vol: Double, momentum: Double = 0.94, reversion: Double = 0.01,
        drift: Double = 0
    ) {
        self.center = center
        self.vol = vol
        self.momentum = momentum
        self.reversion = reversion
        self.drift = drift
        self.value = center
    }

    /// Advance one step and return the new value. `drift` biases the velocity, so
    /// a positive value trends the walk upward (used to make degen mostly moon).
    mutating func step() -> Double {
        let kick = vol * (1 - momentum * momentum).squareRoot()
        velocity = velocity * momentum + randn() * kick + drift
        value += velocity + (center - value) * reversion
        return value
    }

    /// A backfill history ending at "now", so a chart opens populated.
    mutating func seed(seconds: Double = 45, hz: Double = 5) -> [LivelinePoint] {
        let now = Date().timeIntervalSince1970
        let n = Int(seconds * hz)
        return (0..<n).map { i in
            LivelinePoint(time: now - seconds + Double(i) / hz, value: step())
        }
    }
}

/// A trending feed pushing values at 20 Hz. Models a data source, deliberately
/// separate from the chart's own render loop. Starts from a backfilled history
/// (continuing seamlessly, no jump) so the chart is populated immediately.
final class Walk: ObservableObject {
    @Published var value: Double
    let seed: [LivelinePoint]
    private var walk: TrendWalk
    private var timer: Timer?
    private var ticks = 0

    /// When set, the feed stops pushing after this many seconds (to observe a
    /// stale feed). `nil` runs forever.
    var stopAfterSeconds: Double?
    /// When set, the feed holds its value until this many seconds have elapsed
    /// (to observe the loading state before data arrives).
    var feedDelaySeconds: Double?
    /// Optional callback each tick with the elapsed seconds — used by the
    /// loading demo to flip state.
    var onTick: ((Double) -> Void)?

    /// Seconds between pushes. Most feeds run at 20 Hz; a calmer demo (e.g. the
    /// value overlay) can push less often so the number steps rather than races.
    private let interval: Double

    init(
        center: Double = 100, vol: Double = 0.55, momentum: Double = 0.94, reversion: Double = 0.01,
        interval: Double = 0.05, drift: Double = 0
    ) {
        self.interval = interval
        var w = TrendWalk(
            center: center, vol: vol, momentum: momentum, reversion: reversion, drift: drift)
        self.seed = w.seed()
        self.value = w.value
        self.walk = w
        start()
    }

    private func start() {
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            self?.step()
        }
    }

    private func step() {
        ticks += 1
        let elapsed = Double(ticks) * interval
        onTick?(elapsed)
        if let delay = feedDelaySeconds, elapsed < delay { return }
        if let stop = stopAfterSeconds, elapsed > stop { return }
        value = walk.step()
    }

    deinit { timer?.invalidate() }
}

// MARK: - Cards

private struct BasicCard: View {
    @StateObject private var walk = Walk()
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        Card(title: "Basic", subtitle: "A live value. Two props: data and value.") {
            Liveline(data: walk.seed, value: walk.value)
                .theme(livelineTheme(scheme))
        }
    }
}

private struct MomentumCard: View {
    @StateObject private var walk = Walk(vol: 0.7)
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        Card(
            title: "Momentum",
            subtitle: "Directional chevrons on the live dot; the badge tints green up / red down."
        ) {
            Liveline(data: walk.seed, value: walk.value)
                .momentum(.auto)
                .theme(livelineTheme(scheme))
        }
    }
}

private struct ValueOverlayCard: View {
    @StateObject private var walk = Walk(
        center: 9800, vol: 4, momentum: 0.95, reversion: 0.008, interval: 0.3)
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        Card(
            title: "Value overlay",
            subtitle: "showValue draws the live number over the chart; valueMomentumColor tints it."
        ) {
            Liveline(data: walk.seed, value: walk.value)
                .showValue()
                .valueMomentumColor()
                .formatValue { String(format: "$%.2f", $0) }
                .theme(livelineTheme(scheme))
        }
    }
}

private struct ReferenceLineCard: View {
    @StateObject private var walk = Walk(center: 67_500, vol: 55, momentum: 0.93)
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        Card(title: "Reference line", subtitle: "A horizontal marker at a fixed value, kept in view.") {
            Liveline(data: walk.seed, value: walk.value)
                .color(Color(red: 0.55, green: 0.36, blue: 0.96))
                .referenceLine(ReferenceLine(value: 67_500, label: "Above $67,500"))
                .formatValue { String(format: "$%.0f", $0) }
                .theme(livelineTheme(scheme))
        }
    }
}

private struct HeartRateCard: View {
    // A realistic resting rate: updates about once a second, low volatility and
    // strong mean-reversion so it holds ~68 bpm with only small beat-to-beat
    // drift — which `exaggerate` then magnifies to fill the height.
    @StateObject private var walk = Walk(
        center: 68, vol: 0.5, momentum: 0.5, reversion: 0.06, interval: 1.0)
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        Card(
            title: "Heart rate",
            subtitle: "exaggerate tightens the Y-axis so the small bpm variation fills the height. Custom bpm formatter."
        ) {
            Liveline(data: walk.seed, value: walk.value)
                .color(Color(red: 0.9, green: 0.3, blue: 0.24))
                .exaggerate()
                .formatValue { String(format: "%.0f bpm", $0) }
                .theme(livelineTheme(scheme))
        }
    }
}

/// Loading for 3 s, then the chart morphs into the (already backfilled) data —
/// the common real-world case where history exists behind a connecting state.
final class StatesModel: ObservableObject {
    @Published var value: Double
    @Published var loading = true
    let seed: [LivelinePoint]
    private var walk: TrendWalk
    private var timer: Timer?
    private var t = 0.0

    init() {
        var w = TrendWalk(center: 210, vol: 0.9)
        seed = w.seed()
        value = w.value
        walk = w
        timer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            self?.step()
        }
    }

    private func step() {
        t += 0.05
        // Rotate loading ↔ loaded every 4s so the state is observable on a loop.
        loading = t.truncatingRemainder(dividingBy: 8) < 4
        value = walk.step()
    }

    deinit { timer?.invalidate() }
}

/// Toggles `loading` on a chart that never receives data — loading wins, so it
/// breathes while loading and falls back to the empty state otherwise.
final class NoDataModel: ObservableObject {
    @Published var loading = true
    private var timer: Timer?
    private var t = 0.0

    init() {
        timer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            self?.t += 0.05
            self?.loading = (self!.t.truncatingRemainder(dividingBy: 8)) < 4
        }
    }

    deinit { timer?.invalidate() }
}

private struct NoDataCard: View {
    @StateObject private var model = NoDataModel()
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        Card(
            title: "No data",
            subtitle: "An empty chart. Loading wins: it breathes while loading, then shows the empty state (toggles every 4s)."
        ) {
            Liveline()
                .color(Color(red: 0.29, green: 0.68, blue: 0.4))
                .loading(model.loading)
                .theme(livelineTheme(scheme))
        }
    }
}

private struct SurfaceCard: View {
    @StateObject private var walk = Walk(center: 100, vol: 0.55)
    var body: some View {
        Card(
            title: "Custom surface",
            subtitle: "The opt-in exception: an opaque surfaceColor paints its own card, independent of the theme."
        ) {
            Liveline(data: walk.seed, value: walk.value)
                .color(Color(red: 0.67, green: 0.62, blue: 0.95))  // #AB9FF2
                .theme(.dark)
                .surfaceColor(Color(red: 0.11, green: 0.08, blue: 0.18))  // #1c1530
        }
    }
}

private struct DegenCard: View {
    // A mostly-moon feed: an upward drift + long momentum so it keeps pumping,
    // firing the degen shake/sparks often.
    @StateObject private var walk = Walk(center: 420, vol: 3, momentum: 0.9, reversion: 0.006, drift: 0.12)
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        Card(
            title: "Degen",
            subtitle: "Chart shake + sparks on strong up-moves, with momentum arrows and haptics."
        ) {
            Liveline(data: walk.seed, value: walk.value)
                .color(Color(red: 245.0/255, green: 115.0/255, blue: 31.0/255))  // #f5731f
                .momentum(.auto)
                .degen()
                .haptics()
                .badgeVariant(.accent)  // orange badge, matching the line + sparks
                .theme(livelineTheme(scheme))
                .formatValue { String(format: "%.2f", $0) }
        }
    }
}

private struct StatesCard: View {
    @StateObject private var model = StatesModel()
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        Card(
            title: "Loading",
            subtitle: "Toggles every 4s: a breathing line, then it morphs into the backfilled chart."
        ) {
            Liveline(data: model.seed, value: model.value)
                .color(Color(red: 0.29, green: 0.68, blue: 0.4))
                .loading(model.loading)
                .theme(livelineTheme(scheme))
        }
    }
}

/// Auto-toggles pause every 4 s while data keeps arriving, so the resume /
/// catch-up behaviour is observable without tapping.
final class PausedModel: ObservableObject {
    @Published var value: Double
    @Published var paused = false
    let seed: [LivelinePoint]
    private var walk: TrendWalk
    private var timer: Timer?
    private var t = 0.0

    init() {
        var w = TrendWalk(center: 160, vol: 0.7)
        seed = w.seed()
        value = w.value
        walk = w
        timer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            self?.step()
        }
    }

    private func step() {
        t += 0.05
        paused = t.truncatingRemainder(dividingBy: 8) >= 4
        value = walk.step()
    }

    deinit { timer?.invalidate() }
}

private struct PausedCard: View {
    @StateObject private var model = PausedModel()
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        Card(
            title: "Paused",
            subtitle: "Auto-toggles every 4s. Data keeps arriving while paused; on resume it catches up."
        ) {
            VStack(spacing: 8) {
                Text(model.paused ? "⏸ Paused" : "▶ Playing")
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                Liveline(data: model.seed, value: model.value)
                    .color(Color(red: 0.29, green: 0.68, blue: 0.4))
                    .paused(model.paused)
                    .theme(livelineTheme(scheme))
            }
        }
    }
}

/// A slow ticker: one update every 4 s, like a low-volume asset. Liveline
/// interpolates between updates so it still scrolls smoothly.
final class SparseFeed: ObservableObject {
    @Published var value: Double
    let seed: [LivelinePoint]
    private var walk: TrendWalk
    private var timer: Timer?

    init() {
        // A sparse backfill: one point every 4s (a low-volume asset).
        var w = TrendWalk(center: 100, vol: 4, momentum: 0.6)
        seed = w.seed(seconds: 48, hz: 0.25)
        value = w.value
        walk = w
        timer = Timer.scheduledTimer(withTimeInterval: 4.0, repeats: true) { [weak self] _ in
            guard let self else { return }
            self.value = self.walk.step()
        }
    }

    deinit { timer?.invalidate() }
}

private struct SparseCard: View {
    @StateObject private var feed = SparseFeed()
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        Card(
            title: "Slow ticker",
            subtitle: "One update every 4s (a low-volume asset). It still scrolls smoothly between ticks."
        ) {
            Liveline(data: feed.seed, value: feed.value)
                .window(60)
                .color(Color(red: 0.55, green: 0.36, blue: 0.96))
                .theme(livelineTheme(scheme))
        }
    }
}

private struct StaleFeedCard: View {
    @StateObject private var walk: Walk = {
        let w = Walk(center: 100, vol: 0.55)
        w.stopAfterSeconds = 6
        return w
    }()
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        Card(
            title: "Stale feed",
            subtitle: "The feed stops after 6s. The chart keeps scrolling; the line runs flat to the edge."
        ) {
            Liveline(data: walk.seed, value: walk.value)
                .theme(livelineTheme(scheme))
        }
    }
}

// MARK: - CPU usage (spikes)

/// A low idle baseline (~14%) with occasional spikes that decay away — the
/// classic "mostly quiet, sometimes busy" system metric.
final class CPUFeed: ObservableObject {
    @Published var value: Double
    let seed: [LivelinePoint]
    private var base = TrendWalk(center: 14, vol: 1.2, momentum: 0.85, reversion: 0.06)
    private var spike = 0.0
    private var timer: Timer?

    init() {
        let now = Date().timeIntervalSince1970
        var b = TrendWalk(center: 14, vol: 1.2, momentum: 0.85, reversion: 0.06)
        var sp = 0.0
        var pts = [LivelinePoint]()
        for i in 0..<200 {
            let bv = b.step()
            if Double.random(in: 0...1) > 0.985 { sp = Double.random(in: 40...75) }
            sp *= 0.8
            pts.append(
                LivelinePoint(
                    time: now - 45 + Double(i) / 199 * 45, value: max(2, min(100, bv + sp))))
        }
        seed = pts
        base = b
        spike = sp
        value = pts.last!.value
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            self?.step()
        }
    }

    private func step() {
        let bv = base.step()
        if Double.random(in: 0...1) > 0.985 { spike = Double.random(in: 40...75) }
        spike *= 0.82
        value = max(2, min(100, bv + spike))
    }

    deinit { timer?.invalidate() }
}

private struct CPUCard: View {
    @StateObject private var feed = CPUFeed()
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        Card(
            title: "CPU usage",
            subtitle: "A low idle baseline with occasional spikes."
        ) {
            Liveline(data: feed.seed, value: feed.value)
                .color(Color(red: 0.29, green: 0.682, blue: 0.4))  // #4aae66
                .window(60)
                .formatValue { String(format: "%.0f%%", $0) }
                .theme(livelineTheme(scheme))
        }
    }
}

// MARK: - Stress tests

/// The blog's stress-test matrix: extreme feeds that exercise the render loop
/// and easing under wild, chaotic, spiky, reversing and irregular input.
enum Stress: String, CaseIterable, Identifiable {
    case wild = "Wild swings"
    case flatSpikes = "Near-flat + spikes"
    case chaotic = "Chaotic"
    case reversals = "Sharp reversals"
    case isolatedSpikes = "Isolated spikes"
    case zigzag = "Rapid zigzag"
    case irregular = "Irregular arrivals"
    var id: String { rawValue }

    var detail: String {
        switch self {
        case .wild: return "Large continuous swings at 100ms."
        case .flatSpikes: return "A near-flat line with sudden spikes (exaggerated Y)."
        case .chaotic: return "Massive fluctuations at 80ms."
        case .reversals: return "Frequent sharp direction reversals at 60ms."
        case .isolatedSpikes: return "Nearly flat with rare extreme spikes (exaggerated Y)."
        case .zigzag: return "Rapid alternating oscillation at 50ms."
        case .irregular: return "Bursts of updates with random 1–3s stalls."
        }
    }

    var interval: TimeInterval {
        switch self {
        case .wild: return 0.1
        case .flatSpikes: return 0.15
        case .chaotic: return 0.08
        case .reversals: return 0.06
        case .isolatedSpikes: return 0.12
        case .zigzag: return 0.05
        case .irregular: return 0.06
        }
    }

    var exaggerate: Bool { self == .flatSpikes || self == .isolatedSpikes }
}

final class StressFeed: ObservableObject {
    @Published var value: Double = 100
    private let variant: Stress
    private(set) var seed: [LivelinePoint] = []
    private var timer: Timer?
    private var v = 100.0
    private var dir = 1.0
    private var ticks = 0

    init(_ variant: Stress) {
        self.variant = variant
        reset()
    }

    private func reset() {
        timer?.invalidate()
        let now = Date().timeIntervalSince1970
        var s = 100.0
        var pts = [LivelinePoint]()
        for i in 0..<200 {
            s += Double.random(in: -3...3)
            pts.append(LivelinePoint(time: now - 30 + Double(i) / 199 * 30, value: s))
        }
        seed = pts
        v = s
        value = s
        dir = 1
        ticks = 0
        schedule()
    }

    private func schedule() {
        timer = Timer.scheduledTimer(withTimeInterval: variant.interval, repeats: true) {
            [weak self] _ in self?.step()
        }
    }

    private func step() {
        ticks += 1
        switch variant {
        case .wild: v += Double.random(in: -8...8)
        case .flatSpikes:
            v += Double.random(in: -0.3...0.3)
            if Double.random(in: 0...1) > 0.95 { v += Double.random(in: -25...25) }
        case .chaotic: v += Double.random(in: -18...18)
        case .reversals:
            if ticks % 6 == 0 { dir = -dir }
            v += dir * Double.random(in: 2...10)
        case .isolatedSpikes:
            v += Double.random(in: -0.2...0.2)
            if Double.random(in: 0...1) > 0.97 { v += Double.random(in: -40...40) }
        case .zigzag:
            dir = -dir
            v += dir * Double.random(in: 4...9)
        case .irregular: v += Double.random(in: -6...6)
        }
        v = max(20, min(180, v))
        value = v
        // Occasionally stall the irregular feed for 1–3s, then resume.
        if variant == .irregular, Int.random(in: 0...40) == 0 {
            timer?.invalidate()
            DispatchQueue.main.asyncAfter(deadline: .now() + Double.random(in: 1...3)) {
                [weak self] in self?.schedule()
            }
        }
    }

    deinit { timer?.invalidate() }
}

private struct StressCard: View {
    // The picker binds to a plain `@State`, and the high-frequency value feed
    // lives in the child `StressChart` — so the ~10–20 pushes/sec never re-render
    // this view. Previously the picker sat on the same view as the @Published
    // `value`, so it rebuilt under every tap and swallowed the selection.
    @State private var variant: Stress = .wild
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker("Pattern", selection: $variant) {
                ForEach(Stress.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.menu)
            Card(title: "Stress tests", subtitle: variant.detail) {
                // .id restarts the feed (fresh seed) when the pattern changes.
                StressChart(variant: variant, dark: scheme == .dark).id(variant)
            }
        }
    }
}

/// Owns the high-frequency stress feed, isolated from the picker so its
/// per-push re-renders don't reach the menu.
private struct StressChart: View {
    let variant: Stress
    let dark: Bool
    @StateObject private var feed: StressFeed

    init(variant: Stress, dark: Bool) {
        self.variant = variant
        self.dark = dark
        _feed = StateObject(wrappedValue: StressFeed(variant))
    }

    var body: some View {
        Liveline(data: feed.seed, value: feed.value)
            .color(Color(red: 0.9, green: 0.3, blue: 0.24))
            .exaggerate(variant.exaggerate)
            .theme(dark ? .dark : .light)
    }
}

// MARK: - Multi-series (prediction market)

/// Three outcomes that always sum to 100%. Backfills each series' history and
/// publishes a fresh set of values every tick for the live feed. A slow wave
/// sets the trend; a smaller, faster wave keeps the head visibly moving without
/// jagged spikes.
final class PredictionModel: ObservableObject {
    @Published var values: [String: Double] = [:]
    let seriesInputs: [LivelineView.SeriesInput]
    private var timer: Timer?

    private static let defs: [(id: String, color: UIColor, label: String)] = [
        ("yes", UIColor(red: 0.23, green: 0.51, blue: 0.96, alpha: 1), "Yes"),
        ("maybe", UIColor(red: 0.96, green: 0.62, blue: 0.07, alpha: 1), "Maybe"),
        ("no", UIColor(red: 0.94, green: 0.27, blue: 0.27, alpha: 1), "No"),
    ]

    init() {
        let now = Date().timeIntervalSince1970
        let window = 45.0
        let n = 200
        seriesInputs = PredictionModel.defs.map { def in
            let pts = (0..<n).map { i -> LivelinePoint in
                let t = now - window + Double(i) / Double(n - 1) * window
                return LivelinePoint(time: t, value: PredictionModel.market(t)[def.id]!)
            }
            return .init(id: def.id, color: def.color, label: def.label, data: pts)
        }
        values = PredictionModel.market(now)
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            self?.values = PredictionModel.market(Date().timeIntervalSince1970)
        }
    }

    /// Deterministic so backfill and live feed line up seamlessly. A realistic
    /// lopsided market: Yes leads at ~70–90%, then Maybe, then No.
    static func market(_ t: Double) -> [String: Double] {
        let yes = 80 + sin(t * 0.18) * 8 + sin(t * 0.6) * 2
        let maybe = 13 + sin(t * 0.22 + 1) * 3
        let no = 7 + cos(t * 0.28) * 2
        let sum = yes + no + maybe
        return ["yes": yes / sum * 100, "no": no / sum * 100, "maybe": maybe / sum * 100]
    }

    deinit { timer?.invalidate() }
}

private struct PredictionCard: View {
    @StateObject private var model = PredictionModel()
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        Card(
            title: "Prediction market",
            subtitle: "Multi-series: three outcomes summing to 100%. Tap a chip to toggle a line."
        ) {
            Liveline()
                .series(model.seriesInputs)
                .seriesValues(model.values)
                .window(45)
                .formatValue { String(format: "%.0f%%", $0) }
                .theme(livelineTheme(scheme))
        }
    }
}

// MARK: - Orderbook stream

/// A price line plus a synthetic order book (six levels each side, sizes
/// jittering each tick). The chart floats the resting sizes upward behind the
/// line — bids green, asks red — faster when the price is moving.
final class OrderbookFeed: ObservableObject {
    @Published var value: Double
    @Published var book: OrderbookData
    let seed: [LivelinePoint]
    private var walk: TrendWalk
    private var timer: Timer?

    init() {
        var w = TrendWalk(center: 62, vol: 0.45)
        seed = w.seed()
        value = w.value
        walk = w
        book = OrderbookFeed.makeBook(price: w.value)
        timer = Timer.scheduledTimer(withTimeInterval: 0.12, repeats: true) { [weak self] _ in
            self?.step()
        }
    }

    private func step() {
        let price = walk.step()
        value = price
        book = OrderbookFeed.makeBook(price: price)
    }

    static func makeBook(price: Double) -> OrderbookData {
        var bids = [OrderbookLevel]()
        var asks = [OrderbookLevel]()
        for i in 0..<6 {
            let d = Double(i) * 0.12 + 0.08
            // Dollar-ish order sizes: mostly small, the occasional whale.
            let bid = Double.random(in: 0...1) > 0.9 ? Double.random(in: 80...260) : Double.random(in: 4...70)
            let ask = Double.random(in: 0...1) > 0.9 ? Double.random(in: 80...260) : Double.random(in: 4...70)
            bids.append(OrderbookLevel(price: price - d, size: bid))
            asks.append(OrderbookLevel(price: price + d, size: ask))
        }
        return OrderbookData(bids: bids, asks: asks)
    }

    deinit { timer?.invalidate() }
}

private struct OrderbookCard: View {
    @StateObject private var feed = OrderbookFeed()
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        Card(
            title: "Orderbook",
            subtitle: "Bid/ask sizes float up behind the price line — green bids, red asks."
        ) {
            Liveline(data: feed.seed, value: feed.value)
                .orderbook(feed.book)
                .formatValue { String(format: "%.0f¢", $0) }
                .theme(livelineTheme(scheme))
        }
    }
}

// MARK: - Candlestick

/// Aggregates a random-walk price into fixed-width OHLC candles plus a live
/// candle that keeps updating within the current bucket.
final class CandleFeed: ObservableObject {
    @Published var candles: [LivelineCandle] = []
    @Published var live: LivelineCandle
    let candleWidth: Double = 3
    private var walk = TrendWalk(center: 150, vol: 1.4, momentum: 0.93, reversion: 0.006)
    private var timer: Timer?

    init() {
        // Backfill ~18 historical candles so the chart opens populated.
        let cw = 3.0
        let liveBucket = (Date().timeIntervalSince1970 / cw).rounded(.down) * cw
        var w = TrendWalk(center: 150, vol: 1.4, momentum: 0.93, reversion: 0.006)
        var history = [LivelineCandle]()
        for i in 0..<18 {
            let open = w.value
            var hi = open
            var lo = open
            var close = open
            for _ in 0..<10 {
                close = w.step()
                hi = max(hi, close)
                lo = min(lo, close)
            }
            history.append(
                LivelineCandle(
                    time: liveBucket - cw * Double(18 - i), open: open, high: hi, low: lo, close: close))
        }
        candles = history
        walk = w
        let p = w.value
        live = LivelineCandle(time: liveBucket, open: p, high: p, low: p, close: p)
        timer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            self?.step()
        }
    }

    private func step() {
        let price = walk.step()
        let bucket = (Date().timeIntervalSince1970 / candleWidth).rounded(.down) * candleWidth
        if bucket != live.time {
            candles.append(live)
            if candles.count > 40 { candles.removeFirst(candles.count - 40) }
            live = LivelineCandle(time: bucket, open: price, high: price, low: price, close: price)
        } else {
            var l = live
            l.high = max(l.high, price)
            l.low = min(l.low, price)
            l.close = price
            live = l
        }
    }

    deinit { timer?.invalidate() }
}

private struct TimeWindowsCard: View {
    @StateObject private var walk = Walk(center: 87, vol: 0.6)
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        Card(
            title: "Time windows",
            subtitle: "Tap a window to smoothly zoom the interval."
        ) {
            Liveline(data: walk.seed, value: walk.value)
                .color(Color(red: 242.0/255, green: 153.0/255, blue: 15.0/255))  // #f2990f
                .windows([
                    Window(label: "30s", secs: 30), Window(label: "1m", secs: 60),
                    Window(label: "5m", secs: 300),
                ])
                .windowStyle(.rounded)
                .formatValue { String(format: "%.0f%%", $0) }
                .theme(livelineTheme(scheme))
        }
    }
}

private struct CandlestickCard: View {
    @StateObject private var feed = CandleFeed()
    @State private var candle = true
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        Card(
            title: "Candlestick",
            subtitle: "OHLC candles with a live candle that grows its wicks. Toggle line / candle."
        ) {
            Liveline(value: feed.live.close)
                .mode(candle ? .candle : .line)
                .candles(feed.candles)
                .liveCandle(feed.live)
                .candleWidth(feed.candleWidth)
                .modeToggle()
                .onModeChange { candle = ($0 == .candle) }
                .theme(livelineTheme(scheme))
        }
    }
}

#Preview {
    ContentView()
}
