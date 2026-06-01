import SwiftUI

/// The card detail sheet. For a top-level task it also hosts the sub-task
/// manager (one level deep) with a roll-up progress bar; drilling into a
/// sub-task pushes it onto the breadcrumb so it can be edited as a full card.
struct TaskDetailView: View {
    @EnvironmentObject var store: AppStore

    var body: some View {
        if let id = store.detailStack.last, store.task(id) != nil {
            DetailBody(taskID: id)
        } else {
            VStack(spacing: 12) {
                Text("This task no longer exists.").foregroundStyle(.secondary)
                Button("Close") { store.closeDetail() }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

private struct DetailBody: View {
    @EnvironmentObject var store: AppStore
    let taskID: String
    @State private var previewing = false

    private var task: KTask {
        store.task(taskID) ?? KTask.new(boardID: "", status: .notStarted, title: "", order: 0)
    }
    private var bind: Binding<KTask> { store.binding(taskID) }
    private var subtasks: [KTask] { store.subtasks(of: taskID) }
    private var isTopLevel: Bool { task.parentID == nil }

    var body: some View {
        VStack(spacing: 0) {
            topBar
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    titleField
                    fieldsRow
                    LabelEditor(labels: bind.labels)
                    notesSection
                    if isTopLevel { subtaskSection }
                    metaFooter
                }
                .padding(20)
            }
        }
    }

    // MARK: Top bar (breadcrumb + close)

    private var topBar: some View {
        HStack {
            breadcrumb
            Spacer()
            Button {
                store.closeDetail()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.title3).foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.cancelAction)
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
    }

    private var breadcrumb: some View {
        HStack(spacing: 5) {
            Button(task.boardID) { store.closeDetail() }
                .buttonStyle(.plain).foregroundStyle(.secondary)
            ForEach(Array(store.detailStack.enumerated()), id: \.offset) { idx, id in
                Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.tertiary)
                let isLast = idx == store.detailStack.count - 1
                Button(store.task(id)?.title.nonEmpty ?? "Untitled") {
                    store.detailStack = Array(store.detailStack.prefix(idx + 1))
                }
                .buttonStyle(.plain)
                .foregroundStyle(isLast ? .primary : .secondary)
                .fontWeight(isLast ? .semibold : .regular)
            }
        }
        .font(.subheadline)
        .lineLimit(1)
    }

    // MARK: Fields

    private var titleField: some View {
        TextField("Task title", text: bind.title, axis: .vertical)
            .textFieldStyle(.plain)
            .font(.system(size: 22, weight: .semibold))
            .lineLimit(1...3)
    }

    private var fieldsRow: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 16) {
                labeledField("Status") { StatusMenu(status: bind.status) }
                labeledField("Priority") { PriorityMenu(priority: bind.priority) }
                Spacer()
            }
            HStack(spacing: 16) {
                labeledField("Start") { DateField(date: bind.start) }
                labeledField("Due") { DateField(date: bind.due) }
                Spacer()
            }
        }
    }

    private func labeledField<Content: View>(_ title: String, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title.uppercased())
                .font(.system(size: 10, weight: .semibold)).foregroundStyle(.tertiary)
            content()
        }
    }

    // MARK: Notes

    private var notesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("NOTES").font(.system(size: 10, weight: .semibold)).foregroundStyle(.tertiary)
                Spacer()
                Picker("", selection: $previewing) {
                    Text("Write").tag(false)
                    Text("Preview").tag(true)
                }
                .pickerStyle(.segmented).fixedSize().controlSize(.small)
            }
            if previewing {
                ScrollView {
                    MarkdownContent(text: task.notes.nonEmpty ?? "_Nothing yet — switch to Write._")
                        .padding(12)
                }
                .frame(minHeight: 160, maxHeight: 320)
                .background(Color.primary.opacity(0.03))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            } else {
                TextEditor(text: bind.notes)
                    .font(.system(size: 13, design: .monospaced))
                    .frame(minHeight: 160, maxHeight: 320)
                    .scrollContentBackground(.hidden)
                    .padding(8)
                    .background(Color.primary.opacity(0.03))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.primary.opacity(0.08)))
            }
        }
    }

    // MARK: Sub-tasks

    private var subtaskSection: some View {
        let p = store.progress(of: taskID)
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("SUB-TASKS").font(.system(size: 10, weight: .semibold)).foregroundStyle(.tertiary)
                Spacer()
                if p.total > 0 {
                    Text("\(p.done) of \(p.total) done")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            if p.total > 0 {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.primary.opacity(0.10))
                        Capsule().fill(p.done == p.total ? Color.green : Color.accentColor)
                            .frame(width: geo.size.width * CGFloat(p.done) / CGFloat(max(p.total, 1)))
                    }
                }
                .frame(height: 6)
            }
            VStack(spacing: 2) {
                ForEach(subtasks) { sub in
                    SubtaskRow(sub: sub)
                    if sub.id != subtasks.last?.id { Divider() }
                }
            }
            AddSubtaskField(parent: task)
        }
        .padding(14)
        .background(Color.primary.opacity(0.03))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private var metaFooter: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Created \(DateFmt.label(task.created))")
                Text("Updated \(DateFmt.label(task.updated))")
            }
            .font(.caption2).foregroundStyle(.tertiary)
            Spacer()
            if !isTopLevel {
                Button {
                    store.promoteToTopLevel(taskID)
                    store.popDetail()
                } label: { Label("Promote to top-level", systemImage: "arrow.up") }
                    .buttonStyle(.bordered).controlSize(.small)
            }
            Button(role: .destructive) {
                store.delete(taskID)
                store.popDetail()
            } label: { Label("Delete", systemImage: "trash") }
                .buttonStyle(.bordered).controlSize(.small)
        }
    }
}

// MARK: - Sub-task row

private struct SubtaskRow: View {
    @EnvironmentObject var store: AppStore
    let sub: KTask
    private var isDone: Bool { sub.status == .completed }

    var body: some View {
        HStack(spacing: 8) {
            Button {
                store.setStatus(sub.id, isDone ? .notStarted : .completed)
            } label: {
                Image(systemName: isDone ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isDone ? Color.green : Color.secondary.opacity(0.55))
            }
            .buttonStyle(.plain)

            Circle().fill(sub.status.color).frame(width: 7, height: 7)

            TextField("Sub-task", text: store.binding(sub.id).title)
                .textFieldStyle(.plain)
                .strikethrough(isDone, color: .secondary)
                .foregroundStyle(isDone ? .secondary : .primary)

            Spacer(minLength: 6)

            if let due = sub.due { DueChip(due: due, overdue: sub.isOverdue) }

            Button { store.drillInto(sub.id) } label: {
                Image(systemName: "arrow.up.forward.square").foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("Open sub-task")
        }
        .padding(.vertical, 5)
        .contextMenu {
            Button("Open") { store.drillInto(sub.id) }
            Menu("Status") {
                ForEach(TaskStatus.allCases) { s in Button(s.title) { store.setStatus(sub.id, s) } }
            }
            Button("Promote to Top-level Task") { store.promoteToTopLevel(sub.id) }
            Divider()
            Button("Delete", role: .destructive) { store.delete(sub.id) }
        }
    }
}

private struct AddSubtaskField: View {
    @EnvironmentObject var store: AppStore
    let parent: KTask
    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "plus.circle.fill").foregroundStyle(.secondary)
            TextField("Add a sub-task", text: $text)
                .textFieldStyle(.plain)
                .focused($focused)
                .onSubmit(add)
        }
        .padding(.top, 6)
    }

    private func add() {
        let t = text.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty else { return }
        store.addTask(board: parent.boardID, status: .notStarted, title: t, parentID: parent.id)
        text = ""
        focused = true
    }
}

// MARK: - Field helpers

private struct DateField: View {
    @Binding var date: Date?
    var body: some View {
        HStack(spacing: 6) {
            if let d = date {
                DatePicker("", selection: Binding(
                    get: { d },
                    set: { date = Calendar.current.startOfDay(for: $0) }),
                    displayedComponents: .date)
                    .labelsHidden()
                Button { date = nil } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
            } else {
                Button("Set date") { date = Calendar.current.startOfDay(for: Date()) }
                    .buttonStyle(.link)
            }
        }
    }
}

/// Token-style label editor with wrapping pills and an inline add field.
struct LabelEditor: View {
    @Binding var labels: [String]
    @State private var newLabel = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("LABELS").font(.system(size: 10, weight: .semibold)).foregroundStyle(.tertiary)
            FlowLayout(spacing: 6) {
                ForEach(labels, id: \.self) { name in
                    HStack(spacing: 4) {
                        Text(name).font(.system(size: 11, weight: .semibold)).foregroundStyle(.white)
                        Button { labels.removeAll { $0 == name } } label: {
                            Image(systemName: "xmark").font(.system(size: 8, weight: .bold)).foregroundStyle(.white.opacity(0.85))
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(Capsule().fill(Theme.color(forLabel: name)))
                }
                TextField("Add label", text: $newLabel)
                    .textFieldStyle(.plain)
                    .frame(width: 90)
                    .onSubmit(addLabel)
            }
        }
    }

    private func addLabel() {
        let t = newLabel.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty, !labels.contains(where: { $0.caseInsensitiveCompare(t) == .orderedSame }) else {
            newLabel = ""; return
        }
        labels.append(t)
        newLabel = ""
    }
}

// MARK: - Flow layout

struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0
        for s in subviews {
            let size = s.sizeThatFits(.unspecified)
            if x + size.width > maxWidth, x > 0 {
                x = 0; y += rowHeight + spacing; rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: proposal.width ?? x, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) {
        var x: CGFloat = bounds.minX, y: CGFloat = bounds.minY, rowHeight: CGFloat = 0
        for s in subviews {
            let size = s.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX, x > bounds.minX {
                x = bounds.minX; y += rowHeight + spacing; rowHeight = 0
            }
            s.place(at: CGPoint(x: x, y: y), anchor: .topLeading, proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

