import Foundation

/// Reads and writes a task as a single `.md` file: a small YAML-style
/// front-matter block followed by the markdown notes body. The schema is
/// fixed and tiny, so we hand-roll the (de)serialization rather than pull in
/// a YAML dependency — that keeps the build self-contained.
///
/// Example on disk:
/// ```
/// ---
/// id: 7F3A...
/// title: Redesign landing page
/// status: in-progress
/// priority: important
/// due: 2026-06-15
/// labels: [Design, Frontend]
/// order: 2
/// created: 2026-06-01T10:00:00Z
/// updated: 2026-06-01T11:30:00Z
/// ---
///
/// Body notes in **markdown** …
/// ```
enum MarkdownFile {

    // MARK: Date formats
    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    private static let isoFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    static func dayString(_ d: Date) -> String { dayFormatter.string(from: d) }
    static func parseDay(_ s: String) -> Date? { dayFormatter.date(from: s) }

    // MARK: Serialize

    static func serialize(_ t: KTask) -> String {
        var fm = "---\n"
        fm += "id: \(t.id)\n"
        fm += "title: \(yaml(t.title))\n"
        fm += "status: \(t.status.rawValue)\n"
        fm += "priority: \(t.priority.rawValue)\n"
        if let start = t.start { fm += "start: \(dayFormatter.string(from: start))\n" }
        if let due = t.due     { fm += "due: \(dayFormatter.string(from: due))\n" }
        if !t.labels.isEmpty {
            fm += "labels: [\(t.labels.map(yaml).joined(separator: ", "))]\n"
        }
        if let parent = t.parentID { fm += "parent: \(parent)\n" }
        fm += "order: \(trimNumber(t.order))\n"
        fm += "created: \(isoFormatter.string(from: t.created))\n"
        fm += "updated: \(isoFormatter.string(from: t.updated))\n"
        fm += "---\n\n"
        return fm + t.notes
    }

    // MARK: Parse

    /// Parses a task file. If the file has no recognizable front-matter (e.g. a
    /// plain note dropped into the vault), it is still imported as a task whose
    /// title is the file name and whose body is the whole content, so an
    /// existing vault remains readable.
    static func parse(_ content: String, boardID: String, relPath: String) -> KTask {
        let fileStem = (relPath as NSString).lastPathComponent
            .replacingOccurrences(of: ".md", with: "")

        guard content.hasPrefix("---") else {
            return fallbackTask(title: fileStem, body: content, boardID: boardID, relPath: relPath)
        }

        // Split front-matter from body.
        var lines = content.components(separatedBy: "\n")
        lines.removeFirst() // opening ---
        var fmLines: [String] = []
        var bodyStart = 0
        var closed = false
        for (i, line) in lines.enumerated() {
            if line.trimmingCharacters(in: .whitespaces) == "---" {
                bodyStart = i + 1
                closed = true
                break
            }
            fmLines.append(line)
        }
        guard closed else {
            return fallbackTask(title: fileStem, body: content, boardID: boardID, relPath: relPath)
        }

        var fields: [String: String] = [:]
        for line in fmLines {
            guard let colon = line.firstIndex(of: ":") else { continue }
            let key = String(line[..<colon]).trimmingCharacters(in: .whitespaces)
            let value = String(line[line.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
            if !key.isEmpty { fields[key] = value }
        }

        var body = lines[bodyStart...].joined(separator: "\n")
        if body.hasPrefix("\n") { body.removeFirst() }

        let now = Date()
        let id = fields["id"].flatMap { $0.isEmpty ? nil : $0 } ?? stableID(for: relPath)
        let status = fields["status"].flatMap { TaskStatus(rawValue: $0) } ?? .notStarted
        let priority = fields["priority"].flatMap { Priority(rawValue: $0) } ?? .medium

        return KTask(
            id: id,
            title: unquote(fields["title"] ?? fileStem),
            notes: body,
            status: status,
            priority: priority,
            start: fields["start"].flatMap { dayFormatter.date(from: $0) },
            due: fields["due"].flatMap { dayFormatter.date(from: $0) },
            labels: parseList(fields["labels"]),
            parentID: fields["parent"].flatMap { $0.isEmpty ? nil : $0 },
            order: fields["order"].flatMap { Double($0) } ?? 0,
            created: fields["created"].flatMap { isoFormatter.date(from: $0) } ?? now,
            updated: fields["updated"].flatMap { isoFormatter.date(from: $0) } ?? now,
            boardID: boardID,
            relPath: relPath
        )
    }

    private static func fallbackTask(title: String, body: String, boardID: String, relPath: String) -> KTask {
        let now = Date()
        return KTask(
            id: stableID(for: relPath), title: title, notes: body,
            status: .notStarted, priority: .medium, start: nil, due: nil,
            labels: [], parentID: nil, order: 0, created: now, updated: now,
            boardID: boardID, relPath: relPath
        )
    }

    /// Deterministic id for files that lack one, so identity is stable across
    /// launches without rewriting the user's file.
    private static func stableID(for relPath: String) -> String {
        var hash: UInt64 = 14695981039346656037
        for byte in relPath.utf8 { hash ^= UInt64(byte); hash = hash &* 1099511628211 }
        return "f-" + String(hash, radix: 16)
    }

    // MARK: YAML scalar helpers

    /// Quote a string when it could be misread as YAML structure.
    private static func yaml(_ s: String) -> String {
        let needsQuote = s.isEmpty
            || s != s.trimmingCharacters(in: .whitespaces)
            || s.contains(":") || s.contains("#") || s.contains("[") || s.contains("]")
            || s.contains("\"") || s.contains("\n") || s.hasPrefix("'") || s.hasPrefix(">")
        if !needsQuote { return s }
        let escaped = s.replacingOccurrences(of: "\\", with: "\\\\")
                       .replacingOccurrences(of: "\"", with: "\\\"")
                       .replacingOccurrences(of: "\n", with: " ")
        return "\"\(escaped)\""
    }

    private static func unquote(_ s: String) -> String {
        guard s.count >= 2, s.hasPrefix("\""), s.hasSuffix("\"") else { return s }
        let inner = String(s.dropFirst().dropLast())
        return inner.replacingOccurrences(of: "\\\"", with: "\"")
                    .replacingOccurrences(of: "\\\\", with: "\\")
    }

    private static func parseList(_ raw: String?) -> [String] {
        guard var s = raw else { return [] }
        s = s.trimmingCharacters(in: .whitespaces)
        guard s.hasPrefix("["), s.hasSuffix("]") else { return [] }
        s = String(s.dropFirst().dropLast())
        if s.trimmingCharacters(in: .whitespaces).isEmpty { return [] }
        return s.components(separatedBy: ",")
            .map { unquote($0.trimmingCharacters(in: .whitespaces)) }
            .filter { !$0.isEmpty }
    }

    private static func trimNumber(_ d: Double) -> String {
        if d == d.rounded() { return String(Int(d)) }
        return String(d)
    }
}

// MARK: - Filesystem-safe names

enum NameUtil {
    /// Turn a task title into a human-readable, filesystem-safe file stem.
    /// Mirrors the reference vault: no path separators, no leading dot,
    /// `:` becomes `-`, length-capped. Spaces and case are preserved.
    static func slug(_ title: String) -> String {
        var s = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.isEmpty { s = "Untitled" }
        s = s.replacingOccurrences(of: ":", with: "-")
        for bad in ["/", "\\", "\0", "?", "%", "*", "|", "\"", "<", ">"] {
            s = s.replacingOccurrences(of: bad, with: "-")
        }
        s = s.replacingOccurrences(of: "\n", with: " ")
        while s.contains("  ") { s = s.replacingOccurrences(of: "  ", with: " ") }
        if s.hasPrefix(".") { s = "_" + s.dropFirst() }
        if s.count > 120 { s = String(s.prefix(120)).trimmingCharacters(in: .whitespaces) }
        if s.isEmpty { s = "Untitled" }
        return s
    }
}
