import Foundation

// MARK: - Status

/// The four project states. Their order here is also the left-to-right
/// column order on the Kanban board, so "Completed" always sits on the right.
enum TaskStatus: String, CaseIterable, Identifiable, Codable {
    case notStarted = "not-started"
    case inProgress = "in-progress"
    case onHold     = "on-hold"
    case completed  = "completed"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .notStarted: return "Not Started"
        case .inProgress: return "In Progress"
        case .onHold:     return "On Hold"
        case .completed:  return "Completed"
        }
    }

    /// SF Symbol used on cards and in menus.
    var symbol: String {
        switch self {
        case .notStarted: return "circle"
        case .inProgress: return "circle.lefthalf.filled"
        case .onHold:     return "pause.circle"
        case .completed:  return "checkmark.circle.fill"
        }
    }

    var isDone: Bool { self == .completed }

    /// Stable column ordering.
    var columnIndex: Int { Self.allCases.firstIndex(of: self) ?? 0 }
}

// MARK: - Priority

enum Priority: String, CaseIterable, Identifiable, Codable {
    case urgent, important, medium, low

    var id: String { rawValue }

    var title: String {
        switch self {
        case .urgent:    return "Urgent"
        case .important: return "Important"
        case .medium:    return "Medium"
        case .low:       return "Low"
        }
    }

    var symbol: String {
        switch self {
        case .urgent:    return "exclamationmark.2"
        case .important: return "exclamationmark"
        case .medium:    return "minus"
        case .low:       return "arrow.down"
        }
    }

    /// Only above/below-normal priorities draw an icon on the card, so a board
    /// of mostly-Medium tasks stays quiet (a pattern borrowed from Planner).
    var showsFlag: Bool { self != .medium }

    /// Sort rank used by "group by priority": Urgent first.
    var rank: Int {
        switch self {
        case .urgent:    return 0
        case .important: return 1
        case .medium:    return 2
        case .low:       return 3
        }
    }
}

// MARK: - Task

/// A single card. Parents and sub-tasks share this type; a sub-task simply has
/// a non-nil `parentID`. Nesting is capped at one level by the app logic.
struct KTask: Identifiable, Equatable {
    var id: String
    var title: String
    var notes: String                 // markdown body of the .md file
    var status: TaskStatus
    var priority: Priority
    var start: Date?
    var due: Date?
    var labels: [String]
    var parentID: String?             // nil = top-level card
    var order: Double                 // sort within a column (fractional for easy insert)
    var created: Date
    var updated: Date

    // Persistence bookkeeping (not written into the markdown body).
    var boardID: String               // board folder name this task lives in
    var relPath: String               // path of the .md file relative to vault root

    static func new(boardID: String, status: TaskStatus, title: String,
                    parentID: String? = nil, order: Double) -> KTask {
        let now = Date()
        return KTask(
            id: UUID().uuidString,
            title: title,
            notes: "",
            status: status,
            priority: .medium,
            start: nil,
            due: nil,
            labels: [],
            parentID: parentID,
            order: order,
            created: now,
            updated: now,
            boardID: boardID,
            relPath: ""               // assigned by the Vault on first write
        )
    }

    var isSubtask: Bool { parentID != nil }

    /// Due today or earlier and not yet completed.
    var isOverdue: Bool {
        guard let due, status != .completed else { return false }
        return Calendar.current.startOfDay(for: due) < Calendar.current.startOfDay(for: Date())
    }
}

extension String {
    /// nil when empty/whitespace, for `?? "fallback"` chains.
    var nonEmpty: String? {
        trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : self
    }
}

// MARK: - Board

/// A board is one folder directly under the vault root. Its display name is the
/// folder name. All of a board's task `.md` files live inside that folder.
struct Board: Identifiable, Equatable {
    var id: String        // folder name == identity == display name
    var order: Int
    var name: String { id }
}
