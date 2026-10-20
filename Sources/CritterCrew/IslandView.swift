import SwiftUI

@MainActor
final class IslandUI: ObservableObject {
    enum Mode { case collapsed, expanded }

    @Published var mode: Mode = .collapsed
    @Published var selectedId: String?
    @Published var peek: CrewSession?
    @Published var bump = false
    @Published var notchSize = CGSize(width: 190, height: 32)

    let earRadius: CGFloat = 8
    let canvas = CGSize(width: 720, height: 280)
    let expandedWidth: CGFloat = 640
    let bodyHeight: CGFloat = 156
    let sideWidth: CGFloat = 72

    func islandSize(sessionCount: Int) -> CGSize {
        switch mode {
        case .expanded:
            let h = notchSize.height + (sessionCount == 0 ? 64 : bodyHeight + 24)
            return CGSize(width: expandedWidth + 2 * earRadius, height: h)
        case .collapsed:
            if sessionCount == 0 && peek == nil {
                return CGSize(width: notchSize.width + 2 * earRadius, height: notchSize.height)
            }
            var w = notchSize.width + 2 * sideWidth + 2 * earRadius
            var h = notchSize.height
            if peek != nil {
                w = max(w, 380)
                h += 32
            }
            return CGSize(width: w, height: h)
        }
    }
}

struct IslandActions {
    var open: @MainActor (CrewSession) -> Void
    var select: @MainActor (CrewSession) -> Void
    var minimize: @MainActor () -> Void
    var markAllSeen: @MainActor () -> Void
    var editCritters: @MainActor () -> Void
    var quit: @MainActor () -> Void
}

struct IslandView: View {
    @ObservedObject var store: SessionStore
    @ObservedObject var ui: IslandUI
    let actions: IslandActions

    private let spring = Animation.spring(response: 0.38, dampingFraction: 0.82)

    var body: some View {
        let size = ui.islandSize(sessionCount: store.sessions.count)
        ZStack(alignment: .top) {
            NotchShape(earRadius: ui.earRadius, bottomRadius: ui.mode == .expanded ? 24 : 12)
                .fill(Color.black)
            Group {
                if ui.mode == .expanded { expanded } else { collapsed }
            }
            .padding(.horizontal, ui.earRadius)
            .frame(width: size.width, height: size.height, alignment: .top)
            .clipped()
        }
        .frame(width: size.width, height: size.height)
        .scaleEffect(ui.bump ? 1.08 : 1, anchor: .top)
        .contextMenu {
            Button("Mark all as seen") { actions.markAllSeen() }
            Button("Edit critters…") { actions.editCritters() }
            Divider()
            Button("Quit Critter Crew") { actions.quit() }
        }
        .frame(width: ui.canvas.width, height: ui.canvas.height, alignment: .top)
        .animation(spring, value: ui.mode)
        .animation(spring, value: ui.peek?.id)
        .animation(spring, value: store.sessions.count)
        .animation(.spring(response: 0.16, dampingFraction: 0.45), value: ui.bump)
    }

    // MARK: collapsed

    private var collapsed: some View {
        let lead = ui.peek ?? store.sessions.first
        return VStack(spacing: 0) {
            HStack(spacing: 0) {
                if let lead {
                    CritterView(look: lead.look, state: lead.state, size: 26)
                }
                Spacer(minLength: ui.notchSize.width)
                badge
            }
            .padding(.horizontal, 12)
            .frame(height: ui.notchSize.height)

            if let p = ui.peek {
                HStack(spacing: 8) {
                    Text(p.name)
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    Text(p.state.label)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(p.state.color)
                }
                .padding(.horizontal, 16)
                .frame(height: 28)
                .transition(.opacity)
            }
        }
    }

    @ViewBuilder
    private var badge: some View {
        let needsYou = store.sessions.filter { $0.state == .needsYou }.count
        let wants = store.sessions.filter { $0.state.wantsYou }.count
        let working = store.sessions.filter { $0.state == .working }.count
        if wants > 0 {
            Text("\(wants)")
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundStyle(.black)
                .frame(minWidth: 20, minHeight: 20)
                .padding(.horizontal, wants > 9 ? 4 : 0)
                .background(Capsule().fill(needsYou > 0 ? CrewState.needsYou.color : CrewState.yourTurn.color))
        } else if working > 0 {
            HStack(spacing: 5) {
                PulseDot(color: CrewState.working.color)
                Text("\(working)")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color(hex: "#D1D1D6"))
            }
        } else if !store.sessions.isEmpty {
            Text("\(store.sessions.count)")
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(Color(hex: "#6E6E76"))
        }
    }

    // MARK: expanded

    private var expanded: some View {
        VStack(spacing: 10) {
            HStack {
                Text("Critter crew")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color(hex: "#C7C7CC"))
                Spacer(minLength: ui.notchSize.width + 24)
                Text(summary)
                    .font(.system(size: 11.5))
                    .foregroundStyle(Color(hex: "#8E8E96"))
                Button { actions.minimize() } label: {
                    Image(systemName: "minus")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(Color(hex: "#C7C7CC"))
                        .frame(width: 20, height: 20)
                        .background(Circle().fill(Color(hex: "#2C2C30")))
                }
                .buttonStyle(.plain)
                .help("Minimize")
                .padding(.leading, 6)
            }
            .padding(.horizontal, 18)
            .frame(height: ui.notchSize.height)

            if let featured {
                HStack(alignment: .top, spacing: 10) {
                    FeaturedCard(session: featured, open: actions.open)
                        .frame(width: 318, height: ui.bodyHeight)
                    Group {
                        if store.sessions.count > 4 {
                            ScrollView(.vertical, showsIndicators: false) { chips(featured: featured) }
                        } else {
                            chips(featured: featured)
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: ui.bodyHeight, alignment: .top)
                }
                .padding(.horizontal, 14)
            } else {
                HStack(spacing: 10) {
                    CritterView(look: CritterLook(hex: "#A8A3C7", accessory: .nightcap, seed: 1), state: .asleep, size: 40)
                    Text("No Claude tasks open")
                        .font(.system(size: 12.5))
                        .foregroundStyle(Color(hex: "#8E8E96"))
                }
            }
        }
    }

    private func chips(featured: CrewSession) -> some View {
        VStack(spacing: 6) {
            ForEach(store.sessions) { s in
                ChipView(session: s, selected: s.id == featured.id)
                    .onHover { inside in if inside { actions.select(s) } }
                    .onTapGesture { actions.open(s) }
            }
        }
    }

    private var featured: CrewSession? {
        store.sessions.first { $0.id == ui.selectedId } ?? store.sessions.first
    }

    private var summary: String {
        let s = store.sessions
        var parts: [String] = []
        let wants = s.filter { $0.state.wantsYou }.count
        let working = s.filter { $0.state == .working }.count
        if wants > 0 { parts.append("\(wants) need you") }
        if working > 0 { parts.append("\(working) working") }
        parts.append("\(s.count) open")
        return parts.joined(separator: " · ")
    }
}

struct FeaturedCard: View {
    let session: CrewSession
    let open: @MainActor (CrewSession) -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            CritterView(look: session.look, state: session.state, size: 84)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Circle().fill(session.state.color).frame(width: 7, height: 7)
                    Text(session.name)
                        .font(.system(size: 13.5, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                }
                Text("\(session.project) · \(session.state.label)")
                    .font(.system(size: 11))
                    .foregroundStyle(Color(hex: "#8E8E96"))
                    .lineLimit(1)
                Text("› " + session.detail)
                    .font(.system(size: 11.5))
                    .foregroundStyle(Color(hex: "#D1D1D6"))
                    .lineLimit(1)
                    .padding(.top, 4)
                if let said = session.lastSaid {
                    Text("› “\(said)”")
                        .font(.system(size: 11))
                        .foregroundStyle(Color(hex: "#7C7C84"))
                        .lineLimit(2)
                }
                Spacer(minLength: 0)
                Button { open(session) } label: {
                    HStack(spacing: 4) {
                        Text("Open")
                        Image(systemName: "arrow.up.right")
                    }
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 5)
                    .background(Capsule().fill(session.state.wantsYou ? session.state.color.opacity(0.3) : Color(hex: "#2C2C30")))
                }
                .buttonStyle(.plain)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color(hex: "#141416")))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Color(hex: "#2A2A2E"), lineWidth: 1))
    }
}

struct ChipView: View {
    let session: CrewSession
    let selected: Bool

    var body: some View {
        HStack(spacing: 8) {
            CritterView(look: session.look, state: session.state, size: 30, animated: session.state != .resting)
            Text(session.name)
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(Color(hex: "#E5E5EA"))
                .lineLimit(1)
            Spacer(minLength: 4)
            Circle().fill(session.state.color).frame(width: 7, height: 7)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color(hex: selected ? "#232327" : "#18181B")))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Color(hex: selected ? "#5E5E66" : "#2A2A2E"), lineWidth: 1))
        .contentShape(Rectangle())
    }
}

struct PulseDot: View {
    let color: Color

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 20.0)) { tl in
            let t = tl.date.timeIntervalSinceReferenceDate
            Circle()
                .fill(color)
                .frame(width: 7, height: 7)
                .opacity(0.45 + 0.55 * abs(sin(t * .pi / 1.1)))
        }
    }
}

/// Flat top with little inward "ears" so it melts into the menu bar,
/// rounded bottom corners like the notch.
struct NotchShape: Shape {
    var earRadius: CGFloat
    var bottomRadius: CGFloat

    var animatableData: CGFloat {
        get { bottomRadius }
        set { bottomRadius = newValue }
    }

    func path(in rect: CGRect) -> Path {
        let e = earRadius
        let r = max(0, min(bottomRadius, rect.height / 2, (rect.width - 2 * e) / 2))
        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: rect.minY))
        p.addArc(tangent1End: CGPoint(x: rect.minX + e, y: rect.minY),
                 tangent2End: CGPoint(x: rect.minX + e, y: rect.minY + e), radius: e)
        p.addArc(tangent1End: CGPoint(x: rect.minX + e, y: rect.maxY),
                 tangent2End: CGPoint(x: rect.maxX, y: rect.maxY), radius: r)
        p.addArc(tangent1End: CGPoint(x: rect.maxX - e, y: rect.maxY),
                 tangent2End: CGPoint(x: rect.maxX - e, y: rect.minY), radius: r)
        p.addArc(tangent1End: CGPoint(x: rect.maxX - e, y: rect.minY),
                 tangent2End: CGPoint(x: rect.maxX, y: rect.minY), radius: e)
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        p.closeSubpath()
        return p
    }
}
