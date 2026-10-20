import Foundation

/// One task from the Claude app's own list
/// (~/Library/Application Support/Claude/claude-code-sessions/*/*/local_*.json).
/// Internal app files, read-only and read defensively.
struct AppSession {
    let id: String              // local_…, what the claude:// link wants
    let cliSessionId: String?   // transcript file name
    let title: String?
    let cwd: String
    let originCwd: String?
    let lastActivityAt: Double
    let lastFocusedAt: Double
    let statusCategory: String? // completed, need_input, blocked, failed
    let statusDetail: String?
    let needsAction: String?

    init?(url: URL) {
        guard let data = try? Data(contentsOf: url),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let id = obj["sessionId"] as? String else { return nil }
        if obj["isArchived"] as? Bool == true { return nil }

        func nonEmpty(_ v: Any?) -> String? {
            guard let s = v as? String, !s.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
            return s
        }
        self.id = id
        cliSessionId = nonEmpty(obj["cliSessionId"])
        title = nonEmpty(obj["title"])
        cwd = obj["cwd"] as? String ?? ""
        originCwd = nonEmpty(obj["originCwd"])
        lastActivityAt = (obj["lastActivityAt"] as? NSNumber)?.doubleValue ?? 0
        lastFocusedAt = (obj["lastFocusedAt"] as? NSNumber)?.doubleValue ?? 0
        let summary = obj["postTurnSummary"] as? [String: Any]
        statusCategory = nonEmpty(summary?["status_category"])
        statusDetail = nonEmpty(summary?["status_detail"])
        needsAction = nonEmpty(summary?["needs_action"])
    }
}

final class AppSessionIndex {
    private let root = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/Claude/claude-code-sessions", isDirectory: true)
    private var cache: [String: (mtime: Date, session: AppSession?)] = [:]

    /// Tasks active since `sinceMs`, plus any in `alwaysInclude`.
    func recent(sinceMs: Double, alwaysInclude: Set<String>) -> [AppSession] {
        let cutoff = Date(timeIntervalSince1970: sinceMs / 1000)
        guard let files = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.contentModificationDateKey],
                                                         options: [.skipsHiddenFiles]) else { return [] }
        var out: [AppSession] = []
        for case let url as URL in files {
            let name = url.lastPathComponent
            guard name.hasPrefix("local_"), url.pathExtension == "json" else { continue }
            let id = url.deletingPathExtension().lastPathComponent
            let mtime = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
            // Old files can't hold recent activity, so skip reading them
            if mtime < cutoff && !alwaysInclude.contains(id) { continue }

            let session: AppSession?
            if let c = cache[url.path], c.mtime == mtime {
                session = c.session
            } else {
                session = AppSession(url: url)
                cache[url.path] = (mtime, session)
            }
            guard let s = session else { continue }
            if s.lastActivityAt >= sinceMs || alwaysInclude.contains(s.id) { out.append(s) }
        }
        return out
    }
}
