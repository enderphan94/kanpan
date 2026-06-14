import SwiftUI

/// A board card. Quiet by default — footer icons appear only when a field is
/// set, so a board of plain tasks stays scannable (a pattern from Planner).
struct TaskCardView: View {
    @EnvironmentObject var store: AppStore
    let task: KTask
    @State private var hovering = false

    private var progress: (done: Int, total: Int) { store.deepProgress(of: task.id) }
    private var isDone: Bool { task.status == .completed }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            if !task.labels.isEmpty { LabelPills(labels: task.labels) }

            HStack(alignment: .top, spacing: 8) {
                completeButton
                Text(task.title.isEmpty ? "Untitled" : task.title)
                    .font(.system(size: 13, weight: .medium))
                    .strikethrough(isDone, color: .secondary)
                    .foregroundStyle(isDone ? .secondary : .primary)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }

            footer
        }
        .padding(.vertical, 10)
        .padding(.leading, 12)
        .padding(.trailing, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            Theme.surface.overlay(task.status.color.opacity(0.06))
        )
        .overlay(Rectangle().fill(task.status.color).frame(width: 3), alignment: .leading)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Theme.hairline)
        )
        .shadow(color: .black.opacity(hovering ? 0.10 : 0.04), radius: hovering ? 5 : 2, y: 1)
        .opacity(isDone ? 0.85 : 1)
        .contentShape(Rectangle())
        .onTapGesture { store.openDetail(task.id) }
        .onHover { hovering = $0 }
        .draggable(task.id)
        .contextMenu { contextMenu }
    }

    private var completeButton: some View {
        Button {
            store.setStatus(task.id, isDone ? .inProgress : .completed)
        } label: {
            Image(systemName: isDone ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 15))
                .foregroundStyle(isDone ? Color.green : Color.secondary.opacity(0.55))
        }
        .buttonStyle(.plain)
        .help(isDone ? "Mark as in progress" : "Mark as completed")
    }

    @ViewBuilder private var footer: some View {
        let hasFooter = task.due != nil || task.priority.showsFlag || progress.total > 0
        if hasFooter {
            HStack(spacing: 12) {
                if let due = task.due { DueChip(due: due, overdue: task.isOverdue) }
                PriorityFlag(priority: task.priority)
                if progress.total > 0 { ProgressBadge(done: progress.done, total: progress.total) }
                Spacer(minLength: 0)
            }
            .padding(.leading, 23) // align under the title, past the checkmark
        }
    }

    @ViewBuilder private var contextMenu: some View {
        Menu("Status") {
            ForEach(TaskStatus.allCases) { s in
                Button { store.setStatus(task.id, s) } label: { Label(s.title, systemImage: s.symbol) }
            }
        }
        Menu("Priority") {
            ForEach(Priority.allCases) { p in
                Button {
                    var t = task; t.priority = p; store.commit(t, immediate: true)
                } label: { Label(p.title, systemImage: p.symbol) }
            }
        }
        Button("Open") { store.openDetail(task.id) }
        Divider()
        Button("Delete", role: .destructive) { store.delete(task.id) }
    }
}
