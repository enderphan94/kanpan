import SwiftUI

enum DateFmt {
    private static let short: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "MMM d"; return f
    }()
    private static let withYear: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "MMM d, yyyy"; return f
    }()
    static func label(_ d: Date) -> String {
        Calendar.current.isDate(d, equalTo: Date(), toGranularity: .year)
            ? short.string(from: d) : withYear.string(from: d)
    }
}

/// Colored label chips, capped with a "+n" overflow.
struct LabelPills: View {
    let labels: [String]
    var max: Int = 3
    var body: some View {
        if !labels.isEmpty {
            HStack(spacing: 4) {
                ForEach(labels.prefix(max), id: \.self) { name in
                    Text(name)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Capsule().fill(Theme.color(forLabel: name)))
                }
                if labels.count > max {
                    Text("+\(labels.count - max)")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

struct DueChip: View {
    let due: Date
    let overdue: Bool
    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: "calendar")
            Text(DateFmt.label(due))
        }
        .font(.system(size: 11, weight: .medium))
        .foregroundStyle(overdue ? Color.red : Color.secondary)
    }
}

struct PriorityFlag: View {
    let priority: Priority
    var showLabel = false
    var body: some View {
        if priority.showsFlag {
            HStack(spacing: 3) {
                Image(systemName: priority.symbol)
                if showLabel { Text(priority.title) }
            }
            .font(.system(size: 11, weight: .bold))
            .foregroundStyle(priority.color)
        }
    }
}

/// Sub-task roll-up: a mini progress bar plus "done/total".
struct ProgressBadge: View {
    let done: Int
    let total: Int
    var body: some View {
        if total > 0 {
            HStack(spacing: 5) {
                Image(systemName: "checklist").font(.system(size: 10))
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.primary.opacity(0.10)).frame(width: 46, height: 5)
                    Capsule().fill(done == total ? Color.green : Color.accentColor)
                        .frame(width: 46 * CGFloat(done) / CGFloat(total), height: 5)
                }
                Text("\(done)/\(total)").font(.system(size: 10, weight: .medium))
            }
            .foregroundStyle(.secondary)
        }
    }
}

/// A reusable status picker rendered as a colored menu.
struct StatusMenu: View {
    @Binding var status: TaskStatus
    var body: some View {
        Menu {
            ForEach(TaskStatus.allCases) { s in
                Button { status = s } label: {
                    Label(s.title, systemImage: s.symbol)
                }
            }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: status.symbol)
                Text(status.title)
            }
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(.white)
            .padding(.horizontal, 9).padding(.vertical, 4)
            .background(Capsule().fill(status.color))
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }
}

struct PriorityMenu: View {
    @Binding var priority: Priority
    var body: some View {
        Menu {
            ForEach(Priority.allCases) { p in
                Button { priority = p } label: { Label(p.title, systemImage: p.symbol) }
            }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: priority.symbol)
                Text(priority.title)
            }
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(priority == .medium ? Color.secondary : priority.color)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }
}
