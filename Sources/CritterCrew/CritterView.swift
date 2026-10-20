import SwiftUI

private struct CritterClockKey: EnvironmentKey {
    static let defaultValue: Double? = nil
}

extension EnvironmentValues {
    /// A fixed animation time, for rendering frames (e.g. a video) instead of live
    var critterClock: Double? {
        get { self[CritterClockKey.self] }
        set { self[CritterClockKey.self] = newValue }
    }
}

/// A blob critter. Drawn on a 64x60 grid: body sits at y 22-56, hats above it.
struct CritterView: View {
    let look: CritterLook
    let state: CrewState
    var size: CGFloat = 40
    var animated = true

    @Environment(\.critterClock) private var clock

    var body: some View {
        Group {
            if let clock {
                canvas(t: animated ? clock : 0)
            } else {
                TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: !animated)) { timeline in
                    canvas(t: animated ? timeline.date.timeIntervalSinceReferenceDate : 0)
                }
            }
        }
        .frame(width: size, height: size * 60 / 64)
    }

    private func canvas(t: Double) -> some View {
        Canvas { gc, canvasSize in
            let s = canvasSize.width / 64
            gc.scaleBy(x: s, y: s)
            CritterPainter(look: look, state: state, t: t).paint(&gc)
        }
    }
}

struct CritterPainter {
    let look: CritterLook
    let state: CrewState
    let t: Double

    private let ink = Color(hex: "#111111")

    func paint(_ gc: inout GraphicsContext) {
        if state == .asleep { paintZs(gc) }

        var g = gc
        g.translateBy(x: 0, y: bounce)
        if state == .asleep { g.opacity = 0.6 }
        paintBody(g)
        paintFace(g)
        paintAccessory(g)
        paintBubble(g)
    }

    // MARK: motion

    private var bounce: CGFloat {
        switch state {
        case .needsYou: return -CGFloat(abs(sin(t * .pi / 0.38))) * 5
        case .yourTurn: return -CGFloat(abs(sin(t * .pi / 0.6))) * 4
        case .working: return -CGFloat(abs(sin(t * .pi / 0.3))) * 1.2
        default: return 0
        }
    }

    private var blink: CGFloat {
        let phase = (t + Double(look.seed) * 0.37).truncatingRemainder(dividingBy: 4.2)
        return phase < 0.12 ? 0.15 : 1
    }

    // MARK: parts

    private func paintBody(_ g: GraphicsContext) {
        let body = Path(roundedRect: CGRect(x: 8, y: 22, width: 48, height: 34), cornerRadius: 16, style: .continuous)
        g.fill(body, with: .color(look.color))
        g.fill(Path(ellipseIn: CGRect(x: 15, y: 26, width: 10, height: 5)), with: .color(.white.opacity(0.3)))
        let cheek = Color(hex: "#FF6B8A").opacity(0.35)
        g.fill(Path(ellipseIn: CGRect(x: 15, y: 44, width: 7, height: 4)), with: .color(cheek))
        g.fill(Path(ellipseIn: CGRect(x: 42, y: 44, width: 7, height: 4)), with: .color(cheek))
    }

    private func paintFace(_ g: GraphicsContext) {
        if look.accessory == .shades { return } // shades cover the eyes

        if state == .asleep {
            var p = Path()
            p.move(to: CGPoint(x: 22, y: 39))
            p.addQuadCurve(to: CGPoint(x: 30, y: 39), control: CGPoint(x: 26, y: 42.5))
            p.move(to: CGPoint(x: 34, y: 39))
            p.addQuadCurve(to: CGPoint(x: 42, y: 39), control: CGPoint(x: 38, y: 42.5))
            g.stroke(p, with: .color(ink), style: StrokeStyle(lineWidth: 2.2, lineCap: .round))
            return
        }

        let dx: CGFloat = state == .working ? CGFloat(sin(t * 2 * .pi / 0.7)) * 1.6 : 0
        let h = 8 * blink
        for cx in [26.0, 38.0] {
            g.fill(Path(ellipseIn: CGRect(x: cx - 2.8 + dx, y: 39 - h / 2, width: 5.6, height: h)), with: .color(ink))
        }
    }

    private func paintBubble(_ g: GraphicsContext) {
        let circle = Path(ellipseIn: CGRect(x: 2, y: 13, width: 15, height: 15))
        switch state {
        case .needsYou:
            g.fill(circle, with: .color(Color(hex: "#FF5A4E")))
            g.stroke(circle, with: .color(.black), lineWidth: 1.5)
            g.fill(Path(roundedRect: CGRect(x: 8.6, y: 15.8, width: 1.8, height: 6.4), cornerRadius: 0.9), with: .color(.white))
            g.fill(Path(ellipseIn: CGRect(x: 8.5, y: 23.2, width: 2, height: 2)), with: .color(.white))
        case .yourTurn:
            g.fill(circle, with: .color(Color(hex: "#3B82F6")))
            g.stroke(circle, with: .color(.black), lineWidth: 1.5)
            for x in [6.3, 9.5, 12.7] {
                g.fill(Path(ellipseIn: CGRect(x: x - 1.1, y: 19.4, width: 2.2, height: 2.2)), with: .color(.white))
            }
        default:
            break
        }
    }

    private func paintZs(_ gc: GraphicsContext) {
        for i in 0..<2 {
            let phase = (t / 2.4 + Double(i) * 0.5).truncatingRemainder(dividingBy: 1)
            var g = gc
            g.opacity = sin(phase * .pi)
            let z = Text("z")
                .font(.system(size: 8 + phase * 4, weight: .heavy, design: .rounded))
                .foregroundColor(Color(hex: "#9A9AA3"))
            g.draw(z, at: CGPoint(x: 51 + phase * 7, y: 19 - phase * 14))
        }
    }

    // MARK: accessories

    private func paintAccessory(_ g: GraphicsContext) {
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x, y: y) }
        func fill(_ path: Path, _ hex: String) { g.fill(path, with: .color(Color(hex: hex))) }
        func outline(_ path: Path, _ width: CGFloat = 1.4) { g.stroke(path, with: .color(ink), lineWidth: width) }
        func dot(_ x: CGFloat, _ y: CGFloat, _ r: CGFloat) -> Path { Path(ellipseIn: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2)) }

        switch look.accessory {
        case .hardHat:
            var dome = Path()
            dome.move(to: p(15, 24))
            dome.addQuadCurve(to: p(49, 24), control: p(32, 3))
            dome.closeSubpath()
            fill(dome, "#FFD400"); outline(dome)
            var ridge = Path()
            ridge.move(to: p(32, 10)); ridge.addLine(to: p(32, 22))
            g.stroke(ridge, with: .color(Color(hex: "#E0B000")), lineWidth: 2.4)
            let brim = Path(roundedRect: CGRect(x: 11, y: 21.5, width: 42, height: 4.5), cornerRadius: 2.2)
            fill(brim, "#FFD400"); outline(brim)

        case .shades:
            fill(Path(roundedRect: CGRect(x: 18, y: 35, width: 12, height: 7.5), cornerRadius: 2.5), "#111111")
            fill(Path(roundedRect: CGRect(x: 34, y: 35, width: 12, height: 7.5), cornerRadius: 2.5), "#111111")
            fill(Path(CGRect(x: 29.5, y: 37, width: 5, height: 2)), "#111111")
            fill(Path(roundedRect: CGRect(x: 20, y: 36.5, width: 4, height: 1.4), cornerRadius: 0.7), "#FFFFFF")
            fill(Path(roundedRect: CGRect(x: 36, y: 36.5, width: 4, height: 1.4), cornerRadius: 0.7), "#FFFFFF")

        case .antenna:
            var stalk = Path()
            stalk.move(to: p(32, 22)); stalk.addLine(to: p(32, 11))
            g.stroke(stalk, with: .color(ink), lineWidth: 2)
            var bulb = g
            if state == .working { bulb.opacity = 0.55 + 0.45 * abs(sin(t * .pi / 0.5)) }
            bulb.fill(dot(32, 9, 3.4), with: .color(Color(hex: "#FF5F7E")))

        case .beanie:
            var dome = Path()
            dome.move(to: p(13, 27))
            dome.addQuadCurve(to: p(51, 27), control: p(32, 1))
            dome.closeSubpath()
            fill(dome, "#E5484D")
            fill(Path(roundedRect: CGRect(x: 12, y: 21, width: 40, height: 7), cornerRadius: 3.5), "#B5383C")
            fill(dot(32, 7, 4), "#FFFFFF")

        case .crown:
            var c = Path()
            c.addLines([p(18, 25), p(17, 11), p(24.5, 17.5), p(32, 7), p(39.5, 17.5), p(47, 11), p(46, 25)])
            c.closeSubpath()
            fill(c, "#FFD54A"); outline(c, 1.2)
            fill(dot(32, 19.5, 2), "#FF5F7E")

        case .headphones:
            var band = Path()
            band.move(to: p(11, 36))
            band.addQuadCurve(to: p(53, 36), control: p(32, -6))
            g.stroke(band, with: .color(Color(hex: "#2A2A2E")), lineWidth: 3.2)
            fill(Path(roundedRect: CGRect(x: 5, y: 31, width: 9, height: 13), cornerRadius: 3.5), "#3A3A40")
            fill(Path(roundedRect: CGRect(x: 50, y: 31, width: 9, height: 13), cornerRadius: 3.5), "#3A3A40")

        case .bow:
            var left = Path()
            left.addLines([p(46, 22), p(38, 15), p(38, 29)]); left.closeSubpath()
            var right = Path()
            right.addLines([p(46, 22), p(54, 15), p(54, 29)]); right.closeSubpath()
            fill(left, "#FF5FA2"); outline(left, 1)
            fill(right, "#FF5FA2"); outline(right, 1)
            fill(dot(46, 22, 2.6), "#E0428A")

        case .partyHat:
            var cone = Path()
            cone.addLines([p(22, 25), p(42, 25), p(32, 4)]); cone.closeSubpath()
            fill(cone, "#7C5CFF")
            fill(dot(29.5, 18, 1.6), "#FFFFFF")
            fill(dot(34.5, 12, 1.4), "#FFFFFF")
            fill(dot(32, 4, 3), "#FFD400")

        case .chefHat:
            fill(dot(24, 13, 7), "#FFFFFF")
            fill(dot(32, 10, 8), "#FFFFFF")
            fill(dot(40, 13, 7), "#FFFFFF")
            fill(Path(CGRect(x: 22, y: 13, width: 20, height: 9)), "#FFFFFF")
            fill(Path(roundedRect: CGRect(x: 21, y: 19, width: 22, height: 4.5), cornerRadius: 1.5), "#E3E3E8")

        case .flower:
            var stem = Path()
            stem.move(to: p(41, 23))
            stem.addQuadCurve(to: p(44, 11), control: p(46, 18))
            g.stroke(stem, with: .color(Color(hex: "#3E9B4F")), lineWidth: 2)
            for i in 0..<5 {
                let a = Double(i) / 5 * 2 * .pi
                fill(dot(44 + CGFloat(cos(a)) * 4, 9 + CGFloat(sin(a)) * 4, 3.2), "#FF8FB1")
            }
            fill(dot(44, 9, 2.4), "#FFD45C")

        case .glasses:
            outline(dot(26, 39, 6), 1.8)
            outline(dot(38, 39, 6), 1.8)
            var arms = Path()
            arms.move(to: p(20, 38)); arms.addLine(to: p(10, 36))
            arms.move(to: p(44, 38)); arms.addLine(to: p(54, 36))
            outline(arms, 1.6)

        case .sprout:
            var stem = Path()
            stem.move(to: p(32, 22)); stem.addLine(to: p(32, 12))
            g.stroke(stem, with: .color(Color(hex: "#3E9B4F")), lineWidth: 2)
            var leftLeaf = Path()
            leftLeaf.move(to: p(32, 13))
            leftLeaf.addQuadCurve(to: p(21, 8), control: p(25, 15))
            leftLeaf.addQuadCurve(to: p(32, 13), control: p(26, 4))
            var rightLeaf = Path()
            rightLeaf.move(to: p(32, 13))
            rightLeaf.addQuadCurve(to: p(43, 8), control: p(39, 15))
            rightLeaf.addQuadCurve(to: p(32, 13), control: p(38, 4))
            fill(leftLeaf, "#6DCB5A")
            fill(rightLeaf, "#6DCB5A")

        case .nightcap:
            var cap = Path()
            cap.move(to: p(14, 25))
            cap.addQuadCurve(to: p(40, 8), control: p(18, 8))
            cap.addQuadCurve(to: p(55, 17), control: p(52, 6))
            cap.addLine(to: p(50, 25))
            cap.closeSubpath()
            fill(cap, "#4B4FA8")
            fill(Path(roundedRect: CGRect(x: 12, y: 21, width: 40, height: 6), cornerRadius: 3), "#FFFFFF")
            fill(dot(55, 17, 3.5), "#FFFFFF")
        }
    }
}
