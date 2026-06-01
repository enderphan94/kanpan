import SwiftUI
import Combine

enum ViewMode: String { case board, grid }

/// App appearance override. `.system` follows macOS; the others force light/dark.
enum AppAppearance: String, CaseIterable, Identifiable {
    case system, light, dark
    var id: String { rawValue }
    var title: String {
        switch self {
        case .system: return "System"
        case .light:  return "Light"
        case .dark:   return "Dark"
        }
    }
    var symbol: String {
        switch self {
        case .system: return "circle.lefthalf.filled"
        case .light:  return "sun.max"
        case .dark:   return "moon"
        }
    }
    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light:  return .light
        case .dark:   return .dark
        }
    }
}

/// The single source of truth for the running app. Holds the open vault, the
/// in-memory task list, and the current UI selection. Every mutation persists
/// to markdown — structural edits immediately, text edits debounced.
final class AppStore: ObservableObject {

    // Vault
    @Published private(set) var vaultURL: URL?
    private var vault: Vault?
    private var prefs = VaultPrefs()

    // Data
    @Published private(set) var boards: [Board] = []
    @Published private(set) var tasks: [KTask] = []

    // UI state
    @Published var selectedBoardID: String?
    @Published var viewMode: ViewMode = .board
    @Published var appearance: AppAppearance = .system
    @Published var searchText: String = ""
    /// Drill-in stack of task ids. Empty = no detail open; last = visible card.
    @Published var detailStack: [String] = []
    /// Set by the "New Board…" menu command; the sidebar presents its prompt.
    @Published var showNewBoardSheet: Bool = false

    private let vaultKey = "KanpanVaultPath"
    private let viewModeKey = "KanpanViewMode"
    private let appearanceKey = "KanpanAppearance"
    private var pendingSaves: [String: DispatchWorkItem] = [:]

    var hasVault: Bool { vault != nil }

    // MARK: - Bootstrap

    func bootstrap() {
        if let raw = UserDefaults.standard.string(forKey: viewModeKey),
           let m = ViewMode(rawValue: raw) { viewMode = m }
        if let raw = UserDefaults.standard.string(forKey: appearanceKey),
           let a = AppAppearance(rawValue: raw) { appearance = a }
        if let saved = UserDefaults.standard.string(forKey: vaultKey) {
            let url = URL(fileURLWithPath: saved)
            var isDir: ObjCBool = false
            if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue {
                openVault(at: url, createDefaultBoardIfEmpty: true)
            }
        }
    }

    // MARK: - Vault lifecycle

    func createVault(at url: URL) {
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        openVault(at: url, createDefaultBoardIfEmpty: true)
    }

    func openVault(at url: URL, createDefaultBoardIfEmpty: Bool) {
        let v = Vault(root: url)
        vault = v
        vaultURL = url
        prefs = v.loadPrefs()
        UserDefaults.standard.set(url.path, forKey: vaultKey)

        var names = v.discoverBoards()
        if names.isEmpty && createDefaultBoardIfEmpty {
            if let created = try? v.createBoard(named: "My Board") { names = [created] }
        }
        rebuildBoards(names)
        tasks = v.loadAllTasks()
        migrateLegacyLayoutIfNeeded()

        if let last = prefs.lastBoard, boards.contains(where: { $0.id == last }) {
            selectedBoardID = last
        } else {
            selectedBoardID = boards.first?.id
        }
        detailStack = []
    }

    /// Forget the current vault and return to the welcome screen.
    func closeVault() {
        vault = nil
        vaultURL = nil
        boards = []
        tasks = []
        selectedBoardID = nil
        detailStack = []
        UserDefaults.standard.removeObject(forKey: vaultKey)
    }

    func reload() {
        guard let v = vault else { return }
        rebuildBoards(v.discoverBoards())
        tasks = v.loadAllTasks()
        if let sel = selectedBoardID, !boards.contains(where: { $0.id == sel }) {
            selectedBoardID = boards.first?.id
        }
    }

    func revealVaultInFinder() {
        guard let url = vaultURL else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    private func rebuildBoards(_ names: [String]) {
        let order = prefs.boardOrder
        let sorted = names.sorted { a, b in
            let ia = order.firstIndex(of: a) ?? Int.max
            let ib = order.firstIndex(of: b) ?? Int.max
            if ia != ib { return ia < ib }
            return a.localizedCaseInsensitiveCompare(b) == .orderedAscending
        }
        boards = sorted.enumerated().map { Board(id: $0.element, order: $0.offset) }
    }

    private func persistPrefs() {
        prefs.boardOrder = boards.map { $0.id }
        prefs.lastBoard = selectedBoardID
        vault?.savePrefs(prefs)
    }

    func setViewMode(_ m: ViewMode) {
        viewMode = m
        UserDefaults.standard.set(m.rawValue, forKey: viewModeKey)
    }

    func rememberSelection() { persistPrefs() }

    func setAppearance(_ a: AppAppearance) {
        appearance = a
        UserDefaults.standard.set(a.rawValue, forKey: appearanceKey)
    }

    // MARK: - Boards

    @discardableResult
    func addBoard(named name: String) -> String? {
        guard let v = vault, let created = try? v.createBoard(named: name) else { return nil }
        rebuildBoards(v.discoverBoards())
        selectedBoardID = created
        persistPrefs()
        return created
    }

    func renameBoard(_ id: String, to newName: String) {
        guard let v = vault, let newID = try? v.renameBoard(id, to: newName) else { return }
        // Reassign tasks that belonged to the old board.
        for i in tasks.indices where tasks[i].boardID == id {
            tasks[i].boardID = newID
            tasks[i].relPath = tasks[i].relPath.replacingOccurrences(
                of: id + "/", with: newID + "/")
        }
        if selectedBoardID == id { selectedBoardID = newID }
        if let idx = prefs.boardOrder.firstIndex(of: id) { prefs.boardOrder[idx] = newID }
        rebuildBoards(v.discoverBoards())
        persistPrefs()
    }

    func deleteBoard(_ id: String) {
        guard let v = vault else { return }
        try? v.deleteBoard(id)
        tasks.removeAll { $0.boardID == id }
        rebuildBoards(v.discoverBoards())
        if selectedBoardID == id { selectedBoardID = boards.first?.id }
        persistPrefs()
    }

    func moveBoard(from source: IndexSet, to destination: Int) {
        boards.move(fromOffsets: source, toOffset: destination)
        for i in boards.indices { boards[i].order = i }
        persistPrefs()
    }

    // MARK: - Queries

    func task(_ id: String?) -> KTask? {
        guard let id else { return nil }
        return tasks.first { $0.id == id }
    }

    /// Top-level cards in a board + status column, ordered.
    func cards(board: String, status: TaskStatus) -> [KTask] {
        tasks.filter { $0.boardID == board && $0.parentID == nil && $0.status == status && matchesSearch($0) }
            .sorted { $0.order < $1.order }
    }

    func allCards(board: String) -> [KTask] {
        tasks.filter { $0.boardID == board && $0.parentID == nil && matchesSearch($0) }
            .sorted { ($0.status.columnIndex, $0.order) < ($1.status.columnIndex, $1.order) }
    }

    func subtasks(of parentID: String) -> [KTask] {
        tasks.filter { $0.parentID == parentID }.sorted { $0.order < $1.order }
    }

    /// (completed, total) over a parent's sub-tasks — drives the roll-up bar.
    func progress(of parentID: String) -> (done: Int, total: Int) {
        let subs = tasks.filter { $0.parentID == parentID }
        return (subs.filter { $0.status == .completed }.count, subs.count)
    }

    private func matchesSearch(_ t: KTask) -> Bool {
        let q = searchText.trimmingCharacters(in: .whitespaces)
        if q.isEmpty { return true }
        return t.title.localizedCaseInsensitiveContains(q)
            || t.notes.localizedCaseInsensitiveContains(q)
            || t.labels.contains { $0.localizedCaseInsensitiveContains(q) }
    }

    // MARK: - Task mutations

    @discardableResult
    func addTask(board: String, status: TaskStatus, title: String, parentID: String? = nil) -> KTask {
        let peers = tasks.filter { $0.boardID == board && $0.parentID == parentID && $0.status == status }
        let nextOrder = (peers.map { $0.order }.max() ?? 0) + 1
        let t = KTask.new(boardID: board, status: status, title: title, parentID: parentID, order: nextOrder)
        tasks.append(t)
        saveNow(parentID ?? t.id)          // write the project file (creates or rewrites)
        return task(t.id) ?? t
    }

    /// Replace a task in memory and persist its project (debounced for rapid
    /// text edits). A project is one file: editing a sub-task rewrites the
    /// parent's file.
    func commit(_ task: KTask, immediate: Bool = false) {
        var task = task
        task.updated = Date()
        if let idx = tasks.firstIndex(where: { $0.id == task.id }) {
            tasks[idx] = task
        } else {
            tasks.append(task)
        }
        let root = task.parentID ?? task.id
        if immediate { saveNow(root) } else { scheduleSave(root) }
    }

    private func scheduleSave(_ rootID: String) {
        pendingSaves[rootID]?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.saveNow(rootID) }
        pendingSaves[rootID] = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45, execute: work)
    }

    private func saveNow(_ rootID: String) {
        pendingSaves[rootID] = nil
        persistProject(rootID: rootID)
    }

    /// Serialize a whole project (parent + sub-tasks) to its single file.
    private func persistProject(rootID: String) {
        guard let v = vault,
              let parent = tasks.first(where: { $0.id == rootID && $0.parentID == nil })
        else { return }
        let subs = tasks.filter { $0.parentID == rootID }
        guard let (np, nsubs) = try? v.writeProject(parent: parent, subtasks: subs) else { return }
        setRelPath(np.id, np.relPath)
        for ns in nsubs { setRelPath(ns.id, ns.relPath) }
    }

    private func setRelPath(_ id: String, _ rel: String) {
        if let idx = tasks.firstIndex(where: { $0.id == id }) { tasks[idx].relPath = rel }
    }

    /// One-time migration from the old layout (one file per task, sub-tasks in
    /// their own files) to the new layout (one file per project). Detects
    /// sub-tasks that still live in their own file, backs up the vault, writes
    /// each project as a single consolidated file, and removes the leftovers.
    private func migrateLegacyLayoutIfNeeded() {
        guard let v = vault else { return }
        let topIDs = Set(tasks.filter { $0.parentID == nil }.map { $0.id })

        // Legacy on disk = a sub-task stored in a file different from its parent
        // (or orphaned because its parent no longer exists).
        let legacy = tasks.filter { sub in
            guard sub.parentID != nil else { return false }
            guard let p = tasks.first(where: { $0.id == sub.parentID }) else { return true }
            return sub.relPath != p.relPath
        }
        guard !legacy.isEmpty else { return }

        _ = try? v.backup(label: "Kanpan backup before single-file migration")
        let oldFiles = Set(legacy.map { $0.relPath }.filter { !$0.isEmpty })

        // Promote orphans so their content survives.
        for i in tasks.indices {
            if let pid = tasks[i].parentID, !topIDs.contains(pid) {
                tasks[i].parentID = nil
                tasks[i].relPath = ""
            }
        }

        // Write every project as one file (the parent absorbs its sub-tasks).
        for parent in tasks.filter({ $0.parentID == nil }) {
            persistProject(rootID: parent.id)
        }

        // Remove the leftover separate sub-task files (never a live project file).
        let projectFiles = Set(tasks.filter { $0.parentID == nil }.map { $0.relPath })
        for path in oldFiles where !projectFiles.contains(path) {
            v.deleteFile(relPath: path)
        }

        tasks = v.loadAllTasks()   // reload a clean, consolidated state
    }

    /// Write out any debounced edits right now (called when a detail closes).
    func flushSaves() {
        let ids = Array(pendingSaves.keys)
        for id in ids { pendingSaves[id]?.cancel() }
        pendingSaves.removeAll()
        for id in ids { persistProject(rootID: id) }
    }

    func setStatus(_ id: String, _ status: TaskStatus) {
        guard var t = task(id) else { return }
        t.status = status
        commit(t, immediate: true)
    }

    func delete(_ id: String) {
        guard let t = task(id) else { return }
        if let parentID = t.parentID {
            // A sub-task lives inside its parent's file: drop it and rewrite.
            tasks.removeAll { $0.id == id }
            saveNow(parentID)
        } else {
            // A top-level project owns its file (and all its sub-tasks).
            vault?.deleteFile(relPath: t.relPath)
            tasks.removeAll { $0.id == id || $0.parentID == id }
        }
        detailStack.removeAll { $0 == id }
    }

    /// Move a card to a status column, optionally inserting before another card.
    func move(_ id: String, toStatus status: TaskStatus, before beforeID: String? = nil) {
        guard var moved = task(id) else { return }
        let board = moved.boardID
        let parentID = moved.parentID
        moved.status = status

        var column = tasks
            .filter { $0.boardID == board && $0.parentID == parentID && $0.status == status && $0.id != id }
            .sorted { $0.order < $1.order }

        let insertIdx: Int
        if let beforeID, let i = column.firstIndex(where: { $0.id == beforeID }) {
            insertIdx = i
        } else {
            insertIdx = column.count
        }
        column.insert(moved, at: insertIdx)
        // Re-number the whole column so order stays clean and gap-free.
        for (i, var c) in column.enumerated() where c.order != Double(i) || c.id == id {
            c.order = Double(i)
            commit(c, immediate: true)
        }
    }

    /// Promote a sub-task into its own top-level card (its own project file) on
    /// the same board, and rewrite the old parent's file without it.
    func promoteToTopLevel(_ id: String) {
        guard var t = task(id), let oldParent = t.parentID else { return }
        t.parentID = nil
        t.relPath = ""   // force a fresh project file for the promoted task
        let peers = tasks.filter { $0.boardID == t.boardID && $0.parentID == nil && $0.status == t.status }
        t.order = (peers.map { $0.order }.max() ?? 0) + 1
        if let idx = tasks.firstIndex(where: { $0.id == id }) { tasks[idx] = t }
        saveNow(t.id)          // create the new project file
        saveNow(oldParent)     // rewrite the old parent without this sub-task
    }

    // MARK: - Menu intents

    func requestNewTask() {
        guard let b = selectedBoardID else { return }
        let t = addTask(board: b, status: .notStarted, title: "New Task")
        openDetail(t.id)
    }

    func requestNewBoard() { showNewBoardSheet = true }

    // MARK: - Detail navigation

    func openDetail(_ id: String) { detailStack = [id] }
    func drillInto(_ id: String) { detailStack.append(id) }
    func popDetail() { flushSaves(); if !detailStack.isEmpty { detailStack.removeLast() } }
    func closeDetail() { flushSaves(); detailStack = [] }

    /// Two-way binding into a task by id, so detail fields can edit in place.
    func binding(_ id: String) -> Binding<KTask> {
        Binding(
            get: { [weak self] in
                self?.tasks.first(where: { $0.id == id })
                    ?? KTask.new(boardID: "", status: .notStarted, title: "", order: 0)
            },
            set: { [weak self] newValue in self?.commit(newValue) }
        )
    }
}
