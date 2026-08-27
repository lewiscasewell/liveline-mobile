#if canImport(UIKit)
import CoreGraphics
import UIKit

@MainActor
extension LivelineView {
    // MARK: Candle constants

    private enum CK {
        static let lerpSpeed = 0.25
        static let bullBlendSpeed = 0.12
        static let rangeSpeed = 0.15
        static let rangeBoost = 0.2
        static let buffer = 0.015
    }

    /// Bull (up) candle colour, `#22c55e`.
    var bull: RGBA { Theme.up }
    /// Bear (down) candle colour, `#ef4444`.
    var bear: RGBA { Theme.down }

    // MARK: Candle frame

    func drawCandleFrame(
        _ ctx: CGContext,
        w: CGFloat, h: CGFloat,
        pad: (top: CGFloat, right: CGFloat, bottom: CGFloat, left: CGFloat),
        now: Double, dt: Double, pausedDt: Double, nowMs: Double, modeProgress: Double = 1
    ) {
        let chartH = h - pad.top - pad.bottom
        let rightEdge = now + displayWindow * CK.buffer
        let leftEdge = rightEdge - displayWindow

        // Live candle OHLC easing.
        var smoothLive: LivelineCandle?
        if let raw = liveCandle {
            if displayCandle == nil || displayCandle?.time != raw.time {
                displayCandle = LivelineCandle(
                    time: raw.time, open: raw.open, high: raw.open, low: raw.open, close: raw.open)
            } else if var dc = displayCandle {
                dc.open = Clock.lerp(current: dc.open, target: raw.open, speed: CK.lerpSpeed, dt: pausedDt)
                dc.high = Clock.lerp(current: dc.high, target: raw.high, speed: CK.lerpSpeed, dt: pausedDt)
                dc.low = Clock.lerp(current: dc.low, target: raw.low, speed: CK.lerpSpeed, dt: pausedDt)
                dc.close = Clock.lerp(current: dc.close, target: raw.close, speed: CK.lerpSpeed, dt: pausedDt)
                displayCandle = dc
            }
            if let dc = displayCandle {
                let bullTarget = dc.close >= dc.open ? 1.0 : 0.0
                liveBull = Clock.lerp(
                    current: liveBull, target: bullTarget, speed: CK.bullBlendSpeed, dt: pausedDt)
                liveBull = min(max(liveBull, 0), 1)
                smoothLive = dc
            }
        } else {
            displayCandle = nil
            liveBull = 0.5
        }

        // Visible candles: static (backfill) + those aggregated from live pushes.
        var visible = [LivelineCandle]()
        visible.reserveCapacity(candles.count + liveCandles.count + 1)
        for c in candles where c.time + candleWidth >= leftEdge && c.time <= rightEdge {
            visible.append(c)
        }
        for c in liveCandles where c.time + candleWidth >= leftEdge && c.time <= rightEdge {
            visible.append(c)
        }
        if let sl = smoothLive, sl.time + candleWidth >= leftEdge, sl.time <= rightEdge {
            visible.append(sl)
        }
        guard !visible.isEmpty else { return }

        // Range easing (candle uses high/low extent, adaptive speed).
        let target = AutoRange.computeCandles(visible)
        let curRange = domain.valRange
        let gap = (abs(domain.minVal - target.min) + abs(domain.maxVal - target.max)) / curRange
        let speed = CK.rangeSpeed + (1 - min(gap, 1)) * CK.rangeBoost
        domain.update(target: target, speed: speed, dt: dt, chartH: Double(chartH))

        let layout = Layout(
            w: w, h: h, padTop: pad.top, padRight: pad.right, padBottom: pad.bottom, padLeft: pad.left,
            chartW: w - pad.left - pad.right, chartH: chartH,
            leftEdge: leftEdge, rightEdge: rightEdge,
            minVal: domain.minVal, maxVal: domain.maxVal, valRange: domain.valRange
        )

        let reveal = chartReveal
        func revealRamp(_ start: Double, _ end: Double) -> Double {
            let t = min(max((reveal - start) / (end - start), 0), 1)
            return t * t * (3 - 2 * t)
        }

        // 1. Grid.
        if grid {
            let a = reveal < 1 ? revealRamp(0.25, 0.6) : 1
            if a > 0.01 { drawGrid(ctx, layout: layout, dt: dt, groupAlpha: a) }
        }

        // 2. Dashed close-price line.
        if let sl = smoothLive {
            drawCandleClosePrice(ctx, layout: layout, candle: sl, scrubDim: scrubAmount)
        }

        // 3. Candles.
        let scrubX: CGFloat = scrubAmount > 0.05 ? (hoverX ?? -1) : -1
        ctx.saveGState()
        ctx.clip(
            to: CGRect(x: pad.left - 1, y: pad.top, width: layout.chartW + 2, height: chartH))
        drawCandlesticks(
            ctx, layout: layout, candles: visible,
            liveTime: smoothLive?.time ?? -Double.greatestFiniteMagnitude,
            nowMs: nowMs, scrubX: scrubX, scrubDim: scrubAmount, grow: modeProgress)
        // Fade the line out over the growing candles during the morph.
        if modeProgress < 1 {
            drawLineOverlay(ctx, layout: layout, now: now, alpha: (1 - modeProgress) * reveal)
        }
        ctx.restoreGState()

        // 4. Time axis.
        do {
            let a = reveal < 1 ? revealRamp(0.25, 0.6) : 1
            if a > 0.01 { drawTimeAxis(ctx, layout: layout, dt: dt, groupAlpha: a) }
        }

        // 5. Left-edge fade.
        drawLeftEdgeFade(ctx, w: w, h: h, padLeft: pad.left)

        // 6. Crosshair (OHLC).
        if scrubAmount > 0.01, let hx = hoverX,
            let candle = candleAt(x: hx, layout: layout, visible: visible)
        {
            drawCandleCrosshair(ctx, layout: layout, hoverX: hx, candle: candle, opacity: scrubAmount)
        }

        // 7. Live value overlays — dot, momentum arrows, badge and value label,
        //    the same as line mode (they persist for candlesticks). The live
        //    value is the forming candle's close, else the last visible close.
        let liveValue = smoothLive?.close ?? visible.last?.close ?? domain.minVal
        let smoothValue = liveValue
        let trend = resolveTrend()
        let showMomentum = momentum != .off
        let dotY = max(pad.top, min(h - pad.bottom, layout.toY(smoothValue)))
        let dotPoint = CGPoint(x: layout.toX(now), y: dotY)

        if showMomentum, let trend {
            drawArrows(ctx, at: dotPoint, trend: trend, dt: dt, nowMs: nowMs)
        }
        if badge, reveal >= 0.25 {
            updateBadge(
                smoothValue: smoothValue, layout: layout, trend: trend, showMomentum: showMomentum, dt: dt)
            drawBadge(ctx, smoothValue: smoothValue, layout: layout, reveal: reveal)
        }
        updateValueLabel(value: smoothValue, trend: trend ?? .flat, pad: pad)

        // Scrub easing.
        let scrubTarget = isHovering ? 1.0 : 0.0
        scrubAmount += (scrubTarget - scrubAmount) * 0.12
        if scrubAmount < 0.01 { scrubAmount = 0 }
        if scrubAmount > 0.99 { scrubAmount = 1 }
    }

    // MARK: Candle drawing

    private func candleDims(_ layout: Layout) -> (bodyW: CGFloat, wickW: CGFloat, radius: CGFloat) {
        let pxPerSec = layout.chartW / CGFloat(layout.rightEdge - layout.leftEdge)
        let candlePxW = CGFloat(candleWidth) * pxPerSec
        let bodyW = max(1, candlePxW * 0.7)
        let wickW = max(0.8, min(2, bodyW * 0.15))
        let radius: CGFloat = bodyW > 6 ? 1.5 : 0
        return (bodyW, wickW, radius)
    }

    private func candleColor(_ c: LivelineCandle, isLive: Bool) -> RGBA {
        if isLive { return blend(bear, bull, liveBull) }
        return c.close >= c.open ? bull : bear
    }

    func drawCandlesticks(
        _ ctx: CGContext, layout: Layout, candles: [LivelineCandle],
        liveTime: Double, nowMs: Double, scrubX: CGFloat, scrubDim: Double, grow: Double = 1
    ) {
        let dims = candleDims(layout)
        let halfBody = dims.bodyW / 2
        let padL = layout.padLeft
        let padR = layout.padLeft + layout.chartW
        let livePulse = 0.12 + sin(nowMs * 0.004) * 0.08
        let growF = CGFloat(min(max(grow, 0), 1))

        for c in candles {
            let cx = layout.toX(c.time + candleWidth / 2)
            if cx + halfBody < padL || cx - halfBody > padR { continue }
            let isLive = c.time == liveTime
            let color = candleColor(c, isLive: isLive)

            var alpha = 1.0
            if scrubDim > 0.01, scrubX > 0 {
                let dist = cx - scrubX
                if dist > 0 {
                    let fadeZone = dims.bodyW * 1.5
                    let dimT = min(dist / fadeZone, 1)
                    alpha *= 1 - scrubDim * 0.5 * Double(dimT)
                }
            }
            let drawColor = color.withAlpha(color.a * alpha)

            // Grow each candle out of its close as the line→candle morph plays.
            let baseY = layout.toY(c.close)
            func grown(_ y: CGFloat) -> CGFloat { baseY + (y - baseY) * growF }
            let bodyTop = grown(layout.toY(max(c.open, c.close)))
            let bodyBottom = grown(layout.toY(min(c.open, c.close)))
            let bodyH = max(1, bodyBottom - bodyTop)
            let wickTop = grown(layout.toY(c.high))
            let wickBottom = grown(layout.toY(c.low))

            ctx.setStrokeColor(UIColor(rgba: drawColor).cgColor)
            ctx.setLineCap(.round)
            ctx.setLineWidth(dims.wickW)
            if bodyTop - wickTop > 0.5 {
                ctx.move(to: CGPoint(x: cx, y: bodyTop))
                ctx.addLine(to: CGPoint(x: cx, y: wickTop))
                ctx.strokePath()
            }
            if wickBottom - bodyBottom > 0.5 {
                ctx.move(to: CGPoint(x: cx, y: bodyBottom))
                ctx.addLine(to: CGPoint(x: cx, y: wickBottom))
                ctx.strokePath()
            }

            let bodyRect = CGRect(x: cx - halfBody, y: bodyTop, width: dims.bodyW, height: bodyH)
            let bodyPath =
                dims.radius > 0 && bodyH >= dims.radius * 2
                ? CGPath(
                    roundedRect: bodyRect, cornerWidth: dims.radius, cornerHeight: dims.radius, transform: nil
                )
                : CGPath(rect: bodyRect, transform: nil)
            ctx.setFillColor(UIColor(rgba: drawColor).cgColor)
            ctx.addPath(bodyPath)
            ctx.fillPath()

            if isLive {
                ctx.saveGState()
                ctx.setShadow(offset: .zero, blur: 8, color: UIColor(rgba: color).cgColor)
                ctx.setFillColor(UIColor(rgba: color.withAlpha(color.a * alpha * livePulse)).cgColor)
                ctx.addPath(bodyPath)
                ctx.fillPath()
                ctx.restoreGState()
            }
        }
    }

    private func drawCandleClosePrice(
        _ ctx: CGContext, layout: Layout, candle: LivelineCandle, scrubDim: Double
    ) {
        let y = layout.toY(candle.close)
        if y < layout.padTop || y > layout.h - layout.padBottom { return }
        let color = blend(bear, bull, liveBull)
        ctx.saveGState()
        ctx.setLineDash(phase: 0, lengths: [4, 4])
        ctx.setStrokeColor(UIColor(rgba: color.withAlpha((1 - scrubDim * 0.3) * 0.4)).cgColor)
        ctx.setLineWidth(1)
        ctx.move(to: CGPoint(x: layout.padLeft, y: y))
        ctx.addLine(to: CGPoint(x: layout.w - layout.padRight, y: y))
        ctx.strokePath()
        ctx.restoreGState()
    }

    private func candleAt(x: CGFloat, layout: Layout, visible: [LivelineCandle]) -> LivelineCandle? {
        let time =
            layout.leftEdge
            + Double((x - layout.padLeft) / layout.chartW) * (layout.rightEdge - layout.leftEdge)
        for c in visible where time >= c.time && time < c.time + candleWidth {
            return c
        }
        return nil
    }

    private func drawCandleCrosshair(
        _ ctx: CGContext, layout: Layout, hoverX: CGFloat, candle: LivelineCandle, opacity: Double
    ) {
        ctx.saveGState()
        ctx.setStrokeColor(
            UIColor(rgba: palette.crosshairLine.withAlpha(palette.crosshairLine.a * opacity * 0.5)).cgColor)
        ctx.setLineWidth(1)
        ctx.move(to: CGPoint(x: hoverX, y: layout.padTop))
        ctx.addLine(to: CGPoint(x: hoverX, y: layout.h - layout.padBottom))
        ctx.strokePath()
        ctx.restoreGState()

        if opacity < 0.1 || layout.w < 200 { return }
        let valueColor = candle.close >= candle.open ? bull : bear
        let font = crosshairFont()
        let time = crosshairTimeLabel(candle.time)
        // Condensed O H L C · time.
        let segs: [(String, RGBA)] = [
            ("O ", palette.gridLabel), (formatValue(candle.open), valueColor),
            (" H ", palette.gridLabel), (formatValue(candle.high), valueColor),
            (" L ", palette.gridLabel), (formatValue(candle.low), valueColor),
            (" C ", palette.gridLabel), (formatValue(candle.close), valueColor),
            (" · ", palette.gridLabel), (time, palette.gridLabel),
        ]
        var widths = [CGFloat]()
        var total: CGFloat = 0
        for s in segs {
            let ww = (s.0 as NSString).size(withAttributes: [.font: font]).width
            widths.append(ww)
            total += ww
        }
        var tx = hoverX - total / 2
        let minX = layout.padLeft + 4
        // The readout sits above the plot (clear of the badge), so it may use the
        // full width. Clamp the right edge first, then the left — so when the label
        // is wider than the screen the left wins and the prices stay visible (only
        // the trailing time clips), never the High on the left.
        let maxX = layout.w - 12 - total
        tx = min(tx, maxX)
        tx = max(tx, minX)
        let ty = layout.padTop + 24
        var ox = tx
        for (i, s) in segs.enumerated() {
            drawText(
                s.0, x: ox, centerY: ty, font: font, color: s.1.withAlpha(s.1.a * opacity),
                align: .left, outline: palette.tooltipBg.withAlpha(palette.tooltipBg.a * opacity))
            ox += widths[i]
        }
    }
}
#endif
