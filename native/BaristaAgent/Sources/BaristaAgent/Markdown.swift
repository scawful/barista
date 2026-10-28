import Foundation

/// A Markdown document split into blocks. Inline syntax (emphasis, code
/// spans, links) stays in each block's text for `AttributedString(markdown:)`,
/// which handles inlines well but drops block structure.
enum MarkdownBlock: Equatable {
  case heading(level: Int, text: String)
  case paragraph(String)
  case list([MarkdownListItem])
  case code(language: String, text: String)
  case quote([MarkdownBlock])
  case table(header: [String], alignments: [MarkdownAlignment], rows: [[String]])
  case image(alt: String, source: String)
  case rule
}

struct MarkdownListItem: Equatable {
  /// `nil` for a bullet, otherwise the item's number.
  var number: Int?
  /// Nesting depth from indentation: 0 at the margin.
  var depth: Int
  /// A task item's box, `nil` for a plain item.
  var checked: Bool?
  var text: String
}

enum MarkdownAlignment: Equatable {
  case leading, center, trailing
}

enum Markdown {
  static func parse(_ source: String) -> [MarkdownBlock] {
    var lines = source.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n")
    var blocks: [MarkdownBlock] = []
    if lines.first == "---", let end = lines.dropFirst().firstIndex(where: { $0 == "---" || $0 == "..." }) {
      blocks.append(.code(language: "yaml", text: lines[1..<end].joined(separator: "\n")))
      lines.removeSubrange(0...end)
    }
    return blocks + parseBlocks(lines)
  }

  /// Deeper `>` markers stay text, so a line of them can't exhaust the stack.
  static let maxQuoteDepth = 8

  private static func parseBlocks(_ lines: [String], quoteDepth: Int = 0) -> [MarkdownBlock] {
    var blocks: [MarkdownBlock] = []
    var index = 0
    while index < lines.count {
      let line = lines[index]
      let trimmed = line.trimmingCharacters(in: .whitespaces)
      if trimmed.isEmpty {
        index += 1
      } else if trimmed.hasPrefix("<!--") {
        while index < lines.count && !lines[index].contains("-->") { index += 1 }
        index += 1
      } else if let fence = fence(trimmed) {
        let indent = line.prefix { $0 == " " }.count
        var body: [String] = []
        index += 1
        while index < lines.count && !lines[index].trimmingCharacters(in: .whitespaces).hasPrefix(fence.marker) {
          body.append(String(lines[index].dropFirst(min(indent, lines[index].prefix { $0 == " " }.count))))
          index += 1
        }
        index += 1
        blocks.append(.code(language: fence.language, text: body.joined(separator: "\n")))
      } else if let heading = heading(trimmed) {
        blocks.append(heading)
        index += 1
      } else if isRule(trimmed) {
        blocks.append(.rule)
        index += 1
      } else if index + 1 < lines.count, trimmed.contains("|"),
                let alignments = delimiterRow(lines[index + 1]), alignments.count == cells(trimmed).count {
        let header = cells(trimmed)
        var rows: [[String]] = []
        index += 2
        while index < lines.count, lines[index].contains("|"),
              !lines[index].trimmingCharacters(in: .whitespaces).isEmpty {
          let row = cells(lines[index].trimmingCharacters(in: .whitespaces))
          rows.append((0..<header.count).map { $0 < row.count ? row[$0] : "" })
          index += 1
        }
        blocks.append(.table(header: header, alignments: alignments, rows: rows))
      } else if trimmed.hasPrefix(">"), quoteDepth < maxQuoteDepth {
        var inner: [String] = []
        while index < lines.count {
          let quoted = lines[index].trimmingCharacters(in: .whitespaces)
          guard quoted.hasPrefix(">") else { break }
          var text = quoted.dropFirst()
          if text.first == " " { text = text.dropFirst() }
          inner.append(String(text))
          index += 1
        }
        blocks.append(.quote(parseBlocks(inner, quoteDepth: quoteDepth + 1)))
      } else if listItem(line) != nil {
        var items: [MarkdownListItem] = []
        while index < lines.count {
          if let item = listItem(lines[index]) {
            items.append(item)
            index += 1
          } else if lines[index].trimmingCharacters(in: .whitespaces).isEmpty {
            // A blank line inside a loose list; the list goes on if an item follows.
            guard let next = lines[index...].firstIndex(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty }),
                  listItem(lines[next]) != nil else { break }
            index = next
          } else if !startsBlock(lines[index]), !items.isEmpty {
            items[items.count - 1].text += joiner(items[items.count - 1].text)
              + lines[index].trimmingCharacters(in: .whitespaces)
            index += 1
          } else {
            break
          }
        }
        blocks.append(.list(items))
      } else if let image = standaloneImage(trimmed) {
        blocks.append(image)
        index += 1
      } else {
        var text = ""
        while index < lines.count {
          let current = lines[index]
          var part = current.trimmingCharacters(in: .whitespaces)
          if part.isEmpty || (!text.isEmpty && startsBlock(current)) { break }
          // Two trailing spaces or a trailing backslash mark a hard break.
          var hardBreak = current.hasSuffix("  ")
          if part.hasSuffix("\\") {
            part.removeLast()
            hardBreak = true
          }
          text += (text.isEmpty ? "" : joiner(text)) + part + (hardBreak ? "\n" : "")
          index += 1
        }
        blocks.append(.paragraph(text.trimmingCharacters(in: .newlines)))
      }
    }
    return blocks
  }

  /// A soft line break reads as a space; a hard one already ends the text.
  private static func joiner(_ text: String) -> String {
    text.hasSuffix("\n") ? "" : " "
  }

  /// Lines that end a paragraph or a list item's continuation.
  private static func startsBlock(_ line: String) -> Bool {
    let trimmed = line.trimmingCharacters(in: .whitespaces)
    return fence(trimmed) != nil || heading(trimmed) != nil || isRule(trimmed)
      || trimmed.hasPrefix(">") || listItem(line) != nil
  }

  private static func fence(_ trimmed: String) -> (marker: String, language: String)? {
    for mark in ["```", "~~~"] where trimmed.hasPrefix(mark) {
      let run = trimmed.prefix { $0 == mark.first }
      return (String(run), trimmed.dropFirst(run.count).trimmingCharacters(in: .whitespaces))
    }
    return nil
  }

  private static func heading(_ trimmed: String) -> MarkdownBlock? {
    let hashes = trimmed.prefix { $0 == "#" }.count
    guard (1...6).contains(hashes) else { return nil }
    let rest = trimmed.dropFirst(hashes)
    guard rest.isEmpty || rest.first == " " else { return nil }
    var text = rest.trimmingCharacters(in: .whitespaces)
    // A closing run of #s is decoration.
    if let closing = text.range(of: #"\s+#+$"#, options: .regularExpression) { text.removeSubrange(closing) }
    return .heading(level: hashes, text: text)
  }

  private static func isRule(_ trimmed: String) -> Bool {
    let marks = trimmed.filter { $0 != " " }
    guard marks.count >= 3, let mark = marks.first, "-*_".contains(mark) else { return false }
    return marks.allSatisfy { $0 == mark }
  }

  private static let itemPattern = try! NSRegularExpression(pattern: #"^(\s*)([-*+]|(\d{1,9})[.)])\s+(.*)$"#)

  private static func listItem(_ line: String) -> MarkdownListItem? {
    let range = NSRange(line.startIndex..., in: line)
    guard let match = itemPattern.firstMatch(in: line, range: range) else { return nil }
    func group(_ index: Int) -> String? {
      Range(match.range(at: index), in: line).map { String(line[$0]) }
    }
    let indent = (group(1) ?? "").reduce(0) { $0 + ($1 == "\t" ? 4 : 1) }
    var text = group(4) ?? ""
    var checked: Bool?
    for (box, value) in [("[ ] ", false), ("[x] ", true), ("[X] ", true)] where text.hasPrefix(box) {
      checked = value
      text.removeFirst(box.count)
    }
    return MarkdownListItem(number: group(3).flatMap(Int.init), depth: indent / 2, checked: checked, text: text)
  }

  private static func delimiterRow(_ line: String) -> [MarkdownAlignment]? {
    let row = cells(line.trimmingCharacters(in: .whitespaces))
    guard !row.isEmpty else { return nil }
    var alignments: [MarkdownAlignment] = []
    for cell in row {
      let dashes = cell.trimmingCharacters(in: CharacterSet(charactersIn: ":"))
      guard !dashes.isEmpty, dashes.allSatisfy({ $0 == "-" }) else { return nil }
      switch (cell.hasPrefix(":"), cell.hasSuffix(":")) {
      case (true, true): alignments.append(.center)
      case (false, true): alignments.append(.trailing)
      default: alignments.append(.leading)
      }
    }
    return alignments
  }

  /// A table row's cells. Pipes inside code spans or escaped as `\|` stay text.
  private static func cells(_ row: String) -> [String] {
    var body = Substring(row)
    if body.hasPrefix("|") { body = body.dropFirst() }
    if body.hasSuffix("|") && !body.hasSuffix("\\|") { body = body.dropLast() }
    var cells: [String] = []
    var current = ""
    var inCode = false
    var escaped = false
    for character in body {
      if escaped {
        current.append(character == "|" ? "|" : "\\\(character)")
        escaped = false
      } else if character == "\\" {
        escaped = true
      } else if character == "`" {
        inCode.toggle()
        current.append(character)
      } else if character == "|" && !inCode {
        cells.append(current.trimmingCharacters(in: .whitespaces))
        current = ""
      } else {
        current.append(character)
      }
    }
    cells.append(current.trimmingCharacters(in: .whitespaces))
    return cells
  }

  private static let imagePattern = try! NSRegularExpression(pattern: #"^!\[([^\]]*)\]\(<?([^)\s>]+)>?(?:\s+"[^"]*")?\)$"#)

  private static func standaloneImage(_ trimmed: String) -> MarkdownBlock? {
    let range = NSRange(trimmed.startIndex..., in: trimmed)
    guard let match = imagePattern.firstMatch(in: trimmed, range: range),
          let alt = Range(match.range(at: 1), in: trimmed),
          let source = Range(match.range(at: 2), in: trimmed)
    else { return nil }
    return .image(alt: String(trimmed[alt]), source: String(trimmed[source]))
  }
}
