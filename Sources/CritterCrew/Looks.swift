import AppKit
import SwiftUI

enum Accessory: String, CaseIterable {
    case hardHat, shades, antenna, beanie, crown, headphones, bow, partyHat, chefHat, flower, glasses, sprout, nightcap
}

struct CritterLook: Equatable {
    let hex: String
    let accessory: Accessory
    /// Keeps blinks out of sync between critters
    let seed: Int

    var color: Color { Color(hex: hex) }
}

/// Picks a critter for each project folder. Same folder, same critter.
/// Override any of them in ~/Library/Application Support/CritterCrew/crew.json:
/// { "my-website": { "color": "#FFB547", "accessory": "hardHat" } }
@MainActor
final class CrewLooks {
    static let shared = CrewLooks()

    static let palette = ["#FFB547", "#5AA9FF", "#5BE3A1", "#FF7EB6", "#A78BFA",
                          "#FF8A65", "#C6F36B", "#4FD1C5", "#FFE066", "#F472B6"]

    let fileURL: URL
    private var overrides: [String: CritterLook] = [:]
    private var loadedMtime: Date?

    private init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        fileURL = base.appendingPathComponent("CritterCrew/crew.json")
    }

    func look(forProject cwd: String) -> CritterLook {
        let key = (cwd as NSString).lastPathComponent
        if let o = overrides[key] { return o }
        return Self.defaultLook(for: cwd)
    }

    func reloadIfNeeded() {
        let attrs = try? FileManager.default.attributesOfItem(atPath: fileURL.path)
        let mtime = attrs?[.modificationDate] as? Date
        guard mtime != loadedMtime else { return }
        loadedMtime = mtime
        overrides = [:]

        guard let data = try? Data(contentsOf: fileURL),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }
        for (key, value) in obj {
            guard let v = value as? [String: Any] else { continue }
            let fallback = Self.defaultLook(for: key)
            overrides[key] = CritterLook(
                hex: v["color"] as? String ?? fallback.hex,
                accessory: (v["accessory"] as? String).flatMap(Accessory.init(rawValue:)) ?? fallback.accessory,
                seed: fallback.seed
            )
        }
    }

    /// Opens crew.json in TextEdit, creating it from the current crew if needed.
    func openFile(projects: [String]) {
        let fm = FileManager.default
        if !fm.fileExists(atPath: fileURL.path) {
            try? fm.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            var entries: [String] = []
            for cwd in Set(projects).sorted() {
                let key = (cwd as NSString).lastPathComponent
                let l = look(forProject: cwd)
                entries.append("  \"\(key)\": { \"color\": \"\(l.hex)\", \"accessory\": \"\(l.accessory.rawValue)\" }")
            }
            let body = "{\n" + entries.joined(separator: ",\n") + "\n}\n"
            try? body.write(to: fileURL, atomically: true, encoding: .utf8)
        }
        NSWorkspace.shared.open([fileURL],
                                withApplicationAt: URL(fileURLWithPath: "/System/Applications/TextEdit.app"),
                                configuration: NSWorkspace.OpenConfiguration())
    }

    private static func defaultLook(for key: String) -> CritterLook {
        let h = hash(key)
        return CritterLook(hex: palette[h % palette.count],
                           accessory: Accessory.allCases[(h / 13) % Accessory.allCases.count],
                           seed: h % 97)
    }

    /// FNV-1a, stable across launches (unlike hashValue)
    private static func hash(_ s: String) -> Int {
        var h: UInt64 = 0xcbf29ce484222325
        for b in s.utf8 {
            h ^= UInt64(b)
            h = h &* 0x100000001b3
        }
        return Int(h % 1_000_003)
    }
}
