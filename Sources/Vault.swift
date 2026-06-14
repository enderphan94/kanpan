import Foundation

/// Filesystem-backed store, Obsidian-style. A *vault* is one directory on disk.
///
/// Layout:
/// ```
/// <Vault>/
///   .kanpan.json            ← hidden app prefs (board order, last board)
///   My Board/               ← a board = a folder
///     Redesign.md           ← a task = one .md file (front-matter + notes)
///     Build hero section.md ← a sub-task (its front-matter has `parent:`)
///   Personal/
///     Taxes.md
/// ```
///
/// Why on disk and not a database: the vault works with iCloud / Dropbox /
/// Time Machine, can be edited in Obsidian or any editor, and backup is a
/// single folder copy.
struct Vault {
    let root: URL
    private let fm = FileManager.default

    // Files/folders we never treat as boards or tasks.
    private static let skip: Set<String> = [".DS_Store", ".obsidian", ".trash",
                                            ".kanpan.json", "node_modules"]

    private func isHidden(_ name: String) -> Bool {
        name.hasPrefix(".") || name.hasPrefix("_") || Self.skip.contains(name)
    }

    // MARK: Boards

    /// Immediate subdirectories of the vault root, each a board.
    func discoverBoards() -> [String] {
        guard let entries = try? fm.contentsOfDirectory(at: root,
                includingPropertiesForKeys: [.isDirectoryKey], options: []) else { return [] }
        var names: [String] = []
        for url in entries {
            let name = url.lastPathComponent
            if isHidden(name) { continue }
            var isDir: ObjCBool = false
            if fm.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue {
                names.append(name)
            }
        }
        return names.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    @discardableResult
    func createBoard(named name: String) throws -> String {
        let clean = NameUtil.slug(name)
        var target = root.appendingPathComponent(clean, isDirectory: true)
        var n = 2
        while fm.fileExists(atPath: target.path) {
            target = root.appendingPathComponent("\(clean) \(n)", isDirectory: true)
            n += 1
        }
        try fm.createDirectory(at: target, withIntermediateDirectories: true)
        return target.lastPathComponent
    }

    @discardableResult
    func renameBoard(_ old: String, to newName: String) throws -> String {
        let clean = NameUtil.slug(newName)
        let src = root.appendingPathComponent(old, isDirectory: true)
        var dst = root.appendingPathComponent(clean, isDirectory: true)
        if clean == old { return old }
        var n = 2
        while fm.fileExists(atPath: dst.path) {
            dst = root.appendingPathComponent("\(clean) \(n)", isDirectory: true)
            n += 1
        }
        try fm.moveItem(at: src, to: dst)
        return dst.lastPathComponent
    }

    func deleteBoard(_ name: String) throws {
        let url = root.appendingPathComponent(name, isDirectory: true)
        try fm.removeItem(at: url)
    }

    // MARK: Tasks

    /// Read every task in every board.
    func loadAllTasks() -> [KTask] {
        var out: [KTask] = []
        for board in discoverBoards() {
            out.append(contentsOf: loadTasks(board: board))
        }
        return out
    }

    /// Read all `.md` files inside one board folder (recursively, tolerating
    /// any subfolders the user may have made).
    func loadTasks(board: String) -> [KTask] {
        let boardURL = root.appendingPathComponent(board, isDirectory: true)
        var out: [KTask] = []
        collectMarkdown(in: boardURL).forEach { url in
            guard let content = try? String(contentsOf: url, encoding: .utf8) else { return }
            let rel = relativePath(of: url)
            out.append(contentsOf: MarkdownFile.parseProject(content, boardID: board, relPath: rel))
        }
        return out
    }

    private func collectMarkdown(in dir: URL) -> [URL] {
        guard let entries = try? fm.contentsOfDirectory(at: dir,
                includingPropertiesForKeys: [.isDirectoryKey], options: []) else { return [] }
        var files: [URL] = []
        for url in entries {
            let name = url.lastPathComponent
            if isHidden(name) { continue }
            var isDir: ObjCBool = false
            fm.fileExists(atPath: url.path, isDirectory: &isDir)
            if isDir.boolValue {
                files.append(contentsOf: collectMarkdown(in: url))
            } else if name.lowercased().hasSuffix(".md") {
                files.append(url)
            }
        }
        return files
    }

    /// Write a whole project (parent + all of its descendants: sub-tasks and
    /// their works) to one `.md` file, creating or renaming it based on the
    /// parent's title. Returns the parent and items with their `relPath` updated.
    @discardableResult
    func writeProject(parent: KTask, items: [KTask]) throws -> (KTask, [KTask]) {
        var parent = parent
        let boardURL = root.appendingPathComponent(parent.boardID, isDirectory: true)
        try fm.createDirectory(at: boardURL, withIntermediateDirectories: true)

        let desiredName = NameUtil.slug(parent.title) + ".md"
        let currentURL: URL? = parent.relPath.isEmpty ? nil : root.appendingPathComponent(parent.relPath)

        var destURL = boardURL.appendingPathComponent(desiredName)
        if currentURL?.lastPathComponent != desiredName {
            destURL = uniqueURL(in: boardURL, name: desiredName, excluding: currentURL)
        } else {
            destURL = currentURL!
        }

        // Rename the file when the title changed.
        if let currentURL, currentURL != destURL, fm.fileExists(atPath: currentURL.path) {
            if fm.fileExists(atPath: destURL.path) {
                destURL = uniqueURL(in: boardURL, name: desiredName, excluding: currentURL)
            }
            try fm.moveItem(at: currentURL, to: destURL)
        }

        let rel = relativePath(of: destURL)
        parent.relPath = rel
        var descendants = items
        for i in descendants.indices { descendants[i].relPath = rel }

        let content = MarkdownFile.serializeProject(parent: parent, items: descendants)
        try content.data(using: .utf8)?.write(to: destURL, options: .atomic)
        return (parent, descendants)
    }

    /// Delete a project file by its vault-relative path.
    func deleteFile(relPath: String) {
        guard !relPath.isEmpty else { return }
        try? fm.removeItem(at: root.appendingPathComponent(relPath))
    }

    /// Copy the whole vault to a sibling folder (used once before migrating the
    /// storage layout). Returns the backup location.
    @discardableResult
    func backup(label: String) throws -> URL {
        let parent = root.deletingLastPathComponent()
        let base = root.lastPathComponent + " (\(label))"
        var dest = parent.appendingPathComponent(base)
        var n = 2
        while fm.fileExists(atPath: dest.path) {
            dest = parent.appendingPathComponent("\(base) \(n)"); n += 1
        }
        try fm.copyItem(at: root, to: dest)
        return dest
    }

    // MARK: Helpers

    private func uniqueURL(in folder: URL, name: String, excluding: URL?) -> URL {
        let base = (name as NSString).deletingPathExtension
        let ext = (name as NSString).pathExtension
        var candidate = folder.appendingPathComponent(name)
        var n = 2
        while fm.fileExists(atPath: candidate.path), candidate != excluding {
            candidate = folder.appendingPathComponent("\(base) \(n).\(ext)")
            n += 1
        }
        return candidate
    }

    private func relativePath(of url: URL) -> String {
        let rootPath = root.standardizedFileURL.path
        let p = url.standardizedFileURL.path
        if p.hasPrefix(rootPath) {
            return String(p.dropFirst(rootPath.count)).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        }
        return url.lastPathComponent
    }

    // MARK: App prefs (hidden, non-content)

    private var prefsURL: URL { root.appendingPathComponent(".kanpan.json") }

    func loadPrefs() -> VaultPrefs {
        guard let data = try? Data(contentsOf: prefsURL),
              let prefs = try? JSONDecoder().decode(VaultPrefs.self, from: data)
        else { return VaultPrefs() }
        return prefs
    }

    func savePrefs(_ prefs: VaultPrefs) {
        if let data = try? JSONEncoder().encode(prefs) {
            try? data.write(to: prefsURL, options: .atomic)
        }
    }

    static func defaultLocation() -> URL {
        let icloud = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Mobile Documents/com~apple~CloudDocs")
        var isDir: ObjCBool = false
        if FileManager.default.fileExists(atPath: icloud.path, isDirectory: &isDir), isDir.boolValue {
            return icloud.appendingPathComponent("Kanpan Vault")
        }
        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Documents/Kanpan Vault")
    }
}

/// Small non-content preferences kept alongside the vault so board order and
/// the last-opened board travel with the vault when it's moved or restored.
struct VaultPrefs: Codable {
    var boardOrder: [String] = []
    var lastBoard: String? = nil
}
