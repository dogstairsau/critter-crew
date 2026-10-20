import SwiftUI

enum CrewState: Int, Comparable {
    case needsYou, yourTurn, working, resting, asleep

    static func < (lhs: CrewState, rhs: CrewState) -> Bool { lhs.rawValue < rhs.rawValue }

    var label: String {
        switch self {
        case .needsYou: return "Needs you"
        case .yourTurn: return "Your turn"
        case .working: return "Working"
        case .resting: return "Resting"
        case .asleep: return "Asleep"
        }
    }

    var color: Color {
        switch self {
        case .needsYou: return Color(hex: "#FF5A4E")
        case .yourTurn: return Color(hex: "#FFB547")
        case .working: return Color(hex: "#5BE3A1")
        case .resting: return Color(hex: "#8E8E96")
        case .asleep: return Color(hex: "#5E5E66")
        }
    }

    var wantsYou: Bool { self == .needsYou || self == .yourTurn }
}

struct CrewSession: Identifiable, Equatable {
    let id: String
    let name: String
    let cwd: String
    let hostSessionId: String?
    let state: CrewState
    let changedAtMs: Double
    let detail: String
    let lastSaid: String?
    let look: CritterLook

    var project: String { (cwd as NSString).lastPathComponent }
}

extension Color {
    init(hex: String) {
        var s = hex.trimmingCharacters(in: .whitespaces)
        if s.hasPrefix("#") { s.removeFirst() }
        let v = UInt64(s, radix: 16) ?? 0x888888
        self.init(.sRGB,
                  red: Double((v >> 16) & 0xFF) / 255,
                  green: Double((v >> 8) & 0xFF) / 255,
                  blue: Double(v & 0xFF) / 255,
                  opacity: 1)
    }
}

/// "13 min", "2 hrs", "1 day"
func span(_ seconds: TimeInterval) -> String {
    let s = max(0, Int(seconds))
    switch s {
    case ..<60: return "under a min"
    case ..<3600: return "\(s / 60) min"
    case ..<86_400:
        let h = s / 3600
        return h == 1 ? "1 hr" : "\(h) hrs"
    default:
        let d = s / 86_400
        return d == 1 ? "1 day" : "\(d) days"
    }
}
