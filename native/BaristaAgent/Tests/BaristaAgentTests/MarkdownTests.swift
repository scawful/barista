import XCTest
@testable import barista_agent

final class MarkdownTests: XCTestCase {
  func testHeadingsParagraphsAndRules() {
    let blocks = Markdown.parse("""
      # Title #
      First line
      continues here.

      ##NotAHeading
      ---
      Hard break  
      next\\
      last
      """)
    XCTAssertEqual(blocks, [
      .heading(level: 1, text: "Title"),
      .paragraph("First line continues here."),
      .paragraph("##NotAHeading"),
      .rule,
      .paragraph("Hard break\nnext\nlast"),
    ])
  }

  func testListsKeepNumbersDepthTasksAndContinuations() {
    let blocks = Markdown.parse("""
      3. third
      4. fourth
         wraps
      - [x] done
        - [ ] nested todo

      - loose item
      After
      """)
    XCTAssertEqual(blocks, [
      .list([
        MarkdownListItem(number: 3, depth: 0, checked: nil, text: "third"),
        MarkdownListItem(number: 4, depth: 0, checked: nil, text: "fourth wraps"),
        MarkdownListItem(number: nil, depth: 0, checked: true, text: "done"),
        MarkdownListItem(number: nil, depth: 1, checked: false, text: "nested todo"),
        MarkdownListItem(number: nil, depth: 0, checked: nil, text: "loose item After"),
      ]),
    ])
  }

  func testFencedCodeKeepsBlankLinesAndMarkdownVerbatim() {
    let blocks = Markdown.parse("""
      ```swift
      let a = 1

      # not a heading
      ```
      ~~~~
      | not | a table |
      ~~~~
      """)
    XCTAssertEqual(blocks, [
      .code(language: "swift", text: "let a = 1\n\n# not a heading"),
      .code(language: "", text: "| not | a table |"),
    ])
  }

  func testTablesAlignAndKeepEscapedAndCodePipes() {
    let blocks = Markdown.parse("""
      | Name | Count | Note |
      |:-----|------:|:----:|
      | a \\| b | 2 | `x|y` |
      | short |
      """)
    XCTAssertEqual(blocks, [
      .table(header: ["Name", "Count", "Note"], alignments: [.leading, .trailing, .center],
             rows: [["a | b", "2", "`x|y`"], ["short", "", ""]]),
    ])
  }

  func testQuotesNestBlocksAndFrontMatterBecomesCode() {
    let blocks = Markdown.parse("""
      ---
      title: Notes
      ---
      > **Note**
      > - one
      <!-- hidden
      comment -->
      ![Diagram](images/flow.png "Flow")
      """)
    XCTAssertEqual(blocks, [
      .code(language: "yaml", text: "title: Notes"),
      .quote([.paragraph("**Note**"), .list([MarkdownListItem(number: nil, depth: 0, checked: nil, text: "one")])]),
      .image(alt: "Diagram", source: "images/flow.png"),
    ])
  }

  func testDelimiterRowMustMatchTheHeader() {
    XCTAssertEqual(Markdown.parse("a | b\n---"), [.paragraph("a | b"), .rule])
    XCTAssertEqual(Markdown.parse("| a |\n|---|"), [.table(header: ["a"], alignments: [.leading], rows: [])])
  }

  func testDeepQuotesStopNestingInsteadOfOverflowing() {
    var block = Markdown.parse(String(repeating: ">", count: 50_000) + " deep")
    for _ in 0..<Markdown.maxQuoteDepth {
      guard case .quote(let inner) = block.first, inner.count == 1 else { return XCTFail("expected a quote, got \(block)") }
      block = inner
    }
    guard case .paragraph(let text) = block.first else { return XCTFail("expected text, got \(block)") }
    XCTAssertTrue(text.hasSuffix("> deep"))
  }

  func testParagraphInlineImageIsNotABlockImage() {
    XCTAssertEqual(Markdown.parse("See ![x](a.png) here"), [.paragraph("See ![x](a.png) here")])
  }
}

final class ViewerKindTests: XCTestCase {
  func testKindsAndSiblings() throws {
    XCTAssertEqual(ViewerKind.of(URL(fileURLWithPath: "/a/README.MD")), .markdown)
    XCTAssertEqual(ViewerKind.of(URL(fileURLWithPath: "/a/shot.png")), .image)
    XCTAssertEqual(ViewerKind.of(URL(fileURLWithPath: "/a/photo.HEIC")), .image)
    XCTAssertNil(ViewerKind.of(URL(fileURLWithPath: "/a/main.swift")))
    XCTAssertNil(ViewerKind.of(URL(fileURLWithPath: "/a/doc.pdf")))

    let folder = FileManager.default.temporaryDirectory.appendingPathComponent("barista-viewer-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: folder) }
    for name in ["img10.png", "img2.jpg", "notes.md", ".hidden.png"] {
      try Data().write(to: folder.appendingPathComponent(name))
    }
    let siblings = ViewerKind.siblings(of: folder.appendingPathComponent("img2.jpg"))
    XCTAssertEqual(siblings.map(\.lastPathComponent), ["img2.jpg", "img10.png"])
  }
}
