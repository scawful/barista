import Foundation

/// What a run of code is, for coloring the preview pane.
enum SyntaxToken: Equatable {
  case comment, string, number, keyword, label
}

struct SyntaxSpan: Equatable {
  let range: NSRange
  let token: SyntaxToken
}

/// Coloring by regular expressions, not parsing: enough to read code at a
/// glance. Comments and strings are found in one left-to-right pass, so a
/// quote inside a comment (or `;` inside a string) doesn't start the other;
/// later rules never recolor text an earlier one took.
struct Syntax {
  private struct Rule {
    let regex: NSRegularExpression
    let token: SyntaxToken
    /// The capture group that gets colored; 0 is the whole match.
    var group = 0
  }

  /// Comment and string alternatives, matched together.
  private let lexical: NSRegularExpression
  private let rules: [Rule]

  /// By name first: shell startup files, window manager configs, and build
  /// files have no extension to go by.
  static func of(_ url: URL) -> Syntax? {
    switch url.lastPathComponent.lowercased() {
    case ".zshrc", ".zshenv", ".zprofile", ".bashrc", ".bash_profile", ".profile", "yabairc", ".yabairc",
         "skhdrc", ".skhdrc", "makefile", "gnumakefile", "dockerfile", "brewfile", "justfile", "cmakelists.txt",
         ".gitignore", ".gitattributes", ".env", ".envrc":
      return hashes
    default:
      return of(extension: url.pathExtension)
    }
  }

  /// Nil for extensions without rules; their text shows uncolored.
  static func of(extension ext: String) -> Syntax? {
    switch ext.lowercased() {
    case "asm", "s", "inc", "a65": return asm
    case "swift", "c", "h", "cc", "cpp", "hpp", "m", "mm", "js", "jsx", "ts", "tsx", "rs", "go", "java",
         "kt", "cs", "zig", "css", "scss", "json", "jsonc":
      return slashes
    case "py", "sh", "bash", "zsh", "fish", "rb", "toml", "yaml", "yml", "conf", "cmake", "pl", "r":
      return hashes
    case "lua": return dashes
    case "el", "lisp", "scm", "clj": return lisp
    default: return nil
    }
  }

  func spans(_ text: String) -> [SyntaxSpan] {
    let whole = NSRange(location: 0, length: (text as NSString).length)
    var taken = IndexSet()
    var spans: [SyntaxSpan] = []
    for match in lexical.matches(in: text, range: whole) {
      let token: SyntaxToken = match.range(at: 1).location != NSNotFound ? .comment : .string
      spans.append(SyntaxSpan(range: match.range, token: token))
      taken.insert(integersIn: Range(match.range)!)
    }
    for rule in rules {
      for match in rule.regex.matches(in: text, range: whole) {
        let range = match.range(at: rule.group)
        guard range.location != NSNotFound, range.length > 0,
              !taken.intersects(integersIn: Range(range)!) else { continue }
        spans.append(SyntaxSpan(range: range, token: rule.token))
        taken.insert(integersIn: Range(range)!)
      }
    }
    return spans.sorted { $0.range.location < $1.range.location }
  }

  private init(comment: String, strings: String = #""(?:[^"\\\n]|\\.)*""#, rules: [Rule]) {
    lexical = Self.regex("(\(comment))|(\(strings))")
    self.rules = rules
  }

  private static func regex(_ pattern: String, caseless: Bool = false) -> NSRegularExpression {
    try! NSRegularExpression(pattern: pattern, options: caseless ? [.anchorsMatchLines, .caseInsensitive] : .anchorsMatchLines)
  }

  private static func words(_ list: String) -> String {
    list.split(separator: " ").joined(separator: "|")
  }

  /// 65816 as asar writes it.
  private static let asm: Syntax = {
    let mnemonics = words("""
      ADC AND ASL BCC BCS BEQ BIT BMI BNE BPL BRA BRK BRL BVC BVS CLC CLD CLI CLV CMP COP CPX CPY DEC DEX DEY \
      EOR INC INX INY JML JMP JSL JSR LDA LDX LDY LSR MVN MVP NOP ORA PEA PEI PER PHA PHB PHD PHK PHP PHX PHY \
      PLA PLB PLD PLP PLX PLY REP ROL ROR RTI RTL RTS SBC SEC SED SEI SEP STA STP STX STY STZ TAX TAY TCD TCS \
      TDC TRB TSB TSC TSX TXA TXS TXY TYA TYX WAI WDM XBA XCE
      """)
    let directives = words("""
      org base incsrc incbin db dw dl dd fill fillbyte pad padbyte skip macro endmacro if elseif else endif \
      while endwhile for endfor namespace pushpc pullpc pushbase pullbase assert print warnpc warn error \
      freespace freecode freedata autoclean prot table cleartable pushtable pulltable arch lorom hirom \
      exlorom exhirom sa1rom fullsa1rom sfxrom norom function struct endstruct check bank optimize \
      includefrom includeonce math rep
      """)
    return Syntax(comment: ";.*", rules: [
      Rule(regex: regex(#"^[ \t]*(\.?[A-Za-z_@][\w.]*:|\.[A-Za-z_]\w*|[+-]+(?=\s|$))"#), token: .label, group: 1),
      Rule(regex: regex(#"^[ \t]*(\#(directives))\b"#, caseless: true), token: .keyword, group: 1),
      Rule(regex: regex(#"(?<![\w.!%])(?:\#(mnemonics))(?:\.[bwl])?(?!\w)"#, caseless: true), token: .keyword),
      Rule(regex: regex(#"[!%][A-Za-z_]\w*"#), token: .label),
      Rule(regex: regex(#"#?\$[0-9A-Fa-f]+\b|#?%[01]+\b|#?\b\d+\b"#), token: .number),
    ])
  }()

  private static let keywords = words("""
    if else elif for while do return func function fn let var const class struct enum protocol interface \
    import from export package use def lambda in not and or is switch case default break continue true false \
    nil null None True False self this static public private fileprivate internal guard try catch throw \
    throws async await yield new delete type typealias impl trait pub mut match where with as then fi done \
    esac local extension override final defer
    """)
  private static let common = [
    Rule(regex: regex(#"\b(?:\#(keywords))\b"#), token: .keyword),
    Rule(regex: regex(#"\b(?:0[xX][0-9A-Fa-f]+|\d+(?:\.\d+)?)\b"#), token: .number),
  ]
  private static let quoted = #""(?:[^"\\\n]|\\.)*"|'(?:[^'\\\n]|\\.)*'"#
  private static let slashes = Syntax(comment: #"//.*|/\*[\s\S]*?\*/"#, strings: quoted, rules: common)
  private static let hashes = Syntax(comment: "#.*", strings: quoted, rules: common)
  private static let dashes = Syntax(comment: "--.*", strings: quoted, rules: common)
  /// `'` quotes a symbol in Lisp rather than opening a string.
  private static let lisp = Syntax(comment: ";.*", rules: [
    Rule(regex: regex(#"(?<=\()(?:defun|defmacro|defvar|defcustom|defconst|setq|setq-local|let\*?|lambda|if|when|unless|cond|progn|require|provide|use-package|define-key|add-hook|with-eval-after-load)(?=[\s)])"#),
         token: .keyword),
    Rule(regex: regex(#"(?<![\w-])-?\d+(?:\.\d+)?(?![\w-])"#), token: .number),
  ])
}
