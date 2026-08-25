#if canImport(UIKit)
import CoreGraphics
import UIKit

@MainActor
extension LivelineView {
    // MARK: Text helper

    func drawText(
        _ string: String,
        x: CGFloat,
        centerY: CGFloat,
        font: UIFont,
        color: RGBA,
        align: NSTextAlignment = .left,
        outline: RGBA? = nil
    ) {
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: UIColor(rgba: color),
        ]
        let ns = string as NSString
        let size = ns.size(withAttributes: attrs)
        let originX = align == .center ? x - size.width / 2 : x
        let point = CGPoint(x: originX, y: centerY - size.height / 2)
        if let outline {
            let outlineAttrs: [NSAttributedString.Key: Any] = [
                .font: font,
                .foregroundColor: UIColor.clear,
                .strokeColor: UIColor(rgba: outline),
                .strokeWidth: 8.0,
            ]
            ns.draw(at: point, withAttributes: outlineAttrs)
        }
        ns.draw(at: point, withAttributes: attrs)
    }

    func labelFont() -> UIFont { .monospacedSystemFont(ofSize: 11, weight: .regular) }
    func valueFont() -> UIFont { .monospacedSystemFont(ofSize: 11, weight: .medium) }
    func crosshairFont() -> UIFont { .monospacedSystemFont(ofSize: 13, weight: .regular) }

    // MARK: Spline path

    func splinePath(_ pts: [CGPoint]) -> CGMutablePath {
        let path = CGMutablePath()
        let segs = PathBuilder.monotoneSegments(pts)
        guard let first = segs.first else {
            if let p0 = pts.first {
                path.move(to: p0)
                for p in pts.dropFirst() { path.addLine(to: p) }
            }
            return path
        }
        path.move(to: first.start)
        for s in segs { path.addCurve(to: s.end, control1: s.control1, control2: s.control2) }
        return path
    }

    // MARK: Line + fill + dashed baseline

    /// Draws the fill, the stroked line, and the dashed current-value baseline.
    /// Returns the live-dot point (clamped into the canvas).
    func drawLineFillDash(
        _ ctx: CGContext,
        layout: Layout,
        visible: [LivelinePoint],
        smoothValue: Double,
        now: Double,
        scrubX: CGFloat?,
        reveal: Double,
        nowMs: Double
    ) -> CGPoint {
        let yMin = layout.padTop
        let yMax = layout.h - layout.padBottom
        func clampY(_ y: CGFloat) -> CGFloat { max(yMin, min(yMax, y)) }

        // Center-out reveal morph: at reveal < 1 the line traces the loading
        // squiggle and blooms outward from the middle into the real data.
        let centerY = layout.padTop + layout.chartH / 2
        let amplitude = Double(layout.chartH) * 0.07
        let scroll = nowMs * 0.001
        func morphY(_ rawY: CGFloat, _ x: CGFloat) -> CGFloat {
            if reveal >= 1 { return rawY }
            let t = min(max(Double((x - layout.padLeft) / layout.chartW), 0), 1)
            let centerDist = abs(t - 0.5) * 2
            let localReveal = min(max((reveal - centerDist * 0.4) / 0.6, 0), 1)
            let baseY =
                Double(centerY) + amplitude
                * (sin(t * 9.4 + scroll) * 0.55 + sin(t * 15.7 + scroll * 1.3) * 0.3
                    + sin(t * 4.2 + scroll * 0.7) * 0.15)
            return CGFloat(baseY) + (rawY - CGFloat(baseY)) * CGFloat(localReveal)
        }

        // Decimate to roughly one min/max pair per pixel column so a wide
        // window (e.g. 5m at 20 Hz ≈ thousands of points) costs the same to
        // draw as a narrow one, while preserving the line's shape (peaks/dips).
        let lastIndex = visible.count - 1
        var pts = [CGPoint]()
        let targetWidth = Int(layout.chartW)
        func project(_ p: LivelinePoint, isLast: Bool) -> CGPoint {
            let x = layout.toX(p.time)
            let v = isLast ? smoothValue : p.value
            return CGPoint(x: x, y: morphY(clampY(layout.toY(v)), x))
        }
        if targetWidth > 0, visible.count > targetWidth * 2 {
            var values = [Double]()
            values.reserveCapacity(visible.count)
            for p in visible { values.append(p.value) }
            let kept = Decimate.minMax(values: values, targetWidth: targetWidth)
            pts.reserveCapacity(kept.count + 1)
            for idx in kept { pts.append(project(visible[idx], isLast: idx == lastIndex)) }
        } else {
            pts.reserveCapacity(visible.count + 1)
            for (i, p) in visible.enumerated() { pts.append(project(p, isLast: i == lastIndex)) }
        }
        // Tip: at reveal 0 it extends to the full width (matching the loading
        // line); at reveal 1 it sits at the live dot.
        let liveTipX = layout.toX(now)
        let fullRightX = layout.padLeft + layout.chartW
        let tipX = reveal < 1 ? liveTipX + (fullRightX - liveTipX) * CGFloat(1 - reveal) : liveTipX
        pts.append(CGPoint(x: tipX, y: morphY(clampY(layout.toY(smoothValue)), tipX)))
        guard pts.count >= 2 else {
            return CGPoint(x: liveTipX, y: clampY(layout.toY(smoothValue)))
        }

        // Reveal alphas + colour: grey breathing squiggle at reveal 0, accent
        // line with fill by reveal ≈ 0.3+.
        let breath = 0.22 + 0.08 * sin(nowMs / 1200 * .pi)
        let lineAlpha = reveal < 1 ? breath + (1 - breath) * reveal : 1
        let fillAlpha = reveal
        let strokeColor: RGBA =
            reveal < 1 ? blend(palette.gridLabel, palette.line, min(1, reveal * 3)) : palette.line

        let chartRect = CGRect(
            x: layout.padLeft - 1, y: layout.padTop,
            width: layout.chartW + 2, height: layout.chartH
        )

        // Fill.
        if fill, fillAlpha > 0.01 {
            ctx.saveGState()
            ctx.addRect(chartRect)
            ctx.clip()
            let fillPath = CGMutablePath()
            fillPath.move(to: CGPoint(x: pts[0].x, y: yMax))
            fillPath.addLine(to: pts[0])
            let segs = PathBuilder.monotoneSegments(pts)
            for s in segs { fillPath.addCurve(to: s.end, control1: s.control1, control2: s.control2) }
            fillPath.addLine(to: CGPoint(x: pts[pts.count - 1].x, y: yMax))
            fillPath.closeSubpath()
            ctx.addPath(fillPath)
            ctx.clip()
            ctx.setAlpha(CGFloat(fillAlpha))
            let colors =
                [UIColor(rgba: palette.fillTop).cgColor, UIColor(rgba: palette.fillBottom).cgColor] as CFArray
            if let gradient = CGGradient(
                colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1]
            ) {
                ctx.drawLinearGradient(
                    gradient,
                    start: CGPoint(x: 0, y: layout.padTop),
                    end: CGPoint(x: 0, y: yMax),
                    options: []
                )
            }
            ctx.restoreGState()
        }

        // Line (with optional scrub dimming).
        let line = splinePath(pts)
        func strokeLine(alpha: CGFloat) {
            ctx.saveGState()
            ctx.addRect(chartRect)
            ctx.clip()
            ctx.addPath(line)
            ctx.setStrokeColor(
                UIColor(rgba: strokeColor.withAlpha(strokeColor.a * Double(alpha) * lineAlpha)).cgColor)
            ctx.setLineWidth(CGFloat(palette.lineWidth))
            ctx.setLineJoin(.round)
            ctx.setLineCap(.round)
            ctx.strokePath()
            ctx.restoreGState()
        }
        if let sx = scrubX {
            ctx.saveGState()
            ctx.clip(to: CGRect(x: 0, y: 0, width: sx, height: layout.h))
            strokeLine(alpha: 1)
            ctx.restoreGState()
            ctx.saveGState()
            ctx.clip(to: CGRect(x: sx, y: 0, width: layout.w - sx, height: layout.h))
            strokeLine(alpha: CGFloat(1 - scrubAmount * 0.6))
            ctx.restoreGState()
        } else {
            strokeLine(alpha: 1)
        }

        // Dashed current-value baseline (morphs from center, fades in).
        let realBaselineY = clampY(layout.toY(smoothValue))
        let baselineY = reveal < 1 ? centerY + (realBaselineY - centerY) * CGFloat(reveal) : realBaselineY
        ctx.saveGState()
        ctx.setLineDash(phase: 0, lengths: [4, 4])
        let dashScrub = scrubX != nil ? (1 - scrubAmount * 0.2) : 1
        let dashAlpha = palette.dashLine.a * dashScrub * (reveal < 1 ? reveal : 1)
        ctx.setStrokeColor(UIColor(rgba: palette.dashLine.withAlpha(dashAlpha)).cgColor)
        ctx.setLineWidth(1)
        ctx.move(to: CGPoint(x: layout.padLeft, y: baselineY))
        ctx.addLine(to: CGPoint(x: layout.w - layout.padRight, y: baselineY))
        ctx.strokePath()
        ctx.restoreGState()

        var dot = pts[pts.count - 1]
        dot.y = max(10, min(layout.h - 10, dot.y))
        return dot
    }

    // MARK: Grid

    func drawGrid(_ ctx: CGContext, layout: Layout, dt: Double, groupAlpha: Double) {
        let chartH = layout.chartH
        guard chartH > 0, layout.valRange > 0 else { return }
        let pxPerUnit = Double(chartH) / layout.valRange

        let coarse = Ticks.pickInterval(
            valRange: layout.valRange, pxPerUnit: pxPerUnit, minGap: 36, prev: gridInterval
        )
        gridInterval = coarse
        let fine = coarse / 2
        let finePx = fine * pxPerUnit
        let fineTarget = finePx < 40 ? 0 : (finePx >= 60 ? 1 : (finePx - 40) / 20)

        let fadeZone: CGFloat = 32
        func edgeAlpha(_ y: CGFloat) -> Double {
            let fromEdge = min(y - layout.padTop, layout.h - layout.padBottom - y)
            if fromEdge >= fadeZone { return 1 }
            if fromEdge <= 0 { return 0 }
            return Double(fromEdge / fadeZone)
        }

        // Targets.
        var targets = [Int: Double]()
        let first = (layout.minVal / fine).rounded(.up) * fine
        var val = first
        while val <= layout.maxVal {
            let y = layout.toY(val)
            if y >= layout.padTop - 2, y <= layout.h - layout.padBottom + 2 {
                let isCoarse = Ticks.divisible(val, by: coarse)
                let target = (isCoarse ? 1 : fineTarget) * edgeAlpha(y)
                targets[Int((val * 1000).rounded())] = target
            }
            val += fine
        }

        // Update tracked alphas.
        var alphas = gridAlphas
        for (key, alpha) in alphas {
            let target = targets[key] ?? 0
            let speed = target >= alpha ? K.gridFadeIn : K.gridFadeOut
            var next = Clock.lerp(current: alpha, target: target, speed: speed, dt: dt)
            if abs(next - target) < 0.02 { next = target }
            if next < 0.01, target == 0 { alphas[key] = nil } else { alphas[key] = next }
        }
        for (key, target) in targets where alphas[key] == nil {
            alphas[key] = target * K.gridFadeIn
        }
        gridAlphas = alphas

        // Draw.
        ctx.saveGState()
        ctx.setLineDash(phase: 0, lengths: [1, 3])
        ctx.setLineWidth(1)
        for (key, alpha) in gridAlphas where alpha >= 0.02 {
            let v = Double(key) / 1000
            let y = layout.toY(v)
            if y < layout.padTop - 10 || y > layout.h - layout.padBottom + 10 { continue }
            let lineA = palette.gridLine.a * alpha * groupAlpha
            ctx.setStrokeColor(UIColor(rgba: palette.gridLine.withAlpha(lineA)).cgColor)
            ctx.move(to: CGPoint(x: layout.padLeft, y: y))
            ctx.addLine(to: CGPoint(x: layout.w - layout.padRight, y: y))
            ctx.strokePath()
            drawText(
                formatValue(v), x: layout.w - layout.padRight + 8, centerY: y,
                font: labelFont(),
                color: palette.gridLabel.withAlpha(palette.gridLabel.a * alpha * groupAlpha)
            )
        }
        ctx.restoreGState()
    }

    // MARK: Time axis

    func drawTimeAxis(_ ctx: CGContext, layout: Layout, dt: Double, groupAlpha: Double) {
        let chartLeft = layout.padLeft
        let chartRight = layout.w - layout.padRight
        let chartW = chartRight - chartLeft
        let lineY = layout.h - layout.padBottom
        let tickLen: CGFloat = 5
        let fadeZone: CGFloat = 50

        func edgeAlpha(_ x: CGFloat) -> Double {
            let fromEdge = min(x - chartLeft, chartRight - x)
            if fromEdge >= fadeZone { return 1 }
            if fromEdge <= 0 { return 0 }
            return Double(fromEdge / fadeZone)
        }

        let targetPxPerSec = Double(chartW) / windowSeconds
        var interval = Intervals.niceTimeInterval(windowSecs: windowSeconds)
        while interval * targetPxPerSec < 60, interval < windowSeconds { interval *= 2 }

        let firstTime = ((layout.leftEdge - interval) / interval).rounded(.up) * interval
        var targetKeys = Set<Int>()
        var t = firstTime
        while t <= layout.rightEdge + interval, targetKeys.count < 30 {
            targetKeys.insert(Int((t * 100).rounded()))
            t += interval
        }

        var labels = timeAlphas
        for key in targetKeys {
            let text = axisTimeLabel(Double(key) / 100, interval: interval)
            if labels[key] == nil { labels[key] = (0, text) } else { labels[key]?.text = text }
        }
        for (key, label) in labels {
            let x = layout.toX(Double(key) / 100)
            let target = targetKeys.contains(key) ? edgeAlpha(x) : 0
            var next = Clock.lerp(current: label.alpha, target: target, speed: K.timeFade, dt: dt)
            if abs(next - target) < 0.02 { next = target }
            if next < 0.01, target == 0 { labels[key] = nil } else { labels[key]?.alpha = next }
        }
        timeAlphas = labels

        // Bottom axis line.
        ctx.setStrokeColor(UIColor(rgba: palette.gridLine.withAlpha(palette.gridLine.a * groupAlpha)).cgColor)
        ctx.setLineWidth(1)
        ctx.move(to: CGPoint(x: chartLeft, y: lineY))
        ctx.addLine(to: CGPoint(x: chartRight, y: lineY))
        ctx.strokePath()

        // Collect + resolve overlaps.
        struct L {
            var x: CGFloat
            var alpha: Double
            var text: String
            var w: CGFloat
        }
        var list = [L]()
        for (key, label) in timeAlphas where label.alpha >= 0.02 {
            let x = layout.toX(Double(key) / 100)
            if x < chartLeft - 20 || x > chartRight { continue }
            let width = (label.text as NSString).size(withAttributes: [.font: labelFont()]).width
            list.append(L(x: x, alpha: label.alpha, text: label.text, w: width))
        }
        list.sort { $0.x < $1.x }
        var drawn = [L]()
        for label in list {
            let left = label.x - label.w / 2
            if let prev = drawn.last {
                let prevRight = prev.x + prev.w / 2
                if left < prevRight + 8 {
                    if label.alpha > prev.alpha { drawn[drawn.count - 1] = label }
                    continue
                }
            }
            drawn.append(label)
        }

        for label in drawn {
            let a = label.alpha * groupAlpha
            ctx.setStrokeColor(UIColor(rgba: palette.gridLine.withAlpha(palette.gridLine.a * a)).cgColor)
            ctx.setLineWidth(1)
            ctx.move(to: CGPoint(x: label.x, y: lineY))
            ctx.addLine(to: CGPoint(x: label.x, y: lineY + tickLen))
            ctx.strokePath()
            drawText(
                label.text, x: label.x, centerY: lineY + tickLen + 10,
                font: labelFont(), color: palette.timeLabel.withAlpha(palette.timeLabel.a * a),
                align: .center
            )
        }
    }

    // MARK: Live dot

    func drawDot(_ ctx: CGContext, at p: CGPoint, showPulse: Bool, scrubDim: Double, nowMs: Double) {
        let dim = scrubDim * 0.7

        if showPulse, dim < 0.3 {
            let t = (nowMs.truncatingRemainder(dividingBy: 1500)) / 900
            if t < 1 {
                let radius = 9 + t * 12
                let pulseAlpha = 0.35 * (1 - t) * (1 - dim * 3)
                ctx.saveGState()
                ctx.setStrokeColor(UIColor(rgba: palette.line.withAlpha(palette.line.a * pulseAlpha)).cgColor)
                ctx.setLineWidth(1.5)
                ctx.addEllipse(
                    in: CGRect(x: p.x - radius, y: p.y - radius, width: radius * 2, height: radius * 2))
                ctx.strokePath()
                ctx.restoreGState()
            }
        }

        // White outer circle with shadow.
        ctx.saveGState()
        ctx.setShadow(
            offset: CGSize(width: 0, height: 1), blur: 6 * (1 - dim),
            color: UIColor(rgba: palette.badgeOuterShadow).cgColor
        )
        ctx.setFillColor(UIColor(rgba: palette.badgeOuterBg).cgColor)
        ctx.addEllipse(in: CGRect(x: p.x - 6.5, y: p.y - 6.5, width: 13, height: 13))
        ctx.fillPath()
        ctx.restoreGState()

        // Colored inner dot.
        let inner: RGBA = dim > 0.01 ? blend(palette.line, palette.badgeOuterBg, dim) : palette.line
        ctx.setFillColor(UIColor(rgba: inner).cgColor)
        ctx.addEllipse(in: CGRect(x: p.x - 3.5, y: p.y - 3.5, width: 7, height: 7))
        ctx.fillPath()
    }

    // MARK: Momentum arrows

    func drawArrows(_ ctx: CGContext, at p: CGPoint, trend: Trend, dt: Double, nowMs: Double) {
        let upTarget = trend == .up ? 1.0 : 0.0
        let downTarget = trend == .down ? 1.0 : 0.0
        let canFadeInUp = arrowDown < 0.02
        let canFadeInDown = arrowUp < 0.02
        var up = arrowUp
        var down = arrowDown
        up = Clock.lerp(
            current: up, target: canFadeInUp ? upTarget : 0, speed: upTarget > up ? 0.08 : 0.04, dt: dt)
        down = Clock.lerp(
            current: down, target: canFadeInDown ? downTarget : 0, speed: downTarget > down ? 0.08 : 0.04,
            dt: dt)
        if up < 0.01 { up = 0 }
        if down < 0.01 { down = 0 }
        if up > 0.99 { up = 1 }
        if down > 0.99 { down = 1 }
        arrowUp = up
        arrowDown = down

        let cycle = (nowMs.truncatingRemainder(dividingBy: 1400)) / 1400
        func chevrons(dir: CGFloat, opacity: Double) {
            if opacity < 0.01 { return }
            let baseX = p.x + 19
            ctx.saveGState()
            ctx.setLineWidth(2.5)
            ctx.setLineCap(.round)
            ctx.setLineJoin(.round)
            for i in 0..<2 {
                let start = Double(i) * 0.2
                let dur = 0.35
                let localT = cycle - start
                let wave = (localT >= 0 && localT < dur) ? sin((localT / dur) * .pi) : 0
                let pulse = 0.3 + 0.7 * wave
                let nudge: CGFloat = dir == -1 ? -3 : 3
                let cy = p.y + dir * (CGFloat(i) * 8 - 4) + nudge
                ctx.setStrokeColor(
                    UIColor(rgba: palette.gridLabel.withAlpha(palette.gridLabel.a * opacity * pulse)).cgColor)
                ctx.move(to: CGPoint(x: baseX - 5, y: cy - dir * 3.5))
                ctx.addLine(to: CGPoint(x: baseX, y: cy))
                ctx.addLine(to: CGPoint(x: baseX + 5, y: cy - dir * 3.5))
                ctx.strokePath()
            }
            ctx.restoreGState()
        }
        chevrons(dir: -1, opacity: up)
        chevrons(dir: 1, opacity: down)
    }

    // MARK: Badge

    func updateBadge(smoothValue: Double, layout: Layout, trend: Trend?, showMomentum: Bool, dt: Double) {
        let text = formatValue(smoothValue)
        let template = String(text.map { $0.isNumber ? "8" : $0 })
        let targetW = (template as NSString).size(withAttributes: [.font: valueFont()]).width
        if badgeDisplayW == 0 { badgeDisplayW = targetW }
        badgeDisplayW = CGFloat(
            Clock.lerp(
                current: Double(badgeDisplayW), target: Double(targetW), speed: K.badgeWidthLerp, dt: dt))
        if abs(badgeDisplayW - targetW) < 0.3 { badgeDisplayW = targetW }

        let pillH = K.badgeLineH + K.badgePadY * 2
        let targetY = max(layout.padTop, min(layout.h - layout.padBottom, layout.toY(smoothValue)))
        if !badgeYInited {
            badgeY = targetY
            badgeYInited = true
        } else {
            badgeY = CGFloat(
                Clock.lerp(current: Double(badgeY), target: Double(targetY), speed: K.badgeYLerp, dt: dt))
        }
        _ = pillH

        if showMomentum {
            let target = trend == .up ? 1.0 : (trend == .down ? 0.0 : badgeGreen)
            var g = Clock.lerp(current: badgeGreen, target: target, speed: K.momentumColorLerp, dt: dt)
            if g > 0.99 { g = 1 }
            if g < 0.01 { g = 0 }
            badgeGreen = g
        }
    }

    func drawBadge(_ ctx: CGContext, smoothValue: Double, layout: Layout, reveal: Double) {
        let tailLen: CGFloat = badgeTail ? K.badgeTailLen : 0
        let textW = badgeDisplayW
        let pillW = textW + K.badgePadX * 2
        let pillH = K.badgeLineH + K.badgePadY * 2
        let badgeLeft = layout.w - layout.padRight + 8 - K.badgePadX - tailLen
        let badgeTop = badgeY - pillH / 2

        let opacity: Double = reveal < 0.5 ? max(0, (reveal - 0.25) / 0.25) : 1

        // Pill shape.
        let path = UIBezierPath()
        if tailLen > 0 {
            let r = pillH / 2
            let cx = tailLen + pillW - r
            let tl = tailLen + r
            let spread = K.badgeTailSpread
            path.move(to: CGPoint(x: badgeLeft + tl, y: badgeTop))
            path.addLine(to: CGPoint(x: badgeLeft + cx, y: badgeTop))
            path.addArc(
                withCenter: CGPoint(x: badgeLeft + cx, y: badgeTop + r), radius: r,
                startAngle: -.pi / 2, endAngle: .pi / 2, clockwise: true
            )
            path.addLine(to: CGPoint(x: badgeLeft + tl, y: badgeTop + pillH))
            path.addCurve(
                to: CGPoint(x: badgeLeft, y: badgeTop + r),
                controlPoint1: CGPoint(x: badgeLeft + tailLen + 2, y: badgeTop + pillH),
                controlPoint2: CGPoint(x: badgeLeft + 3, y: badgeTop + r + spread)
            )
            path.addCurve(
                to: CGPoint(x: badgeLeft + tl, y: badgeTop),
                controlPoint1: CGPoint(x: badgeLeft + 3, y: badgeTop + r - spread),
                controlPoint2: CGPoint(x: badgeLeft + tailLen + 2, y: badgeTop)
            )
            path.close()
        } else {
            path.append(
                UIBezierPath(
                    roundedRect: CGRect(x: badgeLeft, y: badgeTop, width: pillW, height: pillH),
                    cornerRadius: pillH / 2
                ))
        }

        ctx.saveGState()
        ctx.setAlpha(CGFloat(opacity))

        let fillColor: RGBA
        let textColor: RGBA
        if badgeVariant == .minimal {
            fillColor = palette.badgeOuterBg
            textColor = palette.tooltipText
            ctx.setShadow(
                offset: CGSize(width: 0, height: 1), blur: 4,
                color: UIColor(rgba: palette.badgeOuterShadow).cgColor)
        } else {
            textColor = palette.badgeText
            if momentum == .off {
                fillColor = palette.line
            } else {
                let g = badgeGreen
                let red = LivelineView.momentumRedComponents
                let green = LivelineView.momentumGreenComponents
                fillColor = RGBA(
                    r255: red.0 + (green.0 - red.0) * g,
                    g255: red.1 + (green.1 - red.1) * g,
                    b255: red.2 + (green.2 - red.2) * g
                )
            }
        }
        ctx.setFillColor(UIColor(rgba: fillColor).cgColor)
        ctx.addPath(path.cgPath)
        ctx.fillPath()
        ctx.restoreGState()

        drawText(
            formatValue(smoothValue),
            x: badgeLeft + tailLen + K.badgePadX, centerY: badgeY,
            font: valueFont(), color: textColor.withAlpha(textColor.a * opacity)
        )
    }

    // MARK: Reference line

    func drawReferenceLine(_ ctx: CGContext, layout: Layout, ref: ReferenceLine) {
        let y = layout.toY(ref.value)
        if y < layout.padTop - 10 || y > layout.h - layout.padBottom + 10 { return }
        ctx.setLineWidth(1)
        if let label = ref.label, !label.isEmpty {
            let font = UIFont.systemFont(ofSize: 11, weight: .medium)
            let textW = (label as NSString).size(withAttributes: [.font: font]).width
            let centerX = layout.padLeft + layout.chartW / 2
            let gap: CGFloat = 8
            ctx.setStrokeColor(UIColor(rgba: palette.refLine).cgColor)
            ctx.move(to: CGPoint(x: layout.padLeft, y: y))
            ctx.addLine(to: CGPoint(x: centerX - textW / 2 - gap, y: y))
            ctx.strokePath()
            ctx.move(to: CGPoint(x: centerX + textW / 2 + gap, y: y))
            ctx.addLine(to: CGPoint(x: layout.w - layout.padRight, y: y))
            ctx.strokePath()
            drawText(label, x: centerX, centerY: y, font: font, color: palette.refLabel, align: .center)
        } else {
            ctx.saveGState()
            ctx.setLineDash(phase: 0, lengths: [4, 4])
            ctx.setStrokeColor(UIColor(rgba: palette.refLine).cgColor)
            ctx.move(to: CGPoint(x: layout.padLeft, y: y))
            ctx.addLine(to: CGPoint(x: layout.w - layout.padRight, y: y))
            ctx.strokePath()
            ctx.restoreGState()
        }
    }

    // MARK: Crosshair

    func drawCrosshair(
        _ ctx: CGContext, layout: Layout, hover: (x: CGFloat, value: Double, time: Double), opacity: Double,
        liveDotX: CGFloat
    ) {
        let y = layout.toY(hover.value)
        ctx.saveGState()
        ctx.setStrokeColor(
            UIColor(rgba: palette.crosshairLine.withAlpha(palette.crosshairLine.a * opacity * 0.5)).cgColor)
        ctx.setLineWidth(1)
        ctx.move(to: CGPoint(x: hover.x, y: layout.padTop))
        ctx.addLine(to: CGPoint(x: hover.x, y: layout.h - layout.padBottom))
        ctx.strokePath()
        ctx.restoreGState()

        let dotRadius = 4 * min(opacity * 3, 1)
        if dotRadius > 0.5 {
            ctx.setFillColor(UIColor(rgba: palette.line).cgColor)
            ctx.addEllipse(
                in: CGRect(
                    x: hover.x - CGFloat(dotRadius), y: y - CGFloat(dotRadius), width: CGFloat(dotRadius) * 2,
                    height: CGFloat(dotRadius) * 2))
            ctx.fillPath()
        }

        if opacity < 0.1 || layout.w < 300 { return }
        let valueText = formatValue(hover.value)
        let timeText = crosshairTimeLabel(hover.time)
        let full = valueText + "  ·  " + timeText
        let font = crosshairFont()
        let totalW = (full as NSString).size(withAttributes: [.font: font]).width
        var tx = hover.x - totalW / 2
        let minX = layout.padLeft + 4
        let maxX = liveDotX + 7 - totalW
        if tx < minX { tx = minX }
        if tx > maxX { tx = maxX }
        let ty = layout.padTop + 14 + 10
        drawText(
            valueText, x: tx, centerY: ty, font: font,
            color: palette.tooltipText.withAlpha(palette.tooltipText.a * opacity),
            align: .left, outline: palette.tooltipBg.withAlpha(palette.tooltipBg.a * opacity)
        )
        let valueW = (valueText as NSString).size(withAttributes: [.font: font]).width
        drawText(
            "  ·  " + timeText, x: tx + valueW, centerY: ty, font: font,
            color: palette.gridLabel.withAlpha(palette.gridLabel.a * opacity),
            align: .left, outline: palette.tooltipBg.withAlpha(palette.tooltipBg.a * opacity)
        )
    }

    // MARK: Loading / empty

    /// The no-data / loading waveform (unit amplitude): a few low-frequency sines
    /// summed and drifting, for a smooth, flowing line rather than a busy squiggle.
    /// Shared by the loading state and the reveal-morph so they match.
    func loadingWave(_ t: Double, _ scroll: Double) -> Double {
        sin(t * 3.1 + scroll) * 0.6
            + sin(t * 6.3 + scroll * 1.25) * 0.28
            + sin(t * 1.7 + scroll * 0.6) * 0.16
    }

    func drawLoading(
        _ ctx: CGContext, w: CGFloat, h: CGFloat,
        pad: (top: CGFloat, right: CGFloat, bottom: CGFloat, left: CGFloat), nowMs: Double, alpha: Double
    ) {
        let chartH = h - pad.top - pad.bottom
        let centerY = pad.top + chartH / 2
        let amplitude = Double(chartH) * 0.07
        let scroll = nowMs * 0.001
        let breath = 0.22 + 0.08 * sin(nowMs / 1200 * .pi)
        let left = pad.left
        let right = w - pad.right
        var pts = [CGPoint]()
        let steps = 64
        for i in 0...steps {
            let t = Double(i) / Double(steps)
            let x = left + CGFloat(t) * (right - left)
            let y =
                centerY + amplitude
                * (sin(t * 9.4 + scroll) * 0.55 + sin(t * 15.7 + scroll * 1.3) * 0.3 + sin(
                    t * 4.2 + scroll * 0.7) * 0.15)
            pts.append(CGPoint(x: x, y: CGFloat(y)))
        }
        ctx.addPath(splinePath(pts))
        ctx.setStrokeColor(UIColor(rgba: palette.line.withAlpha(breath * alpha)).cgColor)
        ctx.setLineWidth(CGFloat(palette.lineWidth))
        ctx.setLineJoin(.round)
        ctx.setLineCap(.round)
        ctx.strokePath()
    }

    func drawEmpty(
        _ ctx: CGContext, w: CGFloat, h: CGFloat,
        pad: (top: CGFloat, right: CGFloat, bottom: CGFloat, left: CGFloat), nowMs: Double, alpha: Double
    ) {
        let chartH = h - pad.top - pad.bottom
        let centerY = pad.top + chartH / 2
        // A gentle, slowly drifting wave rather than a dead-flat line.
        let amplitude = Double(chartH) * 0.05
        let scroll = nowMs * 0.0006
        let left = pad.left
        let right = w - pad.right
        var pts = [CGPoint]()
        let steps = 48
        for i in 0...steps {
            let t = Double(i) / Double(steps)
            let x = left + CGFloat(t) * (right - left)
            pts.append(CGPoint(x: x, y: CGFloat(centerY + amplitude * loadingWave(t, scroll))))
        }
        ctx.addPath(splinePath(pts))
        ctx.setStrokeColor(UIColor(rgba: palette.gridLine.withAlpha(palette.gridLine.a * alpha)).cgColor)
        ctx.setLineWidth(1)
        ctx.setLineJoin(.round)
        ctx.setLineCap(.round)
        ctx.strokePath()
        drawText(
            emptyText, x: w / 2, centerY: centerY - 16, font: labelFont(),
            color: palette.gridLabel.withAlpha(palette.gridLabel.a * alpha), align: .center
        )
    }

    // MARK: Left-edge fade

    /// Fades the line into the left edge by painting the background colour over
    /// it (opaque at `padLeft`, transparent 40pt later), blending the line into
    /// the chart surface. Using `destination-out` here would punch a hole
    /// through to whatever is behind the view (e.g. a white app background).
    func drawLeftEdgeFade(_ ctx: CGContext, w: CGFloat, h: CGFloat, padLeft: CGFloat) {
        let bg = palette.background
        let colors =
            [
                UIColor(rgba: bg.withAlpha(1)).cgColor,
                UIColor(rgba: bg.withAlpha(0)).cgColor,
            ] as CFArray
        guard
            let gradient = CGGradient(
                colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1])
        else { return }
        ctx.saveGState()
        ctx.clip(to: CGRect(x: 0, y: 0, width: padLeft + 40, height: h))
        ctx.drawLinearGradient(
            gradient,
            start: CGPoint(x: padLeft, y: 0),
            end: CGPoint(x: padLeft + 40, y: 0),
            options: [.drawsBeforeStartLocation]
        )
        ctx.restoreGState()
    }

    // MARK: Colour blend

    func blend(_ a: RGBA, _ b: RGBA, _ t: Double) -> RGBA {
        RGBA(
            r: a.r + (b.r - a.r) * t,
            g: a.g + (b.g - a.g) * t,
            b: a.b + (b.b - a.b) * t,
            a: a.a + (b.a - a.a) * t
        )
    }
}
#endif
