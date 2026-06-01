import SwiftUI

/// Central palette. Deliberately muted-but-distinct: status is the primary
/// color signal, labels are secondary. "Colorful, but not too much."
enum Theme {
    // Status colors
    static func color(for status: TaskStatus) -> Color {
        switch status {
        case .notStarted: return Color(red: 0.56, green: 0.60, blue: 0.66) // slate
        case .inProgress: return Color(red: 0.22, green: 0.51, blue: 0.92)  // blue
        case .onHold:     return Color(red: 0.93, green: 0.64, blue: 0.20)  // amber
        case .completed:  return Color(red: 0.24, green: 0.70, blue: 0.44)  // green
        }
    }

    static func color(for priority: Priority) -> Color {
        switch priority {
        case .urgent:    return Color(red: 0.86, green: 0.25, blue: 0.25)   // red
        case .important: return Color(red: 0.93, green: 0.55, blue: 0.18)   // orange
        case .medium:    return Color.secondary
        case .low:       return Color(red: 0.45, green: 0.55, blue: 0.62)   // muted blue-gray
        }
    }

    /// A curated, pleasant label palette. A label's color is derived
    /// deterministically from its name so it stays stable across reloads
    /// without needing a separate color registry.
    static let labelPalette: [Color] = [
        Color(red: 0.85, green: 0.34, blue: 0.40), // rose
        Color(red: 0.92, green: 0.58, blue: 0.25), // orange
        Color(red: 0.86, green: 0.73, blue: 0.25), // gold
        Color(red: 0.40, green: 0.72, blue: 0.42), // green
        Color(red: 0.28, green: 0.66, blue: 0.66), // teal
        Color(red: 0.33, green: 0.56, blue: 0.90), // blue
        Color(red: 0.52, green: 0.45, blue: 0.85), // indigo
        Color(red: 0.74, green: 0.45, blue: 0.78), // purple
        Color(red: 0.62, green: 0.55, blue: 0.50), // taupe
        Color(red: 0.40, green: 0.62, blue: 0.55), // sage
    ]

    static func color(forLabel name: String) -> Color {
        let key = name.lowercased()
        var hash: UInt64 = 14695981039346656037 // FNV-1a, stable across runs
        for byte in key.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 1099511628211
        }
        return labelPalette[Int(hash % UInt64(labelPalette.count))]
    }
}

extension TaskStatus { var color: Color { Theme.color(for: self) } }
extension Priority   { var color: Color { Theme.color(for: self) } }
