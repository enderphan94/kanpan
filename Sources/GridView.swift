import SwiftUI

/// A spreadsheet-style view of all top-level tasks in a board, with inline
/// editing of status, priority, and due date. Double-click (or the context
/// menu) opens a task to manage its sub-tasks.
struct GridView: View {
    @EnvironmentObject var store: AppStore
    let board: String
    @State private var selection: KTask.ID?

    private var rows: [KTask] { store.allCards(board: board) }

    var body: some View {
        if rows.isEmpty {
            EmptyStateView(icon: "tablecells", title: "No tasks here",
                           message: "Add a task to get started.",
                           actionTitle: "New Task") { store.requestNewTask() }
        } else {
            Table(rows, selection: $selection) {
                TableColumn("") { task in CompleteToggle(task: task) }
                    .width(24)
                TableColumn("Task") { task in
                    Button {
                        store.openDetail(task.id)
                    } label: {
                        Text(task.title.isEmpty ? "Untitled" : task.title)
                            .strikethrough(task.status == .completed, color: .secondary)
                            .foregroundStyle(task.status == .completed ? .secondary : .primary)
                    }
                    .buttonStyle(.plain)
                }
                .width(min: 180, ideal: 300)
                TableColumn("Status") { task in
                    StatusMenu(status: store.binding(task.id).status)
                }
                .width(140)
                TableColumn("Priority") { task in
                    PriorityMenu(priority: store.binding(task.id).priority)
                }
                .width(110)
                TableColumn("Due") { task in DueCell(task: task) }
                    .width(150)
                TableColumn("Sub-tasks") { task in
                    let p = store.progress(of: task.id)
                    ProgressBadge(done: p.done, total: p.total)
                }
                .width(120)
                TableColumn("Labels") { task in LabelPills(labels: task.labels, max: 4) }
                    .width(min: 100, ideal: 160)
            }
            .contextMenu(forSelectionType: KTask.ID.self) { ids in
                if let id = ids.first {
                    Button("Open") { store.openDetail(id) }
                    Menu("Status") {
                        ForEach(TaskStatus.allCases) { s in
                            Button(s.title) { store.setStatus(id, s) }
                        }
                    }
                    Divider()
                    Button("Delete", role: .destructive) { store.delete(id) }
                }
            } primaryAction: { ids in
                if let id = ids.first { store.openDetail(id) }
            }
        }
    }
}

private struct CompleteToggle: View {
    @EnvironmentObject var store: AppStore
    let task: KTask
    var body: some View {
        Button {
            store.setStatus(task.id, task.status == .completed ? .inProgress : .completed)
        } label: {
            Image(systemName: task.status == .completed ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(task.status == .completed ? Color.green : Color.secondary.opacity(0.55))
        }
        .buttonStyle(.plain)
    }
}

private struct DueCell: View {
    @EnvironmentObject var store: AppStore
    let task: KTask
    var body: some View {
        HStack(spacing: 4) {
            if let due = task.due {
                DatePicker("", selection: Binding(
                    get: { due },
                    set: { setDue($0) }), displayedComponents: .date)
                    .labelsHidden()
                    .datePickerStyle(.field)
                    .foregroundStyle(task.isOverdue ? .red : .primary)
                Button { setDue(nil) } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
            } else {
                Button("Add date") { setDue(Calendar.current.startOfDay(for: Date())) }
                    .buttonStyle(.link)
                    .font(.caption)
            }
        }
    }

    private func setDue(_ date: Date?) {
        var t = task
        t.due = date.map { Calendar.current.startOfDay(for: $0) }
        store.commit(t, immediate: true)
    }
}
