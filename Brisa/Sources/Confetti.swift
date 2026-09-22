import SwiftUI
import AppKit

/// One piece of confetti. Its position is a closed-form function of time (drag plus gravity), so any frame can be drawn on its own.
struct ConfettiParticle {
    var x0: Double, y0: Double
    var vx: Double, vy: Double
    var drag: Double
    var delay: Double
    var width: Double, height: Double
    var color: Color
    var rotation: Double, spin: Double
    var flipRate: Double, flipPhase: Double
    var swayAmount: Double, swayRate: Double, swayPhase: Double
    var isCircle: Bool

    func position(at t: Double) -> CGPoint {
        let decay = exp(-drag * t)
        let terminal = ConfettiField.gravity / drag
        let x = x0 + vx * (1 - decay) / drag + swayAmount * sin(swayRate * t + swayPhase) * (1 - decay)
        let y = y0 + terminal * t + (vy - terminal) * (1 - decay) / drag
        return CGPoint(x: x, y: y)
    }
}

/// A burst of confetti fired from the bottom corners and the bottom center, like a party popper.
struct ConfettiField {
    static let duration = 4.6
    static let gravity = 560.0
    static let palette: [Color] = [
        Color(red: 1.00, green: 0.36, blue: 0.42), Color(red: 1.00, green: 0.72, blue: 0.20),
        Color(red: 0.98, green: 0.90, blue: 0.30), Color(red: 0.32, green: 0.85, blue: 0.55),
        Color(red: 0.30, green: 0.72, blue: 1.00), Color(red: 0.62, green: 0.48, blue: 1.00),
        Color(red: 1.00, green: 0.50, blue: 0.85)
    ]

    let size: CGSize
    let particles: [ConfettiParticle]

    init(size: CGSize, accent: Color, seed: UInt64 = 20260920) {
        self.size = size
        var rng = SplitMix64(seed: seed)
        let colors = ConfettiField.palette + [accent, accent]
        // Scale launch speed with the screen so the burst reaches a similar fraction of any display.
        let scale = min(max(size.height / 900, 0.6), 1.7)
        var all: [ConfettiParticle] = []

        func emit(count: Int, originX: Double, angle: ClosedRange<Double>, speed: ClosedRange<Double>, delay: Double) {
            for _ in 0..<count {
                let theta = Double.random(in: angle, using: &rng) * .pi / 180
                let v = Double.random(in: speed, using: &rng) * scale
                let circle = Double.random(in: 0...1, using: &rng) < 0.18
                let w = Double.random(in: 7...13, using: &rng)
                all.append(ConfettiParticle(
                    x0: originX + Double.random(in: -14...14, using: &rng), y0: size.height + 12,
                    vx: cos(theta) * v, vy: -sin(theta) * v,
                    drag: Double.random(in: 1.7...3.0, using: &rng),
                    delay: delay + Double.random(in: 0...0.22, using: &rng),
                    width: circle ? w * 0.7 : w, height: circle ? w * 0.7 : w * Double.random(in: 0.45...0.8, using: &rng),
                    color: colors[Int.random(in: 0..<colors.count, using: &rng)],
                    rotation: Double.random(in: 0...(2 * .pi), using: &rng), spin: Double.random(in: -9...9, using: &rng),
                    flipRate: Double.random(in: 5...13, using: &rng), flipPhase: Double.random(in: 0...(2 * .pi), using: &rng),
                    swayAmount: Double.random(in: 6...26, using: &rng), swayRate: Double.random(in: 2...5, using: &rng),
                    swayPhase: Double.random(in: 0...(2 * .pi), using: &rng),
                    isCircle: circle))
            }
        }

        emit(count: 130, originX: 0, angle: 38...82, speed: 1300...3300, delay: 0)
        emit(count: 130, originX: size.width, angle: 98...142, speed: 1300...3300, delay: 0)
        emit(count: 90, originX: size.width / 2, angle: 62...118, speed: 1200...2900, delay: 0.3)
        particles = all
    }

    func draw(into context: inout GraphicsContext, elapsed: Double) {
        for particle in particles {
            let t = elapsed - particle.delay
            guard t > 0 else { continue }
            let alpha = min(max((ConfettiField.duration - elapsed) / 0.9, 0), 1)
            guard alpha > 0 else { continue }
            let p = particle.position(at: t)
            guard p.y < size.height + 80 else { continue }

            let flip = cos(particle.flipRate * t + particle.flipPhase)
            let brightness = 0.72 + 0.28 * abs(flip)
            var layer = context
            layer.opacity = alpha
            layer.translateBy(x: p.x, y: p.y)
            layer.rotate(by: .radians(particle.rotation + particle.spin * t))
            layer.scaleBy(x: 1, y: max(abs(flip), 0.12))
            let rect = CGRect(x: -particle.width / 2, y: -particle.height / 2, width: particle.width, height: particle.height)
            let path = particle.isCircle ? Path(ellipseIn: rect) : Path(roundedRect: rect, cornerRadius: 1.5)
            layer.fill(path, with: .color(particle.color.opacity(brightness)))
        }
    }
}

struct ConfettiOverlay: View {
    let field: ConfettiField
    let start: Date

    var body: some View {
        TimelineView(.animation) { timeline in
            Canvas { context, _ in
                field.draw(into: &context, elapsed: timeline.date.timeIntervalSince(start))
            }
        }
        .allowsHitTesting(false)
    }
}

/// Small deterministic generator so the same burst can be reproduced in tests.
struct SplitMix64: RandomNumberGenerator {
    private var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
}

/// Plays the confetti over every screen in click-through windows, then removes them.
@MainActor
final class PomodoroCelebration {
    static let shared = PomodoroCelebration()
    private var panels: [NSPanel] = []
    private var generation = 0

    func play() {
        // Confetti is all motion; people who reduce motion still get the chime and the notification.
        guard !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else { return }
        dismiss()
        generation += 1
        let current = generation
        let start = Date()
        let accent = BrisaThemeStore.shared.current.accent

        for screen in NSScreen.screens {
            let panel = NSPanel(contentRect: screen.frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            panel.isReleasedWhenClosed = false
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.hasShadow = false
            panel.ignoresMouseEvents = true
            panel.hidesOnDeactivate = false
            panel.level = .screenSaver
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
            let field = ConfettiField(size: screen.frame.size, accent: accent, seed: UInt64.random(in: 1...UInt64.max))
            panel.contentView = NSHostingView(rootView: ConfettiOverlay(field: field, start: start))
            panel.setFrame(screen.frame, display: false)
            panel.orderFrontRegardless()
            panels.append(panel)
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + ConfettiField.duration + 0.4) { [weak self] in
            guard let self, self.generation == current else { return }
            self.dismiss()
        }
    }

    private func dismiss() {
        panels.forEach { $0.orderOut(nil) }
        panels.removeAll()
    }
}
