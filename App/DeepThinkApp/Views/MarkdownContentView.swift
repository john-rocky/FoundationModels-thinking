import SwiftUI

// MARK: - Markdown Block Model

enum MarkdownBlock: Identifiable, Equatable {
    case heading(level: Int, text: String)
    case paragraph(text: String)
    case codeBlock(language: String?, code: String)
    case unorderedList(items: [String])
    case orderedList(items: [String])
    case blockquote(text: String)
    case thematicBreak

    var id: String {
        switch self {
        case .heading(let level, let text):
            "h\(level):\(text.hashValue)"
        case .paragraph(let text):
            "p:\(text.hashValue)"
        case .codeBlock(let language, let code):
            "code:\(language ?? ""):\(code.hashValue)"
        case .unorderedList(let items):
            "ul:\(items.hashValue)"
        case .orderedList(let items):
            "ol:\(items.hashValue)"
        case .blockquote(let text):
            "bq:\(text.hashValue)"
        case .thematicBreak:
            "hr"
        }
    }
}

// MARK: - Parser

enum MarkdownParser {
    static func parse(_ input: String) -> [MarkdownBlock] {
        let lines = input.components(separatedBy: "\n")
        var blocks: [MarkdownBlock] = []
        var index = 0

        while index < lines.count {
            let line = lines[index]

            // Fenced code block
            if line.hasPrefix("```") {
                let language = String(line.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                var codeLines: [String] = []
                index += 1
                while index < lines.count && !lines[index].hasPrefix("```") {
                    codeLines.append(lines[index])
                    index += 1
                }
                if index < lines.count { index += 1 } // skip closing ```
                blocks.append(.codeBlock(
                    language: language.isEmpty ? nil : language,
                    code: codeLines.joined(separator: "\n")
                ))
                continue
            }

            // Thematic break
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.count >= 3 && (trimmed.allSatisfy({ $0 == "-" }) ||
                                       trimmed.allSatisfy({ $0 == "*" }) ||
                                       trimmed.allSatisfy({ $0 == "_" })) && !trimmed.isEmpty {
                blocks.append(.thematicBreak)
                index += 1
                continue
            }

            // Heading
            if let headingMatch = parseHeading(line) {
                blocks.append(.heading(level: headingMatch.level, text: headingMatch.text))
                index += 1
                continue
            }

            // Blockquote
            if line.hasPrefix("> ") || line == ">" {
                var quoteLines: [String] = []
                while index < lines.count && (lines[index].hasPrefix("> ") || lines[index] == ">") {
                    let content = lines[index].hasPrefix("> ")
                        ? String(lines[index].dropFirst(2))
                        : ""
                    quoteLines.append(content)
                    index += 1
                }
                blocks.append(.blockquote(text: quoteLines.joined(separator: "\n")))
                continue
            }

            // Unordered list
            if isUnorderedListItem(line) {
                var items: [String] = []
                while index < lines.count && isUnorderedListItem(lines[index]) {
                    let item = stripUnorderedListPrefix(lines[index])
                    items.append(item)
                    index += 1
                }
                blocks.append(.unorderedList(items: items))
                continue
            }

            // Ordered list
            if isOrderedListItem(line) {
                var items: [String] = []
                while index < lines.count && isOrderedListItem(lines[index]) {
                    let item = stripOrderedListPrefix(lines[index])
                    items.append(item)
                    index += 1
                }
                blocks.append(.orderedList(items: items))
                continue
            }

            // Empty line — skip
            if trimmed.isEmpty {
                index += 1
                continue
            }

            // Paragraph — merge consecutive non-special lines
            var paragraphLines: [String] = []
            while index < lines.count {
                let l = lines[index]
                let t = l.trimmingCharacters(in: .whitespaces)
                if t.isEmpty || l.hasPrefix("```") || l.hasPrefix("# ") || l.hasPrefix("## ") ||
                    l.hasPrefix("### ") || l.hasPrefix("> ") || isUnorderedListItem(l) ||
                    isOrderedListItem(l) || isThematicBreak(t) {
                    break
                }
                paragraphLines.append(l)
                index += 1
            }
            if !paragraphLines.isEmpty {
                blocks.append(.paragraph(text: paragraphLines.joined(separator: "\n")))
            }
        }

        return blocks
    }

    private static func parseHeading(_ line: String) -> (level: Int, text: String)? {
        if line.hasPrefix("### ") {
            return (3, String(line.dropFirst(4)))
        } else if line.hasPrefix("## ") {
            return (2, String(line.dropFirst(3)))
        } else if line.hasPrefix("# ") {
            return (1, String(line.dropFirst(2)))
        }
        return nil
    }

    private static func isUnorderedListItem(_ line: String) -> Bool {
        line.hasPrefix("- ") || line.hasPrefix("* ") ||
        line.hasPrefix("  - ") || line.hasPrefix("  * ") ||
        line.hasPrefix("    - ") || line.hasPrefix("    * ")
    }

    private static func stripUnorderedListPrefix(_ line: String) -> String {
        var s = line
        // Strip leading whitespace for nested items
        while s.hasPrefix(" ") { s = String(s.dropFirst()) }
        if s.hasPrefix("- ") { return String(s.dropFirst(2)) }
        if s.hasPrefix("* ") { return String(s.dropFirst(2)) }
        return s
    }

    private static func isOrderedListItem(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .init(charactersIn: " "))
        guard let dotIndex = trimmed.firstIndex(of: ".") else { return false }
        let prefix = trimmed[trimmed.startIndex..<dotIndex]
        if prefix.isEmpty { return false }
        if !prefix.allSatisfy(\.isNumber) { return false }
        let afterDot = trimmed.index(after: dotIndex)
        if afterDot < trimmed.endIndex && trimmed[afterDot] == " " { return true }
        return afterDot == trimmed.endIndex
    }

    private static func stripOrderedListPrefix(_ line: String) -> String {
        let trimmed = line.trimmingCharacters(in: .init(charactersIn: " "))
        guard let dotIndex = trimmed.firstIndex(of: ".") else { return line }
        let afterDot = trimmed.index(after: dotIndex)
        if afterDot < trimmed.endIndex && trimmed[afterDot] == " " {
            return String(trimmed[trimmed.index(after: afterDot)...])
        }
        return String(trimmed[afterDot...])
    }

    private static func isThematicBreak(_ trimmed: String) -> Bool {
        trimmed.count >= 3 && (trimmed.allSatisfy({ $0 == "-" }) ||
                                trimmed.allSatisfy({ $0 == "*" }) ||
                                trimmed.allSatisfy({ $0 == "_" }))
    }
}

// MARK: - Inline Markdown Helper

private func inlineMarkdown(_ text: String) -> AttributedString {
    // Escape bare angle brackets that can cause AttributedString markdown parsing to fail
    let sanitized = text
        .replacingOccurrences(of: "<", with: "&lt;")
        .replacingOccurrences(of: ">", with: "&gt;")
    return (try? AttributedString(
        markdown: sanitized,
        options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
    )) ?? AttributedString(text)
}

// MARK: - MarkdownContentView

struct MarkdownContentView: View {
    let content: String

    var body: some View {
        let blocks = MarkdownParser.parse(content)
        VStack(alignment: .leading, spacing: 8) {
            ForEach(blocks) { block in
                MarkdownBlockView(block: block)
            }
        }
    }
}

// MARK: - Block Renderer

private struct MarkdownBlockView: View {
    let block: MarkdownBlock

    var body: some View {
        switch block {
        case .heading(let level, let text):
            Text(inlineMarkdown(text))
                .font(headingFont(level: level))

        case .paragraph(let text):
            Text(inlineMarkdown(text))

        case .codeBlock(let language, let code):
            CodeBlockView(language: language, code: code)

        case .unorderedList(let items):
            VStack(alignment: .leading, spacing: 4) {
                ForEach(Array(items.enumerated()), id: \.element) { _, item in
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text("\u{2022}")
                            .foregroundStyle(.secondary)
                        Text(inlineMarkdown(item))
                    }
                }
            }

        case .orderedList(let items):
            VStack(alignment: .leading, spacing: 4) {
                ForEach(Array(items.enumerated()), id: \.element) { index, item in
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text("\(index + 1).")
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                        Text(inlineMarkdown(item))
                    }
                }
            }

        case .blockquote(let text):
            HStack(spacing: 0) {
                RoundedRectangle(cornerRadius: 1)
                    .fill(Color.secondary.opacity(0.4))
                    .frame(width: 3)
                Text(inlineMarkdown(text))
                    .foregroundStyle(.secondary)
                    .padding(.leading, 10)
            }
            .padding(.vertical, 2)

        case .thematicBreak:
            Divider()
        }
    }

    private func headingFont(level: Int) -> Font {
        switch level {
        case 1: .title2.bold()
        case 2: .title3.bold()
        default: .headline.bold()
        }
    }
}

// MARK: - Code Block View

private struct CodeBlockView: View {
    let language: String?
    let code: String

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let language, !language.isEmpty {
                Text(language)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 12)
                    .padding(.top, 8)
                    .padding(.bottom, 4)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                Text(code)
                    .font(.system(.callout, design: .monospaced))
                    .textSelection(.enabled)
                    .padding(.horizontal, 12)
                    .padding(.vertical, language != nil ? 8 : 12)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppColors.tertiaryBackground)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}
