#if canImport(UIKit)
    import CoreGraphics
    import UIKit

    @MainActor
    extension LivelineView {
        /// A short-lived spark thrown off by a degen burst.
        struct DegenParticle {
            var x: Double
            var y: Double
            var vx: Double
            var vy: Double
            var life: Double
            let maxLife: Double
        }

        /// Applies the decaying screen-shake and advances live particles. Called
        /// near the top of `draw(_:)`, before the chart content is rendered, so
        /// everything shakes together.
        func degenPreDraw(_ ctx: CGContext, dt: Double) {
            guard degen else {
                if !degenParticles.isEmpty { degenParticles.removeAll() }
                degenShake = 0
                return
            }
            // Decay the shake toward zero (frame-rate independent).
            degenShake *= pow(0.86, dt / Clock.frameMs)
            if degenShake < 0.2 { degenShake = 0 }
            if degenShake > 0 {
                ctx.translateBy(
                    x: CGFloat(Double.random(in: -degenShake...degenShake)),
                    y: CGFloat(Double.random(in: -degenShake...degenShake)))
            }
            // Advance particles: gravity, then integrate, then age out.
            let step = dt / 1000
            for i in degenParticles.indices {
                degenParticles[i].vy += 900 * step
                degenParticles[i].x += degenParticles[i].vx * step
                degenParticles[i].y += degenParticles[i].vy * step
                degenParticles[i].life -= step
            }
            degenParticles.removeAll { $0.life <= 0 }
        }

        /// Fires a burst (particles + shake + optional haptic) when the value pops
        /// up above its slowly-trailing baseline; re-arms once it settles. Called
        /// once the live-dot position is known.
        func degenTrigger(at dot: CGPoint, value: Double, range: Double, dt: Double) {
            guard degen else { return }
            if !degenBaselineInit {
                degenBaseline = value
                degenBaselineInit = true
            }
            // The baseline trails the value by ~0.5s; a fast rise above it bursts.
            degenBaseline += (value - degenBaseline) * min(1, 0.035 * dt / Clock.frameMs)
            let rise = range > 0 ? (value - degenBaseline) / range : 0
            if rise > 0.06, degenArmed {
                degenArmed = false
                spawnBurst(at: dot)
                degenShake = 7
                if haptics { heavyHaptic.impactOccurred(intensity: CGFloat(min(1, rise * 5))) }
            } else if rise < 0.02 {
                degenArmed = true
            }
        }

        private func spawnBurst(at dot: CGPoint) {
            for _ in 0..<18 {
                let angle = Double.random(in: -Double.pi ... 0)  // upward hemisphere
                let speed = Double.random(in: 120...340)
                let life = Double.random(in: 0.5...0.95)
                degenParticles.append(
                    DegenParticle(
                        x: Double(dot.x), y: Double(dot.y),
                        vx: cos(angle) * speed, vy: sin(angle) * speed,
                        life: life, maxLife: life))
            }
            if degenParticles.count > 200 { degenParticles.removeFirst(degenParticles.count - 200) }
        }

        /// Draws the live particles over the line. Called late, before the badge.
        func degenDrawParticles(_ ctx: CGContext) {
            guard degen, !degenParticles.isEmpty else { return }
            let spark = palette.line  // same colour as the line
            ctx.saveGState()
            for p in degenParticles {
                let t = max(0, p.life / p.maxLife)
                // Roughly the line's thickness, tapering as the spark fades.
                let r = lineWidth * CGFloat(0.4 + 0.5 * t)
                ctx.setFillColor(UIColor(rgba: spark.withAlpha(t * 0.9)).cgColor)
                ctx.fillEllipse(
                    in: CGRect(x: CGFloat(p.x) - r, y: CGFloat(p.y) - r, width: r * 2, height: r * 2))
            }
            ctx.restoreGState()
        }
    }
#endif
