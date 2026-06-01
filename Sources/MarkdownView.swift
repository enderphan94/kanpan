import SwiftUI

/// A small, dependency-free markdown renderer for the notes *preview*. The
/// canonical content is always the raw `.md`; this just visualizes it.
/// Handles headings, bullet / numbered / task lists, block quotes, code
/// fences, horizontal rules, and inline emphasis / code / links.
struct MarkdownContent: View {
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(blocks().enumerated()), id: \.offset) { _, block in
                block.view
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .textSelection(.enabled)
    }

    private struct Block: Identifiable { let id = UUID(); let view: AnyView }

    private func blocks() -> [Block] {
        var result: [Block] = []
        let lines = text.components(separatedBy: "\n")
        var i = 0
        while i < lines.count {
            let line = lines[i]
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            // Fenced code block
            if trimmed.hasPrefix("```") {
                var code: [String] = []
                i += 1
                while i < lines.count, !lines[i].trimmingCharacters(in: .whitespaces).hasPrefix("```") {
                    code.append(lines[i]); i += 1
                }
                i += 1
                result.append(Block(view: AnyView(codeBlock(code.joined(separator: "\n")))))
                continue
            }

            if trimmed.isEmpty { i += 1; continue }

            // Horizontal rule
            if ["---", "***", "___"].contains(trimmed) {
                result.append(Block(view: AnyView(Divider().padding(.vertical, 2))))
                i += 1; continue
            }

            // Heading
            if let h = heading(trimmed) {
                result.append(Block(view: AnyView(h)))
                i += 1; continue
            }

            // Block quote
            if trimmed.hasPrefix(">") {
                let body = String(trimmed.dropFirst()).trimmingCharacters(in: .whitespaces)
                result.append(Block(view: AnyView(
                    HStack(spacing: 8) {
                        Rectangle().fill(Color.secondary.opacity(0.4)).frame(width: 3)
                        inline(body).foregroundStyle(.secondary)
                    }
                )))
                i += 1; continue
            }

            // Task list item
            if let (checked, body) = taskItem(trimmed) {
                result.append(Block(view: AnyView(
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Image(systemName: checked ? "checkmark.square.fill" : "square")
                            .foregroundStyle(checked ? Color.green : Color.secondary)
                        inline(body).strikethrough(checked, color: .secondary)
                            .foregroundStyle(checked ? .secondary : .primary)
                    }
                )))
                i += 1; continue
            }

            // Bullet list item
            if trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") || trimmed.hasPrefix("+ ") {
                let body = String(trimmed.dropFirst(2))
                result.append(Block(view: AnyView(
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("•").foregroundStyle(.secondary)
                        inline(body)
                    }
                )))
                i += 1; continue
            }

            // Numbered list item
            if let dot = trimmed.firstIndex(of: "."),
               Int(trimmed[..<dot]) != nil,
               trimmed.index(after: dot) < trimmed.endIndex,
               trimmed[trimmed.index(after: dot)] == " " {
                let num = String(trimmed[..<dot])
                let body = String(trimmed[trimmed.index(dot, offsetBy: 2)...])
                result.append(Block(view: AnyView(
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("\(num).").foregroundStyle(.secondary).monospacedDigit()
                        inline(body)
                    }
                )))
                i += 1; continue
            }

            // Paragraph
            result.append(Block(view: AnyView(inline(line))))
            i += 1
        }
        return result
    }

    private func heading(_ s: String) -> Text? {
        var level = 0
        var idx = s.startIndex
        while idx < s.endIndex, s[idx] == "#", level < 6 { level += 1; idx = s.index(after: idx) }
        guard level > 0, idx < s.endIndex, s[idx] == " " else { return nil }
        let body = String(s[s.index(after: idx)...])
        let size: Font = {
            switch level {
            case 1: return .system(size: 22, weight: .bold)
            case 2: return .system(size: 18, weight: .bold)
            case 3: return .system(size: 15, weight: .semibold)
            default: return .system(size: 13, weight: .semibold)
            }
        }()
        return inline(body).font(size)
    }

    private func taskItem(_ s: String) -> (Bool, String)? {
        let lower = s.lowercased()
        if lower.hasPrefix("- [ ] ") { return (false, String(s.dropFirst(6))) }
        if lower.hasPrefix("- [x] ") { return (true, String(s.dropFirst(6))) }
        return nil
    }

    private func codeBlock(_ code: String) -> some View {
        Text(code)
            .font(.system(.callout, design: .monospaced))
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(8)
            .background(Color.secondary.opacity(0.10))
            .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    private func inline(_ s: String) -> Text {
        if let attr = try? AttributedString(
            markdown: s,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)) {
            return Text(attr)
        }
        return Text(s)
    }
}
