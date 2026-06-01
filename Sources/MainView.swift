import SwiftUI

struct MainView: View {
    @EnvironmentObject var store: AppStore

    var body: some View {
        NavigationSplitView {
            SidebarView()
                .navigationSplitViewColumnWidth(min: 200, ideal: 230, max: 320)
        } detail: {
            ContentArea()
                .navigationTitle(store.selectedBoardID ?? "Kanpan")
                .navigationSubtitle(store.vaultURL?.lastPathComponent ?? "")
        }
        .toolbar { toolbarContent }
        .searchable(text: $store.searchText, placement: .toolbar, prompt: "Search tasks")
        .overlay {
            if !store.detailStack.isEmpty {
                DetailOverlay()
            }
        }
        .animation(.easeOut(duration: 0.16), value: store.detailStack)
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .principal) {
            Picker("", selection: Binding(
                get: { store.viewMode },
                set: { store.setViewMode($0) })) {
                Label("Board", systemImage: "rectangle.split.3x1").tag(ViewMode.board)
                Label("Grid", systemImage: "tablecells").tag(ViewMode.grid)
            }
            .pickerStyle(.segmented)
            .labelStyle(.titleAndIcon)
            .fixedSize()
        }
        ToolbarItem(placement: .primaryAction) {
            Button {
                store.requestNewTask()
            } label: {
                Label("New Task", systemImage: "plus")
            }
            .disabled(store.selectedBoardID == nil)
            .help("Add a task (⌘N)")
        }
    }
}

// MARK: - Detail overlay

/// The task detail panel, shown as an in-window overlay (not a modal sheet) so
/// clicking the dimmed backdrop dismisses it — saving as it closes.
struct DetailOverlay: View {
    @EnvironmentObject var store: AppStore

    var body: some View {
        ZStack {
            Rectangle()
                .fill(.black.opacity(0.4))
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture { store.closeDetail() }

            TaskDetailView()
                .frame(width: 660)
                .frame(minHeight: 460, maxHeight: 760)
                .background(Color(nsColor: .windowBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.10))
                )
                .shadow(color: .black.opacity(0.35), radius: 28, y: 8)
                .padding(.vertical, 32)
        }
        .transition(.opacity)
    }
}

// MARK: - Sidebar

struct SidebarView: View {
    @EnvironmentObject var store: AppStore
    @State private var prompt: NamePrompt?

    var body: some View {
        VStack(spacing: 0) {
            List(selection: Binding(
                get: { store.selectedBoardID },
                set: { store.selectedBoardID = $0; store.rememberSelection() })) {
                Section("Boards") {
                    ForEach(store.boards) { board in
                        Label(board.name, systemImage: "square.stack.3d.up")
                            .tag(board.id as String?)
                            .contextMenu {
                                Button("Rename…") { prompt = .rename(board.id) }
                                Button("Reveal in Finder") { store.revealVaultInFinder() }
                                Divider()
                                Button("Delete Board", role: .destructive) {
                                    prompt = .deleteConfirm(board.id)
                                }
                            }
                    }
                    .onMove { store.moveBoard(from: $0, to: $1) }
                }
            }
            .listStyle(.sidebar)

            Divider()
            HStack {
                Button {
                    prompt = .newBoard
                } label: {
                    Label("Add Board", systemImage: "plus")
                }
                .buttonStyle(.plain)
                Spacer()
                Menu {
                    Picker("Appearance", selection: Binding(
                        get: { store.appearance },
                        set: { store.setAppearance($0) })) {
                        ForEach(AppAppearance.allCases) { a in
                            Label(a.title, systemImage: a.symbol).tag(a)
                        }
                    }
                    Divider()
                    Button("Reveal Vault in Finder") { store.revealVaultInFinder() }
                    Button("Reload from Disk") { store.reload() }
                    Divider()
                    Button("Switch Vault…") { store.closeVault() }
                    Divider()
                    Button("About Kanpan…") { store.showAbout = true }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .safeAreaInset(edge: .top, spacing: 0) { vaultHeader }
        .onChange(of: store.showNewBoardSheet) { _, newValue in
            if newValue { prompt = .newBoard; store.showNewBoardSheet = false }
        }
        .sheet(item: $prompt) { p in promptSheet(p) }
    }

    private var vaultHeader: some View {
        HStack(spacing: 10) {
            AppGlyph(size: 26)
            VStack(alignment: .leading, spacing: 1) {
                Text("Kanpan").font(.system(size: 13, weight: .semibold))
                Text(store.vaultURL?.lastPathComponent ?? "Vault")
                    .font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.bar)
    }

    @ViewBuilder
    private func promptSheet(_ p: NamePrompt) -> some View {
        switch p {
        case .newBoard:
            NamePromptSheet(title: "New Board", placeholder: "Board name", initial: "") { name in
                store.addBoard(named: name)
            }
        case .rename(let id):
            NamePromptSheet(title: "Rename Board", placeholder: "Board name", initial: id) { name in
                store.renameBoard(id, to: name)
            }
        case .deleteConfirm(let id):
            DeleteBoardSheet(boardName: id) { store.deleteBoard(id) }
        }
    }
}

enum NamePrompt: Identifiable {
    case newBoard
    case rename(String)
    case deleteConfirm(String)
    var id: String {
        switch self {
        case .newBoard: return "new"
        case .rename(let s): return "rename-\(s)"
        case .deleteConfirm(let s): return "del-\(s)"
        }
    }
}

// MARK: - Content

struct ContentArea: View {
    @EnvironmentObject var store: AppStore

    var body: some View {
        Group {
            if store.boards.isEmpty {
                EmptyStateView(
                    icon: "square.stack.3d.up.slash",
                    title: "No boards yet",
                    message: "Create a board to start tracking tasks.",
                    actionTitle: "Add Board") { store.requestNewBoard() }
            } else if let board = store.selectedBoardID {
                switch store.viewMode {
                case .board: BoardView(board: board)
                case .grid:  GridView(board: board)
                }
            } else {
                EmptyStateView(icon: "sidebar.left", title: "Select a board",
                               message: "Pick a board from the sidebar.", actionTitle: nil, action: nil)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.canvas)
    }
}

struct EmptyStateView: View {
    let icon: String
    let title: String
    let message: String
    let actionTitle: String?
    let action: (() -> Void)?

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: icon).font(.system(size: 40)).foregroundStyle(.tertiary)
            Text(title).font(.title3.weight(.semibold))
            Text(message).foregroundStyle(.secondary).multilineTextAlignment(.center)
            if let actionTitle, let action {
                Button(actionTitle, action: action).buttonStyle(.borderedProminent).padding(.top, 4)
            }
        }
        .frame(maxWidth: 360)
    }
}

// MARK: - Reusable prompt sheets

struct NamePromptSheet: View {
    let title: String
    let placeholder: String
    let initial: String
    let onConfirm: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var text: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(title).font(.headline)
            TextField(placeholder, text: $text)
                .textFieldStyle(.roundedBorder)
                .onSubmit(confirm)
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Save", action: confirm)
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                    .disabled(text.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 360)
        .onAppear { text = initial }
    }

    private func confirm() {
        let t = text.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty else { return }
        onConfirm(t)
        dismiss()
    }
}

struct DeleteBoardSheet: View {
    let boardName: String
    let onDelete: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Delete “\(boardName)”?").font(.headline)
            Text("This permanently deletes the board folder and all its task files from your vault. This can't be undone.")
                .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Delete", role: .destructive) { onDelete(); dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 380)
    }
}
