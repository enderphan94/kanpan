import SwiftUI

/// The Kanban board: one column per status. Dragging a card to a column sets
/// its status, so marking a task Done lands it in the Completed column.
struct BoardView: View {
    @EnvironmentObject var store: AppStore
    let board: String

    var body: some View {
        ScrollView(.horizontal, showsIndicators: true) {
            HStack(alignment: .top, spacing: 14) {
                ForEach(TaskStatus.allCases) { status in
                    StatusColumn(board: board, status: status)
                        .frame(width: 290)
                }
            }
            .padding(16)
            .frame(maxHeight: .infinity, alignment: .top)
        }
    }
}

private struct StatusColumn: View {
    @EnvironmentObject var store: AppStore
    let board: String
    let status: TaskStatus
    @State private var isTargeted = false

    private var cards: [KTask] { store.cards(board: board, status: status) }

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView(showsIndicators: false) {
                LazyVStack(spacing: 8) {
                    ForEach(cards) { card in
                        TaskCardView(task: card)
                            .dropDestination(for: String.self) { items, _ in
                                guard let id = items.first, id != card.id else { return false }
                                store.move(id, toStatus: status, before: card.id)
                                return true
                            }
                    }
                    AddTaskField(board: board, status: status)
                }
                .padding(8)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(nsColor: .windowBackgroundColor).opacity(0.55))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(isTargeted ? status.color : Color.primary.opacity(0.06),
                              lineWidth: isTargeted ? 2 : 1)
        )
        .dropDestination(for: String.self) { items, _ in
            guard let id = items.first else { return false }
            store.move(id, toStatus: status)
            return true
        } isTargeted: { isTargeted = $0 }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Circle().fill(status.color).frame(width: 9, height: 9)
            Text(status.title).font(.system(size: 13, weight: .semibold))
            Text("\(cards.count)")
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 6).padding(.vertical, 1)
                .background(Capsule().fill(Color.primary.opacity(0.08)))
            Spacer()
            Button {
                let t = store.addTask(board: board, status: status, title: "New Task")
                store.openDetail(t.id)
            } label: { Image(systemName: "plus") }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("Add a task to \(status.title)")
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
        .overlay(alignment: .top) {
            UnevenRoundedRectangle(topLeadingRadius: 12, bottomLeadingRadius: 0,
                                   bottomTrailingRadius: 0, topTrailingRadius: 12,
                                   style: .continuous)
                .fill(status.color)
                .frame(height: 3)
        }
    }
}

/// Inline quick-add at the bottom of a column.
private struct AddTaskField: View {
    @EnvironmentObject var store: AppStore
    let board: String
    let status: TaskStatus
    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "plus.circle.fill")
                .foregroundStyle(focused ? status.color : Color.secondary.opacity(0.6))
            TextField("Add a task", text: $text)
                .textFieldStyle(.plain)
                .focused($focused)
                .onSubmit(add)
        }
        .padding(.horizontal, 10).padding(.vertical, 9)
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(Color.primary.opacity(focused ? 0.06 : 0.03))
        )
    }

    private func add() {
        let t = text.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty else { return }
        store.addTask(board: board, status: status, title: t)
        text = ""
        focused = true
    }
}
