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
        var t = KTask.new(boardID: board, status: status, title: title, parentID: parentID, order: nextOrder)
        if let v = vault, let written = try? v.write(t) { t = written }
        tasks.append(t)
        return t
    }

    /// Replace a task in memory and persist it (debounced for rapid text edits).
    func commit(_ task: KTask, immediate: Bool = false) {
        var task = task
        task.updated = Date()
        if let idx = tasks.firstIndex(where: { $0.id == task.id }) {
            tasks[idx] = task
        } else {
            tasks.append(task)
        }
        if immediate {
            save(task.id)
        } else {
            scheduleSave(task.id)
        }
    }

    private func scheduleSave(_ id: String) {
        pendingSaves[id]?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.save(id) }
        pendingSaves[id] = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45, execute: work)
    }

    private func save(_ id: String) {
        pendingSaves[id] = nil
        persist(id)
    }

    private func persist(_ id: String) {
        guard let v = vault, let idx = tasks.firstIndex(where: { $0.id == id }) else { return }
        if let written = try? v.write(tasks[idx]) {
            // Persist the (possibly renamed) path without disturbing edits.
            tasks[idx].relPath = written.relPath
        }
    }

    /// Write out any debounced edits right now (called when a detail closes).
    func flushSaves() {
        let ids = Array(pendingSaves.keys)
        for id in ids { pendingSaves[id]?.cancel() }
        pendingSaves.removeAll()
        for id in ids { persist(id) }
    }

    func setStatus(_ id: String, _ status: TaskStatus) {
        guard var t = task(id) else { return }
        t.status = status
        commit(t, immediate: true)
    }

    func delete(_ id: String) {
        guard let t = task(id) else { return }
        // Remove sub-tasks first (one level deep).
        for sub in tasks.filter({ $0.parentID == id }) {
            vault?.delete(sub)
        }
        vault?.delete(t)
        tasks.removeAll { $0.id == id || $0.parentID == id }
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

    /// Promote a sub-task into its own top-level card on the same board.
    func promoteToTopLevel(_ id: String) {
        guard var t = task(id) else { return }
        t.parentID = nil
        let peers = tasks.filter { $0.boardID == t.boardID && $0.parentID == nil && $0.status == t.status }
        t.order = (peers.map { $0.order }.max() ?? 0) + 1
        commit(t, immediate: true)
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
