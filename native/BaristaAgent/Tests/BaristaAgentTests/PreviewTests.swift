import XCTest
@testable import barista_agent

final class PreviewTests: XCTestCase {
  private var folder: URL!

  override func setUpWithError() throws {
    folder = FileManager.default.temporaryDirectory.appendingPathComponent("barista-preview-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
  }

  override func tearDownWithError() throws {
    try? FileManager.default.removeItem(at: folder)
  }

  private func write(_ name: String, _ data: Data) throws -> URL {
    let url = folder.appendingPathComponent(name)
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try data.write(to: url)
    return url
  }

  func testOrgBecomesMarkdown() {
    let org = """
    #+TITLE: Music log
    #+STARTUP: overview
    * TODO Session one :music:asm:
    :PROPERTIES:
    :ID: 1234
    :END:
    Made *real* progress on =spc.asm=, see [[https://example.com][docs]] and [[file:notes.org]].
    Related: [[Tech Debt & Fixes]], [[*Steps][the steps]], [[file:My Notes/plan.org][plan]].
    ** Steps
    - [X] tune
    + loop
    #+begin_src asm
    LDA #$01 ; *not bold* =not code=
    #+end_src
    |---+---|
    | a | b |
    |---+---|
    | 1 | 2 |
    |---+---|
    #+begin_quote
    Keep it short.
    #+end_quote
    # a comment
    """
    let markdown = Org.markdown(org)
    XCTAssertEqual(markdown.components(separatedBy: "\n"), [
      "# Music log",
      "# TODO Session one",
      "Made **real** progress on `spc.asm`, see [docs](<https://example.com>) and [notes.org](<notes.org>).",
      "Related: Tech Debt & Fixes, the steps, [plan](<My Notes/plan.org>).",
      "## Steps",
      "- [X] tune",
      "+ loop",
      "```asm",
      "LDA #$01 ; *not bold* =not code=",
      "```",
      "| a | b |",
      "|---|---|",
      "| 1 | 2 |",
      "> Keep it short.",
      "",
    ])
    let blocks = Markdown.parse(markdown)
    XCTAssertTrue(blocks.contains { if case .table = $0 { return true }; return false }, "the table renders as one")
    let link = try? AttributedString(markdown: "[plan](<My Notes/plan.org>)").runs.compactMap(\.link).first
    XCTAssertEqual(link?.path, "My Notes/plan.org", "a target with spaces still parses as a link")
  }

  /// A 64 KB LoROM with a correct checksum: the checksum and its complement
  /// always add 0x1FE to the sum, so any value can be written after summing.
  private func loROM(title: String = "ORACLE OF SECRETS") -> Data {
    var rom = [UInt8](repeating: 0, count: 0x10000)
    for index in 0..<rom.count where index % 7 == 0 { rom[index] = UInt8(index % 251) }
    let header = 0x7FC0
    let padded = Array(title.utf8.prefix(21)) + Array(repeating: 0x20, count: max(0, 21 - title.utf8.count))
    rom.replaceSubrange(header..<header + 21, with: padded)
    rom[header + 21] = 0x30
    rom[header + 23] = 0x06
    rom[header + 24] = 0x03
    rom[header + 25] = 0x01
    rom[header + 27] = 0x02
    rom.replaceSubrange(header + 28..<header + 32, with: [0xFF, 0xFF, 0x00, 0x00])
    let sum = UInt16(truncatingIfNeeded: rom.reduce(UInt32(0)) { $0 &+ UInt32($1) })
    let complement = sum ^ 0xFFFF
    rom.replaceSubrange(header + 28..<header + 32,
                        with: [UInt8(complement & 0xFF), UInt8(complement >> 8), UInt8(sum & 0xFF), UInt8(sum >> 8)])
    return Data(rom)
  }

  func testSNESHeaderIsFoundAndItsChecksumChecked() throws {
    let header = try XCTUnwrap(SNESHeader.parse(loROM()))
    XCTAssertEqual(header.title, "ORACLE OF SECRETS")
    XCTAssertEqual(header.mapping, "LoROM")
    XCTAssertTrue(header.fastROM)
    XCTAssertEqual(header.romKB, 64)
    XCTAssertEqual(header.sramKB, 8)
    XCTAssertEqual(header.region, "North America")
    XCTAssertEqual(header.version, 2)
    XCTAssertTrue(header.complementMatches)
    XCTAssertEqual(header.computed, header.checksum)
    XCTAssertFalse(header.copierHeader)

    let copied = try XCTUnwrap(SNESHeader.parse(Data(count: 512) + loROM()))
    XCTAssertTrue(copied.copierHeader)
    XCTAssertEqual(copied.computed, copied.checksum, "the copier header is not summed")

    var patched = loROM()
    patched[0x100] &+= 1
    XCTAssertNotEqual(SNESHeader.parse(patched)?.computed, SNESHeader.parse(patched)?.checksum)
    XCTAssertNil(SNESHeader.parse(patched + Data(count: 3000))?.computed, "no standard mirroring for this size")
    XCTAssertNil(SNESHeader.parse(Data(count: 0x10000)), "zeros are not a ROM")
    XCTAssertNil(SNESHeader.parse(Data(count: 100)))
  }

  private func uncolored(_ content: PreviewContent) -> PreviewContent {
    guard case .text(let text, let note, _) = content else { return content }
    return .text(text, note: note)
  }

  /// Each colored run's text and token, in order.
  private func colored(_ source: String, _ ext: String) -> [(String, SyntaxToken)] {
    (Syntax.of(extension: ext)?.spans(source) ?? []).map { ((source as NSString).substring(with: $0.range), $0.token) }
  }

  func testAsarSyntax() {
    let source = """
    Main:
      LDA.w #$0010 ; load "x"
    .loop
      JSL !Routine
      %SetFlag(1)
      db "a;b", %0101
      org $008000
      LDA table,x
    """
    let runs = colored(source, "asm")
    XCTAssertEqual(runs.map(\.0), ["Main:", "LDA.w", "#$0010", "; load \"x\"", ".loop", "JSL", "!Routine",
                                   "%SetFlag", "1", "db", "\"a;b\"", "%0101", "org", "$008000", "LDA"])
    XCTAssertEqual(runs.map(\.1), [.label, .keyword, .number, .comment, .label, .keyword, .label,
                                   .label, .number, .keyword, .string, .number, .keyword, .number, .keyword])
  }

  func testCommentsAndStringsDoNotStartInsideEachOther() {
    let runs = colored("let s = \"// not\" // real\nif x == 0x1F { return }", "swift")
    XCTAssertEqual(runs.map(\.0), ["let", "\"// not\"", "// real", "if", "0x1F", "return"])
    XCTAssertEqual(runs.map(\.1), [.keyword, .string, .comment, .keyword, .number, .keyword])
    XCTAssertNil(Syntax.of(extension: "txt"))
  }

  func testTextJSONAndBinaryPreviews() throws {
    let code = try write("a.asm", Data("LDA #$01\n".utf8))
    guard case .text("LDA #$01\n", nil, let spans) = Preview.load(code) else { return XCTFail("code shows as text") }
    XCTAssertEqual(spans.map(\.token), [.keyword, .number], "and is colored")
    XCTAssertEqual(Preview.load(try write("plain.txt", Data("hi\n".utf8))), .text("hi\n", note: nil))
    XCTAssertEqual(Preview.load(try write("blob.bin", Data([0x4C, 0x00, 0x01]))), .details)
    XCTAssertEqual(Preview.load(try write("empty.txt", Data())), .details)

    let minified = try write("m.json", Data(#"{"b":1,"a":"x/y"}"#.utf8))
    XCTAssertEqual(uncolored(Preview.load(minified)),
                   .text("{\n  \"a\" : \"x/y\",\n  \"b\" : 1\n}", note: "Minified JSON, shown indented with keys sorted"))
    let indented = "{\n  \"z\": 1\n}\n"
    XCTAssertEqual(uncolored(Preview.load(try write("i.json", Data(indented.utf8)))), .text(indented, note: nil),
                   "indented JSON keeps its own key order")
    guard case .text(_, let note?, _) = Preview.load(try write("bad.json", Data("{\"a\":".utf8))) else {
      return XCTFail("invalid JSON still shows, with a note")
    }
    XCTAssertTrue(note.hasPrefix("Not valid JSON"))

    let big = try write("big.log", Data(repeating: UInt8(ascii: "x"), count: Preview.textLimit + 10))
    guard case .text(let text, let cut?, _) = Preview.load(big) else { return XCTFail("a long log is cut") }
    XCTAssertEqual(text.utf8.count, Preview.textLimit)
    XCTAssertTrue(cut.hasPrefix("Showing the first"))

    XCTAssertEqual(Preview.decodeText(Data("é".utf8).prefix(1)), "", "a cut inside a character drops it")
    guard case .document(let blocks) = Preview.load(try write("n.org", Data("* Plan\n".utf8))) else {
      return XCTFail("org renders as a document")
    }
    XCTAssertEqual(blocks, [.heading(level: 1, text: "Plan")])
    guard case .rom = Preview.load(try write("game.sfc", loROM())) else { return XCTFail("a ROM shows its header") }
  }

  func testContextReadsEntryPointsAndFindsTheNearestRoot() throws {
    let context = folder.appendingPathComponent("repo/.context")
    _ = try write("repo/.context/scratchpad/state.md", Data("# State\nWorking on menus.\n".utf8))
    _ = try write("repo/.context/scratchpad/inbox.md", Data("x".utf8))
    _ = try write("repo/.context/scratchpad/deep/huge/ignored.md", Data("x".utf8))
    _ = try write("repo/.context/items/task-a.json",
                  Data(#"{"title":"Fix menu","status":"in_progress","assigned_to":"codex","priority":1}"#.utf8))
    _ = try write("repo/.context/items/task-b.json", Data(#"{"title":"Old","status":"done"}"#.utf8))
    _ = try write("repo/.context/items/task-c.json", Data(#"{"title":"Urgent","status":"pending","priority":0}"#.utf8))
    _ = try write("repo/.context/hivemind/codex/20261027T010000-a.json",
                  Data(#"{"from":"codex","to":"claude","type":"status","timestamp":"2026-10-27T01:00:00.5+00:00","payload":{"text":"Built"}}"#.utf8))
    _ = try write("repo/.context/handoffs/menu_2026-10-27/README.md", Data("x".utf8))
    _ = try write("repo/Core/.context/items/.keep", Data())
    let nested = folder.appendingPathComponent("repo/Core/Menu")
    try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)

    XCTAssertEqual(AFSContext.find(from: nested)?.path, context.standardizedFileURL.path,
                   "an empty scaffold on the way up is passed over")
    XCTAssertEqual(AFSContext.find(from: context.appendingPathComponent("scratchpad"))?.path,
                   context.standardizedFileURL.path, "browsing inside .context finds it too")

    let loaded = AFSContext.load(context)
    XCTAssertEqual(loaded.state.first, .heading(level: 1, text: "State"))
    XCTAssertEqual(loaded.active.map(\.title), ["Urgent", "Fix menu"], "by priority")
    XCTAssertEqual(loaded.active.last?.owner, "codex")
    XCTAssertEqual(loaded.finishedCount, 1)
    XCTAssertEqual(loaded.messages.map(\.text), ["Built"])
    XCTAssertEqual(loaded.messages.first?.to, "claude")
    XCTAssertEqual(loaded.notes.map(\.lastPathComponent), ["inbox.md"], "top level only, state.md apart")
    XCTAssertEqual(loaded.handoffs.map(\.lastPathComponent), ["menu_2026-10-27"])
    XCTAssertTrue(AFSContext.load(folder.appendingPathComponent("missing")).isEmpty)
  }
}