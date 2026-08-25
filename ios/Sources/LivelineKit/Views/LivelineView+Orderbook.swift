#if canImport(UIKit)
    import CoreGraphics
    import UIKit

    /// Orderbook streaming labels. When an ``OrderbookData`` snapshot is set, the
    /// render loop emits resting sizes as small `+$` labels that spawn near the
    /// bottom-left, drift straight upward behind the price line and fade out —
    /// bids in the up-colour, asks in the down-colour, bigger orders brighter. The
    /// stream speed reacts to price momentum and orderbook churn (how fast the
    /// bid/ask totals are changing): calm markets drift slowly, volatile ones rush.
    @MainActor
    extension LivelineView {
        /// One streaming label in flight (a fixed column position, rising over time).
        /// All labels share one global rise speed, so the column moves uniformly;
        /// `yOffset` is the accumulated upward drift in points.
        struct OrderbookFloatLabel {
            let text: String
            let x: CGFloat  // fixed column x (screen)
            let spawnY: CGFloat  // starting y near the chart bottom
            let isBid: Bool
            let weight: Double  // 0…1 by size (brightness)
            var yOffset: CGFloat = 0
        }

        var hasOrderbook: Bool {
            guard let book = orderbook else { return false }
            return !(book.bids.isEmpty && book.asks.isEmpty)
        }

        /// Sets (or clears) the current book. Also folds the change in total depth
        /// into an eased churn signal. Emission happens in the render loop.
        public func setOrderbook(_ data: OrderbookData?) {
            if let d = data {
                let total = d.bids.reduce(0) { $0 + $1.size } + d.asks.reduce(0) { $0 + $1.size }
                if orderbookLastTotal >= 0, total > 0 {
                    let inst = min(1, abs(total - orderbookLastTotal) / total * 5)
                    orderbookChurn = orderbookChurn * 0.6 + inst * 0.4
                }
                orderbookLastTotal = total
            }
            orderbook = data
            setNeedsDisplay()
        }

        /// Emits new labels on an activity-scaled cadence, then advances and draws
        /// the ones in flight. `momentumMag` (0…1) is the price momentum.
        func advanceAndDrawOrderbook(
            _ ctx: CGContext, layout: Layout, dt: Double, momentumMag: Double, groupAlpha: Double
        ) {
            // `dt` arrives in milliseconds; the physics here is in seconds.
            let dtSec = dt / 1000
            let activity = min(1, max(0, momentumMag * 0.5 + orderbookChurn * 0.8))

            if let book = orderbook, dtSec > 0 {
                orderbookSpawnClock += dtSec
                let interval = 0.26 - 0.16 * activity  // calm → busy
                var guardCount = 0
                while orderbookSpawnClock >= interval, guardCount < 4 {
                    orderbookSpawnClock -= interval
                    guardCount += 1
                    emitOrderbookLabels(from: book, layout: layout, activity: activity)
                }
            }
            guard !orderbookLabels.isEmpty else { return }

            // One global rise speed for every label (calm drifts, volatile rushes),
            // so the column moves uniformly rather than each label at its own pace.
            let travel = layout.chartH + 24
            let driftPerSec = 60.0 + 90.0 * activity
            let step = CGFloat(driftPerSec * dtSec)
            for i in orderbookLabels.indices { orderbookLabels[i].yOffset += step }
            orderbookLabels.removeAll { $0.yOffset >= travel }
            guard !orderbookLabels.isEmpty else { return }

            let font = chartFont(size: 11, weight: .semibold)
            for lab in orderbookLabels {
                let progress = Double(lab.yOffset / travel)
                let y = lab.spawnY - lab.yOffset
                let fadeIn = min(1, progress / 0.08)
                let fadeOut = 1 - max(0, (progress - 0.7) / 0.3)
                let alpha = max(0, min(1, fadeIn * fadeOut)) * (0.28 + 0.5 * lab.weight) * groupAlpha
                if alpha < 0.01 { continue }
                let color = (lab.isBid ? Theme.up : Theme.down).withAlpha(alpha)
                drawText(lab.text, x: lab.x, centerY: y, font: font, color: color, align: .left)
            }
        }

        private func emitOrderbookLabels(from book: OrderbookData, layout: Layout, activity: Double) {
            // One label per cycle, side chosen at random, so they stack as a single
            // interleaved column rather than colliding bid-over-ask.
            let preferBid = Bool.random()
            let isBid = (preferBid && !book.bids.isEmpty) || book.asks.isEmpty
            let levels = isBid ? book.bids : book.asks
            let top = Array(levels.prefix(8))
            guard let pick = top.randomElement() else { return }
            let maxSize = top.map(\.size).max() ?? 1
            let weight = maxSize > 0 ? min(1, pick.size / maxSize) : 0.5
            // A fixed left edge so the column reads as a clean left-aligned stream.
            let x = layout.padLeft + 6
            let spawnY = layout.padTop + layout.chartH - 6
            orderbookLabels.append(
                OrderbookFloatLabel(
                    text: "+$" + Self.formatSize(pick.size),
                    x: x, spawnY: spawnY, isBid: isBid, weight: weight))
            if orderbookLabels.count > 40 {
                orderbookLabels.removeFirst(orderbookLabels.count - 40)
            }
        }

        /// Compact size formatting: `1.2k`, `3.4M`, `43` (≥10) or `9.3` (<10).
        static func formatSize(_ s: Double) -> String {
            if s >= 1_000_000 { return String(format: "%.1fM", s / 1_000_000) }
            if s >= 1_000 { return String(format: "%.1fk", s / 1_000) }
            if s >= 10 { return String(format: "%.0f", s) }
            return String(format: "%.1f", s)
        }
    }
#endif
