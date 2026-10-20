import AppKit

/// One entry from ~/.claude/sessions/<pid>.json, written by each running
/// Claude process. Internal file, so every field is read defensively.
struct RawSession {
    let pid: Int32
    let sessionId: String
    let name: String?
    let cwd: String
    let status: String
    let waitingFor: String?
    let hostSessionId: String?
    let updatedAt: Double
    let statusUpdatedAt: Double

    init?(url: URL) {
        guard let data = try? Data(contentsOf: url),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let pid = (obj["pid"] as? NSNumber)?.int32Value,
              let sid = obj["sessionId"] as? String else { return nil }
        if obj["spare"] as? Bool == true { return nil }

        self.pid = pid
        sessionId = sid
        name = (obj["name"] as? String).flatMap { $0.isEmpty ? nil : $0 }
        cwd = obj["cwd"] as? String ?? ""
        status = obj["status"] as? String ?? "idle"
        waitingFor = obj["waitingFor"] as? String
        hostSessionId = obj["hostSessionId"] as? String
        updatedAt = (obj["updatedAt"] as? NSNumber)?.doubleValue ?? 0
        statusUpdatedAt = (obj["statusUpdatedAt"] as? NSNumber)?.doubleValue ?? updatedAt
    }

    var isAlive: Bool { kill(pid, 0) == 0 || errno == EPERM }
}

@MainActor
final class SessionStore: ObservableObject {
    @Published private(set) var sessions: [CrewSession] = []

    /// Called when a task flips into "your turn" or "needs you".
    var onAlert: ((CrewSession) -> Void)?

    private let sessionsDir = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".claude/sessions", isDirectory: true)
    private let reader = ActivityReader()
    private let index = AppSessionIndex()
    /// Tasks untouched for longer than this drop off the list
    private let showWithin: TimeInterval = 48 * 3600
    /// Seen tasks quiet for longer than this fall asleep
    private let sleepAfter: TimeInterval = 3 * 3600
    private let needsYouCategories: Set<String> = ["need_input", "blocked", "failed"]
    private let acksKey = "acknowledged"

    private var timer: Timer?
    private var previous: [String: CrewState] = [:]
    private var firstLoad = true
    /// task id -> lastActivityAt you marked as seen from the island
    private var acks: [String: Double]

    init() {
        acks = UserDefaults.standard.dictionary(forKey: acksKey) as? [String: Double] ?? [:]
    }

    func start() {
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
    }

    func refresh() {
        CrewLooks.shared.reloadIfNeeded()
        let nowMs = Date().timeIntervalSince1970 * 1000

        var live: [String: RawSession] = [:]
        let files = (try? FileManager.default.contentsOfDirectory(at: sessionsDir, includingPropertiesForKeys: nil)) ?? []
        for url in files where url.pathExtension == "json" {
            guard let raw = RawSession(url: url), raw.isAlive else { continue }
            if let existing = live[raw.sessionId], existing.updatedAt >= raw.updatedAt { continue }
            live[raw.sessionId] = raw
        }
        var liveByHost: [String: RawSession] = [:]
        for r in live.values {
            if let host = r.hostSessionId { liveByHost[host] = r }
        }

        var out: [CrewSession] = []
        var matched = Set<String>()
        for app in index.recent(sinceMs: nowMs - showWithin * 1000, alwaysInclude: Set(liveByHost.keys)) {
            let r = liveByHost[app.id]
            if let r { matched.insert(r.sessionId) }
            out.append(makeSession(app: app, live: r, nowMs: nowMs))
        }
        // Running sessions the Claude app doesn't list, e.g. claude in Terminal
        for r in live.values where !matched.contains(r.sessionId) {
            out.append(makeSession(app: nil, live: r, nowMs: nowMs))
        }
        out.sort { a, b in a.state != b.state ? a.state < b.state : a.changedAtMs > b.changedAtMs }

        var next: [String: CrewState] = [:]
        var alert: CrewSession?
        for s in out {
            next[s.id] = s.state
            if !firstLoad, alert == nil, s.state.wantsYou, let prev = previous[s.id], !prev.wantsYou {
                alert = s
            }
        }
        previous = next
        firstLoad = false

        if out != sessions { sessions = out }
        if let alert { onAlert?(alert) }
    }

    func acknowledge(_ session: CrewSession) {
        acks[session.id] = session.changedAtMs
        saveAcks()
        refresh()
    }

    func acknowledgeAll() {
        for s in sessions where s.state.wantsYou { acks[s.id] = s.changedAtMs }
        saveAcks()
        refresh()
    }

    private func saveAcks() {
        let listed = Set(sessions.map(\.id))
        acks = acks.filter { listed.contains($0.key) }
        UserDefaults.standard.set(acks, forKey: acksKey)
    }

    private func makeSession(app: AppSession?, live: RawSession?, nowMs: Double) -> CrewSession {
        let cliId = live?.sessionId ?? app?.cliSessionId ?? app?.id ?? ""
        let id = app?.id ?? cliId
        let cwd = app?.cwd ?? live?.cwd ?? ""
        let home = app?.originCwd ?? cwd
        let info = reader.info(sessionId: cliId, cwd: cwd)

        let lastActivity = max(app?.lastActivityAt ?? 0, live?.statusUpdatedAt ?? 0)
        let seenAt = max(app?.lastFocusedAt ?? 0, acks[id] ?? 0)
        let unseen = lastActivity > seenAt + 1000
        let age = max(0, (nowMs - lastActivity) / 1000)

        let state: CrewState
        let detail: String
        var said = app?.statusDetail ?? info.said

        if live?.status == "waiting" {
            state = .needsYou
            detail = "Needs you: " + (live?.waitingFor ?? "your input")
        } else if live?.status == "busy" {
            state = .working
            detail = info.doing ?? "Working…"
            said = info.said ?? said
        } else if let cat = app?.statusCategory, needsYouCategories.contains(cat), unseen || age < sleepAfter {
            state = .needsYou
            if let action = app?.needsAction {
                detail = "Needs you: " + action
            } else {
                detail = cat == "failed" ? "Hit a problem" : "Needs your input"
            }
        } else if !info.hasHistory && app?.statusDetail == nil {
            state = .resting
            detail = "Ready when you are"
        } else if unseen {
            state = .yourTurn
            detail = age < 60 ? "Finished just now" : "Finished \(span(age)) ago"
        } else if age > sleepAfter {
            state = .asleep
            detail = "Quiet for \(span(age))"
        } else {
            state = .resting
            detail = "Idle for \(span(age))"
        }

        let project = (home as NSString).lastPathComponent
        return CrewSession(
            id: id,
            name: app?.title ?? live?.name ?? (project.isEmpty ? "Claude task" : project),
            cwd: home,
            hostSessionId: app?.id ?? live?.hostSessionId,
            state: state,
            changedAtMs: lastActivity,
            detail: detail,
            lastSaid: said,
            look: CrewLooks.shared.look(forProject: home)
        )
    }
}
