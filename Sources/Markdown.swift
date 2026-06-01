import Foundation

/// Reads and writes a whole **project** (a parent task plus its sub-tasks) as a
/// single `.md` file. The parent uses a small YAML-style front-matter block
/// followed by its markdown notes; each sub-task is introduced by a reserved
/// `<!-- kanpan:subtask -->` delimiter, then the same `key: value` fields and
/// its own markdown notes. HTML comments are hidden in Obsidian's reading view
/// and never collide with prose, so the split is unambiguous.
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
/// Project notes in **markdown** …
///
/// <!-- kanpan:subtask -->
/// title: Build hero section
/// status: done
/// due: 2026-06-10
/// order: 1
///
/// Sub-task notes …
/// ```
///
/// The schema is fixed and tiny, so we hand-roll the (de)serialization rather
/// than pull in a YAML dependency — that keeps the build self-contained.
enum MarkdownFile {

    static let subtaskDelimiter = "<!-- kanpan:subtask -->"

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

    // MARK: - Serialize

    /// Serialize a project (parent + its sub-tasks) into one markdown document.
    static func serializeProject(parent: KTask, subtasks: [KTask]) -> String {
        var blocks: [String] = []
        blocks.append("---\n" + fieldLines(parent) + "---")

        let parentNotes = trimEdges(parent.notes)
        if !parentNotes.isEmpty { blocks.append(parentNotes) }

        for sub in subtasks.sorted(by: { $0.order < $1.order }) {
            // fieldLines ends with a newline; drop it so blocks join cleanly.
            var block = subtaskDelimiter + "\n" + fieldLines(sub)
            if block.hasSuffix("\n") { block.removeLast() }
            let notes = trimEdges(sub.notes)
            if !notes.isEmpty { block += "\n\n" + notes }
            blocks.append(block)
        }
        return blocks.joined(separator: "\n\n") + "\n"
    }

    /// The scalar `key: value` lines for one task (no `---`, no `parent:` — the
    /// parent/child relationship is structural in the project file).
    private static func fieldLines(_ t: KTask) -> String {
        var s = ""
        s += "id: \(t.id)\n"
        s += "title: \(yaml(t.title))\n"
        s += "status: \(t.status.rawValue)\n"
        s += "priority: \(t.priority.rawValue)\n"
        if let start = t.start { s += "start: \(dayFormatter.string(from: start))\n" }
        if let due = t.due     { s += "due: \(dayFormatter.string(from: due))\n" }
        if !t.labels.isEmpty {
            s += "labels: [\(t.labels.map(yaml).joined(separator: ", "))]\n"
        }
        s += "order: \(trimNumber(t.order))\n"
        s += "created: \(isoFormatter.string(from: t.created))\n"
        s += "updated: \(isoFormatter.string(from: t.updated))\n"
        return s
    }

    // MARK: - Parse

    /// Parse a project file into a flat list: the parent first, then its
    /// sub-tasks (each with `parentID` set to the parent's id). Files with no
    /// recognizable front-matter are still imported as a single task so an
    /// existing vault stays readable. Legacy single-task files (with a
    /// `parent:` field and no embedded sub-tasks) parse as one task carrying
    /// that `parentID`, which the vault migration then consolidates.
    static func parseProject(_ content: String, boardID: String, relPath: String) -> [KTask] {
        let stem = (relPath as NSString).lastPathComponent
            .replacingOccurrences(of: ".md", with: "")

        guard content.hasPrefix("---") else {
            return [fallbackTask(title: stem, body: content, boardID: boardID, relPath: relPath)]
        }

        var lines = content.components(separatedBy: "\n")
        lines.removeFirst() // opening ---
        var fmLines: [String] = []
        var bodyStart = 0
        var closed = false
        for (i, line) in lines.enumerated() {
            if line.trimmingCharacters(in: .whitespaces) == "---" {
                bodyStart = i + 1; closed = true; break
            }
            fmLines.append(line)
        }
        guard closed else {
            return [fallbackTask(title: stem, body: content, boardID: boardID, relPath: relPath)]
        }

        var parent = taskFromFields(fieldsFromLines(fmLines), fallbackTitle: stem,
                                    boardID: boardID, relPath: relPath)

        // Split the body into the parent notes + one segment per sub-task,
        // ignoring delimiter-looking lines inside fenced code blocks.
        let bodyLines = Array(lines[bodyStart...])
        var segments: [[String]] = [[]]
        var inFence = false
        for line in bodyLines {
            let t = line.trimmingCharacters(in: .whitespaces)
            if t.hasPrefix("```") || t.hasPrefix("~~~") { inFence.toggle() }
            if !inFence && t == subtaskDelimiter {
                segments.append([])
            } else {
                segments[segments.count - 1].append(line)
            }
        }

        parent.notes = trimEdges(segments[0].joined(separator: "\n"))
        var result: [KTask] = [parent]

        for seg in segments.dropFirst() {
            var fieldBlock: [String] = []
            var j = 0
            while j < seg.count {
                let line = seg[j]
                if line.trimmingCharacters(in: .whitespaces).isEmpty { break }
                if !line.contains(":") { break }
                fieldBlock.append(line); j += 1
            }
            var sub = taskFromFields(fieldsFromLines(fieldBlock), fallbackTitle: "Sub-task",
                                     boardID: boardID, relPath: relPath)
            sub.parentID = parent.id
            sub.notes = trimEdges(Array(seg[j...]).joined(separator: "\n"))
            result.append(sub)
        }
        return result
    }

    private static func taskFromFields(_ f: [String: String], fallbackTitle: String,
                                       boardID: String, relPath: String) -> KTask {
        let now = Date()
        let title = unquote(f["title"] ?? fallbackTitle)
        let id = f["id"]?.nonEmpty ?? stableID(for: relPath + "|" + title)
        return KTask(
            id: id,
            title: title,
            notes: "",
            status: f["status"].flatMap { TaskStatus(rawValue: $0) } ?? .notStarted,
            priority: f["priority"].flatMap { Priority(rawValue: $0) } ?? .medium,
            start: f["start"].flatMap { dayFormatter.date(from: $0) },
            due: f["due"].flatMap { dayFormatter.date(from: $0) },
            labels: parseList(f["labels"]),
            parentID: f["parent"]?.nonEmpty,
            order: f["order"].flatMap { Double($0) } ?? 0,
            created: f["created"].flatMap { isoFormatter.date(from: $0) } ?? now,
            updated: f["updated"].flatMap { isoFormatter.date(from: $0) } ?? now,
            boardID: boardID,
            relPath: relPath
        )
    }

    private static func fieldsFromLines(_ lines: [String]) -> [String: String] {
        var fields: [String: String] = [:]
        for line in lines {
            guard let colon = line.firstIndex(of: ":") else { continue }
            let key = String(line[..<colon]).trimmingCharacters(in: .whitespaces)
            let value = String(line[line.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
            if !key.isEmpty { fields[key] = value }
        }
        return fields
    }

    private static func fallbackTask(title: String, body: String, boardID: String, relPath: String) -> KTask {
        let now = Date()
        return KTask(
            id: stableID(for: relPath), title: title, notes: trimEdges(body),
            status: .notStarted, priority: .medium, start: nil, due: nil,
            labels: [], parentID: nil, order: 0, created: now, updated: now,
            boardID: boardID, relPath: relPath
        )
    }

    /// Deterministic id for content that lacks one, so identity is stable across
    /// launches without rewriting the user's file.
    private static func stableID(for seed: String) -> String {
        var hash: UInt64 = 14695981039346656037
        for byte in seed.utf8 { hash ^= UInt64(byte); hash = hash &* 1099511628211 }
        return "f-" + String(hash, radix: 16)
    }

    // MARK: - Helpers

    /// Drop leading/trailing blank lines so notes round-trip stably.
    private static func trimEdges(_ s: String) -> String {
        var lines = s.components(separatedBy: "\n")
        while let f = lines.first, f.trimmingCharacters(in: .whitespaces).isEmpty { lines.removeFirst() }
        while let l = lines.last, l.trimmingCharacters(in: .whitespaces).isEmpty { lines.removeLast() }
        return lines.joined(separator: "\n")
    }

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
