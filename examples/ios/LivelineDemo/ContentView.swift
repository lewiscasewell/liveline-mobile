import LivelineKit
import SwiftUI

/// A scrollable showcase of the implemented line-mode features, mirroring the
/// web liveline docs. Each card owns its own feed so the scenarios (loading,
/// stale data, pausing, exaggerated axis, reference line, theming) can be
/// observed independently.
struct ContentView: View {
    enum Demo: String, CaseIterable, Identifiable {
        case basic = "Basic"
        case momentum = "Momentum"
        case valueOverlay = "Value overlay"
        case referenceLine = "Reference line"
        case heartRate = "Heart rate"
        case sparse = "Slow ticker"
        case theming = "Theming"
        case surface = "Custom surface"
        case timeWindows = "Time windows"
        case candlestick = "Candlestick"
        case states = "States (loading)"
        case paused = "Paused"
        case stale = "Stale feed"
        var id: String { rawValue }
    }

    @State private var selected: Demo = .basic

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
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
            .navigationTitle("Liveline")
        }
    }

    @ViewBuilder private var selectedCard: some View {
        switch selected {
        case .basic: BasicCard()
        case .momentum: MomentumCard()
        case .valueOverlay: ValueOverlayCard()
        case .referenceLine: ReferenceLineCard()
        case .heartRate: HeartRateCard()
        case .sparse: SparseCard()
        case .theming: ThemingCard()
        case .surface: SurfaceCard()
        case .timeWindows: TimeWindowsCard()
        case .candlestick: CandlestickCard()
        case .states: StatesCard()
        case .paused: PausedCard()
        case .stale: StaleFeedCard()
        }
    }
}

// MARK: - Card chrome

private struct Card<Content: View>: View {
    let title: String
    let subtitle: String
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.headline)
            content()
                .frame(height: 220)
                .clipShape(RoundedRectangle(cornerRadius: 14))
            Text(subtitle).font(.caption).foregroundStyle(.secondary)
        }
    }
}

// MARK: - Feed models

/// Generates a backfill history ending at "now", so a chart opens populated
/// rather than building up from empty. Returns the points and the final value.
func seedSeries(center: Double, vol: Double, seconds: Double = 45) -> ([LivelinePoint], Double) {
    let now = Date().timeIntervalSince1970
    let hz = 5.0
    let n = Int(seconds * hz)
    var v = center
    var pts = [LivelinePoint]()
    pts.reserveCapacity(n)
    for i in 0..<n {
        v += (center - v) * 0.01 + Double.random(in: -vol...vol)
        pts.append(LivelinePoint(time: now - seconds + Double(i) / hz, value: v))
    }
    return (pts, v)
}

/// A mean-reverting random walk pushing values at 20 Hz. Models a data feed,
/// deliberately separate from the chart's own render loop. Starts from a
/// backfilled history so the chart is populated immediately.
final class Walk: ObservableObject {
    @Published var value: Double
    let seed: [LivelinePoint]
    private let center: Double
    private let vol: Double
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

    init(center: Double = 100, vol: Double = 0.9) {
        let (points, last) = seedSeries(center: center, vol: vol)
        self.seed = points
        self.value = last
        self.center = center
        self.vol = vol
        start()
    }

    private func start() {
        timer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            self?.step()
        }
    }

    private func step() {
        ticks += 1
        let elapsed = Double(ticks) * 0.05
        onTick?(elapsed)
        if let delay = feedDelaySeconds, elapsed < delay { return }
        if let stop = stopAfterSeconds, elapsed > stop { return }
        let drift = (center - value) * 0.01
        value += drift + Double.random(in: -vol...vol)
    }

    deinit { timer?.invalidate() }
}

// MARK: - Cards

private struct BasicCard: View {
    @StateObject private var walk = Walk()
    var body: some View {
        Card(title: "Basic", subtitle: "A live value. Two props: data and value.") {
            Liveline(data: walk.seed, value: walk.value)
        }
    }
}

private struct MomentumCard: View {
    @StateObject private var walk = Walk(vol: 1.2)
    var body: some View {
        Card(
            title: "Momentum",
            subtitle: "Directional chevrons on the live dot; the badge tints green up / red down."
        ) {
            Liveline(data: walk.seed, value: walk.value).momentum(.auto)
        }
    }
}

private struct ValueOverlayCard: View {
    @StateObject private var walk = Walk(center: 9800, vol: 24)
    var body: some View {
        Card(
            title: "Value overlay",
            subtitle: "showValue draws the live number over the chart; valueMomentumColor tints it."
        ) {
            Liveline(data: walk.seed, value: walk.value)
                .showValue()
                .valueMomentumColor()
                .formatValue { String(format: "$%.2f", $0) }
        }
    }
}

private struct ReferenceLineCard: View {
    @StateObject private var walk = Walk(center: 67_500, vol: 240)
    var body: some View {
        Card(title: "Reference line", subtitle: "A horizontal marker at a fixed value, kept in view.") {
            Liveline(data: walk.seed, value: walk.value)
                .color(Color(red: 0.55, green: 0.36, blue: 0.96))
                .referenceLine(ReferenceLine(value: 67_500, label: "Above $67,500"))
                .formatValue { String(format: "$%.0f", $0) }
        }
    }
}

private struct HeartRateCard: View {
    @StateObject private var walk = Walk(center: 62, vol: 0.4)
    var body: some View {
        Card(
            title: "Heart rate (exaggerate + formatter)",
            subtitle: "exaggerate tightens the Y-axis so tiny moves fill the height. Custom bpm formatter."
        ) {
            Liveline(data: walk.seed, value: walk.value)
                .color(Color(red: 0.9, green: 0.3, blue: 0.24))
                .exaggerate()
                .formatValue { String(format: "%.0f bpm", $0) }
        }
    }
}

private struct ThemingCard: View {
    @StateObject private var walk = Walk(center: 0, vol: 0.7)
    @State private var dark = true
    var body: some View {
        Card(title: "Theming", subtitle: "Any accent colour derives the full palette. Toggle light/dark.") {
            VStack(spacing: 8) {
                Picker("", selection: $dark) {
                    Text("Dark").tag(true)
                    Text("Light").tag(false)
                }
                .pickerStyle(.segmented)
                Liveline(data: walk.seed, value: walk.value)
                    .color(Color(red: 0.13, green: 0.7, blue: 0.67))
                    .theme(dark ? .dark : .light)
            }
        }
    }
}

/// Loading for 3 s, then the chart morphs into the (already backfilled) data —
/// the common real-world case where history exists behind a connecting state.
final class StatesModel: ObservableObject {
    @Published var value: Double
    @Published var loading = true
    let seed: [LivelinePoint]
    private var timer: Timer?
    private var t = 0.0

    init() {
        let (points, last) = seedSeries(center: 210, vol: 1.2)
        seed = points
        value = last
        timer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            self?.step()
        }
    }

    private func step() {
        t += 0.05
        if t >= 3 { loading = false }
        value += (210 - value) * 0.01 + Double.random(in: -1.2...1.2)
    }

    deinit { timer?.invalidate() }
}

private struct SurfaceCard: View {
    @StateObject private var walk = Walk(center: 100, vol: 0.9)
    var body: some View {
        Card(
            title: "Custom surface",
            subtitle: "Dark theme, but a purple-tinted surface via surfaceColor — independent of the accent."
        ) {
            Liveline(data: walk.seed, value: walk.value)
                .color(Color(red: 0.67, green: 0.62, blue: 0.95))  // #AB9FF2
                .theme(.dark)
                .surfaceColor(Color(red: 0.11, green: 0.08, blue: 0.18))  // #1c1530
        }
    }
}

private struct StatesCard: View {
    @StateObject private var model = StatesModel()
    var body: some View {
        Card(
            title: "States",
            subtitle: "loading shows a breathing line for 3s, then morphs into the backfilled chart."
        ) {
            Liveline(data: model.seed, value: model.value)
                .color(Color(red: 0.29, green: 0.68, blue: 0.4))
                .loading(model.loading)
        }
    }
}

/// Auto-toggles pause every 4 s while data keeps arriving, so the resume /
/// catch-up behaviour is observable without tapping.
final class PausedModel: ObservableObject {
    @Published var value: Double
    @Published var paused = false
    let seed: [LivelinePoint]
    private var timer: Timer?
    private var t = 0.0

    init() {
        let (points, last) = seedSeries(center: 160, vol: 1.0)
        seed = points
        value = last
        timer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            self?.step()
        }
    }

    private func step() {
        t += 0.05
        paused = t.truncatingRemainder(dividingBy: 8) >= 4
        value += (160 - value) * 0.01 + Double.random(in: -1.0...1.0)
    }

    deinit { timer?.invalidate() }
}

private struct PausedCard: View {
    @StateObject private var model = PausedModel()
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
            }
        }
    }
}

/// A slow ticker: one update every 4 s, like a low-volume asset. Liveline
/// interpolates between updates so it still scrolls smoothly.
final class SparseFeed: ObservableObject {
    @Published var value: Double
    let seed: [LivelinePoint]
    private var timer: Timer?

    init() {
        // A sparse backfill: one point every 4s.
        let now = Date().timeIntervalSince1970
        var v = 100.0
        var pts = [LivelinePoint]()
        for i in 0..<12 {
            v += Double.random(in: -5...5)
            pts.append(LivelinePoint(time: now - 48 + Double(i) * 4, value: v))
        }
        seed = pts
        value = v
        timer = Timer.scheduledTimer(withTimeInterval: 4.0, repeats: true) { [weak self] _ in
            self?.value += Double.random(in: -5...5)
        }
    }

    deinit { timer?.invalidate() }
}

private struct SparseCard: View {
    @StateObject private var feed = SparseFeed()
    var body: some View {
        Card(
            title: "Slow ticker",
            subtitle: "One update every 4s (a low-volume asset). It still scrolls smoothly between ticks."
        ) {
            Liveline(data: feed.seed, value: feed.value)
                .window(60)
                .color(Color(red: 0.55, green: 0.36, blue: 0.96))
        }
    }
}

private struct StaleFeedCard: View {
    @StateObject private var walk: Walk = {
        let w = Walk(center: 100, vol: 0.9)
        w.stopAfterSeconds = 6
        return w
    }()
    var body: some View {
        Card(
            title: "Stale feed",
            subtitle: "The feed stops after 6s. The chart keeps scrolling; the line runs flat to the edge."
        ) {
            Liveline(data: walk.seed, value: walk.value)
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
    private var price: Double = 150
    private var timer: Timer?

    init() {
        // Backfill ~18 historical candles so the chart opens populated.
        let cw = 3.0
        let liveBucket = (Date().timeIntervalSince1970 / cw).rounded(.down) * cw
        var p = 150.0
        var history = [LivelineCandle]()
        for i in 0..<18 {
            let open = p
            var hi = open
            var lo = open
            for _ in 0..<10 {
                p += Double.random(in: -1.8...1.8)
                hi = max(hi, p)
                lo = min(lo, p)
            }
            history.append(
                LivelineCandle(
                    time: liveBucket - cw * Double(18 - i), open: open, high: hi, low: lo, close: p))
        }
        candles = history
        price = p
        live = LivelineCandle(time: liveBucket, open: p, high: p, low: p, close: p)
        timer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            self?.step()
        }
    }

    private func step() {
        price += Double.random(in: -1.8...1.8)
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
    @StateObject private var walk = Walk(center: 87, vol: 0.85)
    var body: some View {
        Card(
            title: "Time windows",
            subtitle: "Tap a window to smoothly zoom the interval. Three styles via windowStyle."
        ) {
            Liveline(data: walk.seed, value: walk.value)
                .color(Color(red: 0.95, green: 0.6, blue: 0.1))
                .windows([
                    Window(label: "30s", secs: 30), Window(label: "1m", secs: 60),
                    Window(label: "5m", secs: 300),
                ])
                .windowStyle(.rounded)
                .formatValue { String(format: "%.0f%%", $0) }
        }
    }
}

private struct CandlestickCard: View {
    @StateObject private var feed = CandleFeed()
    @State private var candle = true
    var body: some View {
        Card(
            title: "Candlestick",
            subtitle: "OHLC candles with a live candle that grows its wicks. Toggle line / candle."
        ) {
            VStack(spacing: 8) {
                Picker("", selection: $candle) {
                    Text("Line").tag(false)
                    Text("Candle").tag(true)
                }
                .pickerStyle(.segmented)
                Liveline(value: feed.live.close)
                    .mode(candle ? .candle : .line)
                    .candles(feed.candles)
                    .liveCandle(feed.live)
                    .candleWidth(feed.candleWidth)
            }
        }
    }
}

#Preview {
    ContentView()
}
