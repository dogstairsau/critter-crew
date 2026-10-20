import Foundation

struct ActivityInfo {
    /// What Claude is doing right now, e.g. "Editing index.html"
    var doing: String?
    /// First line of Claude's latest reply
    var said: String?
    var hasHistory = false
}

/// Reads the tail of each session's transcript (~/.claude/projects/*/<id>.jsonl)
/// to describe what it's up to. Results are cached until the file changes.
final class ActivityReader {
    private let projectsDir = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".claude/projects", isDirectory: true)
    private var paths: [String: URL] = [:]
    private var cache: [String: (size: UInt64, mtime: Date, info: ActivityInfo)] = [:]

    func info(sessionId: String, cwd: String) -> ActivityInfo {
        guard let url = transcript(sessionId: sessionId, cwd: cwd),
              let attrs = try? FileManager.default.attributesOfItem(atPath: url.path) else { return ActivityInfo() }
        let size = (attrs[.size] as? NSNumber)?.uint64Value ?? 0
        let mtime = attrs[.modificationDate] as? Date ?? .distantPast
        if let c = cache[sessionId], c.size == size, c.mtime == mtime { return c.info }

        let small: UInt64 = 512 * 1024
        var info = parse(url, maxBytes: small)
        if info.doing == nil || info.said == nil, size > small {
            let more = parse(url, maxBytes: 4 * 1024 * 1024)
            info.doing = info.doing ?? more.doing
            info.said = info.said ?? more.said
            info.hasHistory = info.hasHistory || more.hasHistory
        }
        cache[sessionId] = (size, mtime, info)
        return info
    }

    private func transcript(sessionId: String, cwd: String) -> URL? {
        if let p = paths[sessionId] { return p }
        let fm = FileManager.default
        let slug = String(cwd.map { $0.isASCII && ($0.isLetter || $0.isNumber) ? $0 : "-" })
        let direct = projectsDir.appendingPathComponent(slug).appendingPathComponent("\(sessionId).jsonl")
        if fm.fileExists(atPath: direct.path) {
            paths[sessionId] = direct
            return direct
        }
        let dirs = (try? fm.contentsOfDirectory(at: projectsDir, includingPropertiesForKeys: nil)) ?? []
        for d in dirs {
            let f = d.appendingPathComponent("\(sessionId).jsonl")
            if fm.fileExists(atPath: f.path) {
                paths[sessionId] = f
                return f
            }
        }
        return nil
    }

    private func parse(_ url: URL, maxBytes: UInt64) -> ActivityInfo {
        var info = ActivityInfo()
        guard let fh = try? FileHandle(forReadingFrom: url) else { return info }
        defer { try? fh.close() }

        let size = (try? fh.seekToEnd()) ?? 0
        let start = size > maxBytes ? size - maxBytes : 0
        try? fh.seek(toOffset: start)
        guard let data = try? fh.readToEnd(), !data.isEmpty else { return info }

        var lines = data.split(separator: UInt8(ascii: "\n"))
        if start > 0, !lines.isEmpty { lines.removeFirst() } // partial line

        for line in lines.reversed() {
            guard let obj = try? JSONSerialization.jsonObject(with: Data(line)) as? [String: Any],
                  let type = obj["type"] as? String, type == "assistant" || type == "user" else { continue }
            if obj["isSidechain"] as? Bool == true || obj["isMeta"] as? Bool == true { continue }
            info.hasHistory = true

            let content = (obj["message"] as? [String: Any])?["content"]
            if info.doing == nil {
                info.doing = Self.describeLatest(type: type, content: content)
            }
            if info.said == nil, type == "assistant",
               let blocks = content as? [[String: Any]],
               let text = blocks.last(where: { $0["type"] as? String == "text" })?["text"] as? String {
                info.said = Self.snippet(text)
            }
            if info.doing != nil && info.said != nil { break }
        }
        return info
    }

    static func describeLatest(type: String, content: Any?) -> String? {
        if type == "user" {
            if let blocks = content as? [[String: Any]],
               blocks.contains(where: { $0["type"] as? String == "tool_result" }) {
                return "Thinking…"
            }
            return "Reading your message"
        }
        guard let blocks = content as? [[String: Any]], let last = blocks.last else { return nil }
        switch last["type"] as? String {
        case "tool_use":
            return describeTool(name: last["name"] as? String ?? "", input: last["input"] as? [String: Any] ?? [:])
        case "thinking", "redacted_thinking":
            return "Thinking…"
        case "text":
            return "Writing a reply…"
        default:
            return nil
        }
    }

    static func describeTool(name: String, input: [String: Any]) -> String {
        func file(_ key: String) -> String {
            (input[key] as? String).map { ($0 as NSString).lastPathComponent } ?? "a file"
        }
        switch name {
        case "Read": return "Reading \(file("file_path"))"
        case "Edit", "MultiEdit": return "Editing \(file("file_path"))"
        case "NotebookEdit": return "Editing \(file("notebook_path"))"
        case "Write": return "Writing \(file("file_path"))"
        case "Bash":
            if let d = input["description"] as? String, !d.isEmpty { return d }
            return "Running a command"
        case "Grep", "Glob": return "Searching files"
        case "WebSearch": return "Searching the web"
        case "WebFetch": return "Reading a web page"
        case "Task", "Agent": return "Running a helper"
        case "TodoWrite": return "Updating the to-do list"
        case "Skill": return "Using a skill"
        case "AskUserQuestion": return "Asking you a question"
        default:
            if name.hasPrefix("mcp__") {
                let parts = name.components(separatedBy: "__")
                let server = parts.count > 1 ? parts[1] : ""
                let looksLikeId = server.count >= 32 && server.allSatisfy { $0.isHexDigit || $0 == "-" }
                if server.isEmpty || looksLikeId { return "Using a connector" }
                return "Using \(server.replacingOccurrences(of: "_", with: " "))"
            }
            return "Using \(name)"
        }
    }

    static func snippet(_ text: String) -> String? {
        for raw in text.split(whereSeparator: \.isNewline) {
            var s = raw.trimmingCharacters(in: .whitespaces)
            while let f = s.first, "#>*-•`|".contains(f) {
                s.removeFirst()
                s = s.trimmingCharacters(in: .whitespaces)
            }
            s = s.replacingOccurrences(of: "**", with: "").replacingOccurrences(of: "`", with: "")
            if s.isEmpty { continue }
            if s.count > 110 { s = String(s.prefix(107)) + "…" }
            return s
        }
        return nil
    }
}
